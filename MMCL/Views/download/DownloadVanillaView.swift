import SwiftUI

struct DownloadVanillaView: View {
    @ObservedObject var store: LauncherStore
    @State private var versionFilter: MinecraftVersion.ReleaseType? = nil
    @State private var searchText: String = ""
    @State private var expandedVersion: String? = nil
    @State private var appeared = false
    @State private var selectedLoaders: [String: GameLoader] = [:]
    @State private var selectedLoaderVersions: [String: String] = [:]
    @State private var collapsedGroups: Set<String> = ["快照版", "远古版"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top)
            filterBar
                .padding(.horizontal)
                .padding(.top, 8)
            downloadControlBar
                .padding(.horizontal)
                .padding(.top, 8)
            versionList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("原版游戏")
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.mmclSpring(response: 0.4, dampingFraction: 0.85, scale: store.animationDurationScale)) {
                appeared = true
            }
        }
        .task {
            if store.availableVersions.isEmpty {
                await store.refreshAvailableVersions()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("原版游戏")
                .font(.largeTitle.weight(.semibold))
            Text("选择 Minecraft 版本并配置 Mod 加载器后下载安装。")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            TextField("搜索版本...", text: $searchText)
                .textFieldStyle(.roundedBorder)

            Picker("类型", selection: $versionFilter) {
                Text("全部").tag(MinecraftVersion.ReleaseType?.none)
                ForEach([MinecraftVersion.ReleaseType.release, .snapshot, .oldBeta, .oldAlpha], id: \.self) { type in
                    Text(type.label).tag(Optional(type))
                }
            }
            .pickerStyle(.menu)

            Spacer()

            Button {
                Task {
                    await store.refreshAvailableVersions()
                }
            } label: {
                Label("刷新版本", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Download Control Bar

    private var downloadControlBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("下载源", selection: $store.selectedDownloadSource) {
                    ForEach(DownloadSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    Task {
                        await store.executeQueuedDownloads()
                    }
                } label: {
                    Label("开始下载", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.downloadJobs.contains { $0.status == .queued })

                Button(role: .destructive) {
                    store.cancelDownloads()
                } label: {
                    Label("取消", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .disabled(!store.downloadJobs.contains { $0.status.isActive })

                Button {
                    if store.downloadJobs.contains(where: { $0.status == .running }) {
                        store.pauseDownloads()
                    } else if store.downloadJobs.contains(where: { $0.status == .paused }) {
                        store.resumeDownloads()
                    }
                } label: {
                    if store.downloadJobs.contains(where: { $0.status == .running }) {
                        Label("暂停", systemImage: "pause.circle")
                    } else {
                        Label("继续下载", systemImage: "play.circle")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!store.downloadJobs.contains { $0.status == .running || $0.status == .paused })
            }

            HStack(spacing: 16) {
                Label("\(store.taskGroups.count) 个安装任务", systemImage: "square.stack.3d.up")
                Label(store.speedTracker.bytesPerSecond > 0
                      ? ByteCountFormatter.string(fromByteCount: store.speedTracker.bytesPerSecond, countStyle: .file) + "/s"
                      : "等待中",
                      systemImage: "speedometer")
                if let current = store.taskGroups.first(where: { $0.status == .running })?.currentFileName {
                    Label(current, systemImage: "doc")
                        .lineLimit(1)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Version List

    private var versionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(groupedVersions, id: \.0) { group in
                    versionGroup(name: group.0, versions: group.1)
                }
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
    }

    private func versionGroup(name: String, versions: [MinecraftVersion]) -> some View {
        let isExpanded = Binding(
            get: { !collapsedGroups.contains(name) },
            set: { newValue in
                withAnimation(.mmclSpring(response: 0.35, dampingFraction: 0.85, scale: store.animationDurationScale)) {
                    if newValue {
                        collapsedGroups.remove(name)
                    } else {
                        collapsedGroups.insert(name)
                    }
                }
            }
        )

        return DisclosureGroup(isExpanded: isExpanded) {
            LazyVStack(spacing: 0) {
                ForEach(versions) { version in
                    versionRow(version)
                    if version.id != versions.last?.id {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
        } label: {
            HStack {
                Text(name)
                    .font(.headline)
                Text("\(versions.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .padding(.vertical, 4)
    }

    private func versionRow(_ version: MinecraftVersion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.mmclSpring(response: 0.35, dampingFraction: 0.85, scale: store.animationDurationScale)) {
                    if expandedVersion == version.id {
                        expandedVersion = nil
                    } else {
                        expandedVersion = version.id
                    }
                }
            } label: {
                HStack {
                    Image(versionIcon(for: version))
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text(version.id)
                        .font(.headline)
                    Text(version.type.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("推荐 Java \(version.recommendedJavaMajorVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: expandedVersion == version.id ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if expandedVersion == version.id {
                loaderSelectionSection(for: version)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Loader Selection

    private func loaderSelectionSection(for version: MinecraftVersion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mod 加载器（可选）")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 8) {
                loaderCard(name: "Forge", icon: "hammer", version: version.id)
                loaderCard(name: "NeoForge", icon: "hammer.fill", version: version.id)
                loaderCard(name: "Fabric", icon: "shippingbox", version: version.id)
                loaderCard(name: "Quilt", icon: "shippingbox.fill", version: version.id)
            }

            optifineCard(for: version)

            HStack {
                Spacer()
                Button {
                    let loader = selectedLoaders[version.id] ?? .vanilla
                    Task {
                        await store.createInstanceAndDownload(gameVersion: version.id, loader: loader)
                    }
                } label: {
                    Label("开始下载", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 8)
    }

    private func loaderCard(name: String, icon: String, version: String) -> some View {
        let loader = GameLoader(rawValue: name) ?? .vanilla
        let isSelected = selectedLoaders[version] == loader

        return Button {
            if isSelected {
                selectedLoaders.removeValue(forKey: version)
                selectedLoaderVersions.removeValue(forKey: version)
            } else {
                selectedLoaders[version] = loader
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(name)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .animation(.mmclSpring(response: 0.35, dampingFraction: 0.85, scale: store.animationDurationScale), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func optifineCard(for version: MinecraftVersion) -> some View {
        let isSelected = selectedLoaders[version.id] == .vanilla && selectedLoaderVersions[version.id]?.hasPrefix("optifine") == true

        return Button {
            if isSelected {
                selectedLoaders.removeValue(forKey: version.id)
                selectedLoaderVersions.removeValue(forKey: version.id)
            } else {
                selectedLoaders[version.id] = .vanilla
                selectedLoaderVersions[version.id] = "optifine"
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OptiFine")
                        .font(.subheadline.weight(.medium))
                    Text("与部分 Mod 加载器不兼容，请注意版本搭配")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .green : .secondary)
            }
            .padding(10)
            .background(isSelected ? Color.orange.opacity(0.1) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
            )
            .animation(.mmclSpring(response: 0.35, dampingFraction: 0.85, scale: store.animationDurationScale), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func versionIcon(for version: MinecraftVersion) -> String {
        switch version.type {
        case .release: return "Grass"
        case .snapshot: return "CommandBlock"
        case .oldBeta, .oldAlpha: return "CobbleStone"
        }
    }

    private var groupedVersions: [(String, [MinecraftVersion])] {
        let filtered = filteredVersions
        return [
            ("正式版", filtered.filter { $0.type == .release }),
            ("快照版", filtered.filter { $0.type == .snapshot }),
            ("远古版", filtered.filter { $0.type == .oldBeta || $0.type == .oldAlpha }),
        ].filter { !$0.1.isEmpty }
    }

    private var filteredVersions: [MinecraftVersion] {
        var versions = store.availableVersions

        if let filter = versionFilter {
            versions = versions.filter { $0.type == filter }
        }

        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            versions = versions.filter { $0.id.localizedCaseInsensitiveContains(searchText) }
        }

        return versions
    }
}

// MARK: - ReleaseType Extension

extension MinecraftVersion.ReleaseType {
    var groupLabel: String {
        switch self {
        case .release: return "正式版"
        case .snapshot: return "快照版"
        case .oldBeta, .oldAlpha: return "远古版"
        }
    }
}
