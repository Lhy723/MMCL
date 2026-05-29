import SwiftUI

// MARK: - Image Cache

private final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, NSImage>()

    func get(_ url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }
}

// MARK: - Cached Async Image

private struct CachedAsyncImage: View {
    let url: URL?
    var placeholder: AnyView = AnyView(ProgressView())

    @State private var image: NSImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
                    .onAppear { load() }
            }
        }
    }

    private func load() {
        guard let url, !isLoading else { return }
        if let cached = ImageCache.shared.get(url) {
            image = cached
            return
        }
        isLoading = true
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let uiImage = NSImage(data: data) else {
                isLoading = false
                return
            }
            ImageCache.shared.set(uiImage, for: url)
            image = uiImage
        }
    }
}

// MARK: - Community Source

enum CommunitySource: String, CaseIterable, Identifiable {
    case all = "全部"
    case modrinth = "Modrinth"
    case curseforge = "CurseForge"

    var id: String { rawValue }
}

// MARK: - Resource Category

enum ResourceCategory: String, CaseIterable, Identifiable {
    case all = "全部"
    case technology = "科技"
    case magic = "魔法"
    case adventure = "冒险"
    case decoration = "装饰"
    case storage = "存储"
    case utility = "工具"
    case performance = "性能"
    case worldGen = "世界生成"
    case library = "前置库"
    case optimization = "优化"
    case audio = "音效"
    case texture = "材质"
    case pvp = "PvP"
    case quest = "任务"
    case map = "地图"
    case modpack = "整合"

    var id: String { rawValue }

    var modrinthFacet: String? {
        switch self {
        case .all: return nil
        case .technology: return "categories:technology"
        case .magic: return "categories:magic"
        case .adventure: return "categories:adventure"
        case .decoration: return "categories:decoration"
        case .storage: return "categories:storage"
        case .utility: return "categories:utility"
        case .performance: return "categories:performance"
        case .worldGen: return "categories:worldgen"
        case .library: return "categories:library"
        case .optimization: return "categories:optimization"
        case .audio: return "categories:audio"
        case .texture: return "categories:decoration"
        case .pvp: return "categories:pvp"
        case .quest: return "categories:quest"
        case .map: return "categories:worldgen"
        case .modpack: return "categories:modpack"
        }
    }
}

// MARK: - Resource Search Result

enum ResourceSearchItem: Identifiable {
    case modrinth(ModrinthSearchResult)
    case curseforge(CurseForgeSearchResult)

    var id: String {
        switch self {
        case .modrinth(let r): return "modrinth-\(r.id)"
        case .curseforge(let r): return "curseforge-\(r.id)"
        }
    }

    var title: String {
        switch self {
        case .modrinth(let r): return r.title
        case .curseforge(let r): return r.name
        }
    }

    var description: String {
        switch self {
        case .modrinth(let r): return r.description
        case .curseforge(let r): return r.summary
        }
    }

    var downloads: Int {
        switch self {
        case .modrinth(let r): return r.downloads
        case .curseforge(let r): return r.downloadCount
        }
    }

    var author: String? {
        switch self {
        case .modrinth(let r): return r.author
        case .curseforge: return nil
        }
    }

    var formattedDate: String? {
        switch self {
        case .modrinth(let r): return r.formattedDate
        case .curseforge: return nil
        }
    }

    var displayTags: [String] {
        switch self {
        case .modrinth(let r): return r.displayTags
        case .curseforge: return []
        }
    }

    var source: CommunitySource {
        switch self {
        case .modrinth: return .modrinth
        case .curseforge: return .curseforge
        }
    }
}

// MARK: - Resource Search View

struct DownloadResourceSearchView: View {
    @ObservedObject var store: LauncherStore
    let title: String
    let icon: String
    let projectType: String
    let showLoaderFilter: Bool

    @State private var searchText: String = ""
    @State private var selectedSource: CommunitySource = .all
    @State private var selectedVersion: String? = nil
    @State private var selectedLoader: String? = nil
    @State private var selectedCategory: ResourceCategory = .all
    @State private var searchResults: [ResourceSearchItem] = []
    @State private var visibleIDs: Set<String> = []
    @State private var isLoading: Bool = false
    @State private var isLoadingMore: Bool = false
    @State private var errorMessage: String? = nil
    @State private var totalHits: Int = 0
    @State private var currentOffset: Int = 0
    @State private var hasSearched: Bool = false
    @State private var appeared = false

    private let commonVersions = ["全部", "1.21.x", "1.20.x", "1.19.x", "1.18.x", "1.16.5", "1.12.2", "1.7.10"]
    private let loaderOptions = ["任意", "Forge", "NeoForge", "Fabric", "Quilt"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top)
            instanceBar
                .padding(.horizontal)
                .padding(.top, 8)
            searchBar
                .padding(.horizontal)
                .padding(.top, 8)
            filterBar
                .padding(.horizontal)
                .padding(.top, 8)
            resultsList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(title)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.mmclSpring(response: 0.4, dampingFraction: 0.85, scale: store.animationDurationScale)) {
                appeared = true
            }
            if searchResults.isEmpty {
                loadPopular()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.weight(.semibold))
            Text("从 Modrinth 和 CurseForge 搜索并下载\(title)。")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Instance Bar

    private var instanceBar: some View {
        HStack(spacing: 12) {
            Text("安装到").foregroundStyle(.secondary)
            Picker("实例", selection: $store.launcherSelectedInstanceID) {
                Text("未选择").tag(LauncherInstance.ID?.none)
                ForEach(store.instances) { instance in
                    HStack {
                        Image(systemName: "cube.box")
                        Text(instance.name)
                    }
                    .tag(Optional(instance.id))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 280)

            if store.selectedInstance != nil {
                Label("已选择", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label("请先选择实例", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            TextField("搜索\(title)...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    performSearch()
                }

            Button {
                performSearch()
            } label: {
                Label("搜索", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("来源", selection: $selectedSource) {
                    ForEach(CommunitySource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.menu)

                Picker("版本", selection: $selectedVersion) {
                    Text("全部").tag(String?.none)
                    ForEach(commonVersions, id: \.self) { version in
                        Text(version).tag(Optional(version))
                    }
                }
                .pickerStyle(.menu)

                if showLoaderFilter {
                    Picker("加载器", selection: $selectedLoader) {
                        Text("任意").tag(String?.none)
                        ForEach(loaderOptions.dropFirst(), id: \.self) { loader in
                            Text(loader).tag(Optional(loader))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Picker("分类", selection: $selectedCategory) {
                    ForEach(ResourceCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.menu)

                Spacer()
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        Group {
            if searchResults.isEmpty && !isLoading && hasSearched {
                ContentUnavailableView("没有找到结果", systemImage: "magnifyingglass", description: Text("试试其他关键词或筛选条件"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults) { item in
                            resourceRow(item)
                                .opacity(visibleIDs.contains(item.id) ? 1 : 0)
                                .offset(x: visibleIDs.contains(item.id) ? 0 : 20)
                                .onAppear {
                                    if !visibleIDs.contains(item.id) {
                                        withAnimation(.mmclSpring(response: 0.5, dampingFraction: 0.85, scale: store.animationDurationScale)) {
                                            visibleIDs.insert(item.id)
                                        }
                                    }
                                }
                                .onDisappear {
                                    visibleIDs.remove(item.id)
                                }
                        }

                        if !searchResults.isEmpty && currentOffset < totalHits {
                            HStack {
                                Spacer()
                                if isLoadingMore {
                                    ProgressView()
                                } else {
                                    Button("加载更多") {
                                        loadMore()
                                    }
                                    .buttonStyle(.bordered)
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .animation(.mmclSpring(response: 0.4, dampingFraction: 0.85, scale: store.animationDurationScale), value: searchResults.count)
            }
        }
    }

    private func resourceRow(_ item: ResourceSearchItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            iconView(for: item)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title)
                        .font(.headline)
                    Text(item.source.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let author = item.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(item.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label("\(item.downloads)", systemImage: "arrow.down")
                    if let date = item.formattedDate {
                        Label(date, systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !item.displayTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(item.displayTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
            Spacer()
            Button {
                installItem(item)
            } label: {
                Label("安装", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private func iconView(for item: ResourceSearchItem) -> some View {
        switch item {
        case .modrinth(let result):
            if let url = result.iconURLResolved {
                CachedAsyncImage(url: url, placeholder: AnyView(
                    placeholderIcon(tint: result.tintColor)
                ))
            } else {
                placeholderIcon(tint: result.tintColor)
            }
        case .curseforge:
            placeholderIcon(tint: nil)
        }
    }

    private func placeholderIcon(tint: Color?) -> some View {
        Rectangle()
            .fill(tint?.opacity(0.2) ?? Color.secondary.opacity(0.1))
            .overlay {
                Image(systemName: "puzzlepiece.extension")
                    .foregroundStyle(tint ?? .secondary)
            }
    }

    private func installItem(_ item: ResourceSearchItem) {
        switch item {
        case .modrinth(let result):
            store.selectedModrinthProject = result
            store.showingModrinthDetail = true
        case .curseforge:
            // CurseForge direct download not yet implemented
            errorMessage = "CurseForge 直接安装暂未实现，请使用 Modrinth 搜索"
        }
    }

    // MARK: - CurseForge Class IDs

    private var curseforgeClassId: Int? {
        switch projectType {
        case "mod": return 6
        case "modpack": return 4471
        case "resourcepack": return 12
        case "shader": return 4546
        case "datapack": return 5
        default: return nil
        }
    }

    // MARK: - Search

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        hasSearched = true
        currentOffset = 0
        visibleIDs = []

        Task {
            let result = await searchModrinth(query: query, offset: 0)
            searchResults = result.items
            totalHits = result.total
            isLoading = false
        }
    }

    private func loadPopular() {
        isLoading = true
        errorMessage = nil
        hasSearched = false
        currentOffset = 0
        visibleIDs = []

        Task {
            let result = await searchModrinth(query: "", index: "downloads", offset: 0)
            searchResults = result.items
            totalHits = result.total
            isLoading = false
        }
    }

    private func loadMore() {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        let nextOffset = currentOffset + 20

        Task {
            let query = hasSearched ? searchText.trimmingCharacters(in: .whitespaces) : ""
            let index = hasSearched ? "relevance" : "downloads"
            let result = await searchModrinth(query: query, index: index, offset: nextOffset)
            searchResults.append(contentsOf: result.items)
            currentOffset = nextOffset
            totalHits = result.total
            isLoadingMore = false
        }
    }

    private func searchModrinth(query: String, index: String = "relevance", offset: Int) async -> (items: [ResourceSearchItem], total: Int) {
        var items: [ResourceSearchItem] = []
        var total = 0

        if selectedSource == .all || selectedSource == .modrinth {
            do {
                var facets: [[String]] = [["project_type:\(projectType)"]]
                if let categoryFacet = selectedCategory.modrinthFacet {
                    facets.append([categoryFacet])
                }
                let response = try await store.modrinthService.search(query: query, facets: facets, index: index, offset: offset)
                items.append(contentsOf: response.hits.map { .modrinth($0) })
                total = response.totalHits
            } catch {
                errorMessage = "Modrinth: \(error.localizedDescription)"
            }
        }

        // CurseForge (only when API key is provided)
        if offset == 0 && !store.curseForgeApiKey.isEmpty && (selectedSource == .all || selectedSource == .curseforge) {
            do {
                let gameVersion = selectedVersion?.replacingOccurrences(of: ".x", with: "")
                let cfResults = try await store.curseForgeService.search(query: query, classId: curseforgeClassId, gameVersion: gameVersion, apiKey: store.curseForgeApiKey)
                items.append(contentsOf: cfResults.map { .curseforge($0) })
            } catch {
                // silently ignore CurseForge errors when key is provided
            }
        }

        return (items, total)
    }
}
