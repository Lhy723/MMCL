import SwiftUI

struct DownloadsView: View {
    @ObservedObject var store: LauncherStore
    @State private var versionFilter: MinecraftVersion.ReleaseType? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            HStack(alignment: .center, spacing: 12) {
                Picker("下载源", selection: $store.selectedDownloadSource) {
                    ForEach(DownloadSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Button {
                    Task {
                        await store.refreshAvailableVersions()
                    }
                } label: {
                    Label("刷新版本", systemImage: "arrow.clockwise")
                }

                Button {
                    Task {
                        await store.executeQueuedDownloads()
                    }
                } label: {
                    Label("开始下载", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.downloadJobs.contains { $0.status == .queued })

                Button {
                    store.cancelDownloads()
                } label: {
                    Label("取消", systemImage: "xmark.circle")
                }
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
                .disabled(!store.downloadJobs.contains { $0.status == .running || $0.status == .paused })

                Button {
                    store.expandSelectedInstanceAssetIndex()
                } label: {
                    Label("展开资源", systemImage: "shippingbox")
                }

                Button {
                    store.prepareNativeLibrariesForSelectedInstance()
                } label: {
                    Label("准备 Native", systemImage: "square.and.arrow.down")
                }
                .disabled(store.plannedVersionMetadata == nil)
            }

            HStack(spacing: 16) {
                Label("\(store.downloadJobs.count) 个任务", systemImage: "square.stack.3d.up")
                Label(totalByteSummary, systemImage: "externaldrive.badge.checkmark")
                Label(store.speedTracker.bytesPerSecond > 0 ? ByteCountFormatter.string(fromByteCount: store.speedTracker.bytesPerSecond, countStyle: .file) + "/s" : "等待中", systemImage: "speedometer")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            DetailSection(title: "可用版本", systemImage: "list.bullet.rectangle") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("类型", selection: $versionFilter) {
                        Text("全部").tag(MinecraftVersion.ReleaseType?.none)
                        ForEach([MinecraftVersion.ReleaseType.release, .snapshot, .oldBeta, .oldAlpha], id: \.self) { type in
                            Text(type.label).tag(Optional(type))
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 400)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(filteredVersions) { version in
                                HStack {
                                    Text(version.id).font(.headline)
                                    Text(version.type.label).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("推荐 Java \(version.recommendedJavaMajorVersion)").foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }

            ForEach(store.downloadJobs) { job in
                DownloadJobRow(job: job)
            }

            Spacer()
        }
        .padding(24)
        .navigationTitle("下载中心")
    }

    private var totalByteSummary: String {
        let totalBytes = store.downloadJobs.reduce(Int64(0)) { $0 + $1.totalBytes }
        guard totalBytes > 0 else { return "总计 0 字节" }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    private var filteredVersions: [MinecraftVersion] {
        if let filter = versionFilter {
            return store.availableVersions.filter { $0.type == filter }
        }
        return store.availableVersions
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("下载中心")
                .font(.largeTitle.weight(.semibold))
            Text("下载任务会写入实例目录并进行 SHA-1 校验；全部完成后会自动准备 Native 并更新实例状态。")
                .foregroundStyle(.secondary)
        }
    }
}

private struct DownloadJobRow: View {
    let job: DownloadJob

    var body: some View {
        DetailSection(title: job.title, systemImage: "arrow.down.circle") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(job.source.rawValue)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(job.status.label)
                }
                ProgressView(value: job.progress)
                if let remoteURL = job.remoteURL {
                    Text(remoteURL.absoluteString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                if let sha1 = job.sha1 {
                    Text("SHA-1: \(sha1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text(job.destination.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct ContentProjectsView: View {
    @ObservedObject var store: LauncherStore
    @State private var searchText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Modrinth")
                    .font(.largeTitle.weight(.semibold))
                Text("搜索并安装 Mod、资源包、光影包。")
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("搜索 Mod...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await store.searchModrinth(query: searchText) }
                    }

                Button {
                    Task { await store.searchModrinth(query: searchText) }
                } label: {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if store.modrinthSearchResults.isEmpty && !searchText.isEmpty && store.modrinthSearchQuery == searchText {
                ContentUnavailableView("没有找到结果", systemImage: "magnifyingglass", description: Text("试试其他关键词"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.modrinthSearchResults) { result in
                            ModrinthSearchRow(result: result, store: store)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .navigationTitle("Modrinth")
    }
}

private struct ModrinthSearchRow: View {
    let result: ModrinthSearchResult
    @ObservedObject var store: LauncherStore

    var body: some View {
        Button {
            store.selectedModrinthProject = result
            store.showingModrinthDetail = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(result.title)
                            .font(.headline)
                        Text(result.projectType)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    Text(result.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 12) {
                        Label("\(result.downloads)", systemImage: "arrow.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(result.categories.prefix(3), id: \.self) { category in
                            Text(category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.tertiary, in: Capsule())
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("诊断日志")
                        .font(.largeTitle.weight(.semibold))
                    Text("中文诊断会聚合 Java、下载、实例文件和 Mod 冲突问题。")
                        .foregroundStyle(.secondary)
                }

                ForEach(store.diagnostics) { report in
                    DiagnosticReportView(report: report)
                }
            }
            .padding(24)
        }
        .navigationTitle("诊断日志")
    }
}

struct CurseForgeView: View {
    @ObservedObject var store: LauncherStore
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CurseForge")
                    .font(.largeTitle.weight(.semibold))
                Text("搜索 CurseForge 上的 Mod。")
                    .foregroundStyle(.secondary)
            }
            HStack {
                TextField("搜索 Mod...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await store.searchCurseForge(query: searchText) } }
                Button {
                    Task { await store.searchCurseForge(query: searchText) }
                } label: { Label("搜索", systemImage: "magnifyingglass") }
                .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.curseForgeResults) { result in
                        CurseForgeRow(result: result)
                    }
                }
            }
            Spacer()
        }
        .padding(24)
        .navigationTitle("CurseForge")
    }
}

private struct CurseForgeRow: View {
    let result: CurseForgeSearchResult
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.name)
                    .font(.headline)
                Text(result.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Label("\(result.downloadCount)", systemImage: "arrow.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DiagnosticReportView: View {
    let report: DiagnosticReport

    var body: some View {
        DetailSection(title: report.title, systemImage: iconName) {
            VStack(alignment: .leading, spacing: 10) {
                Text(report.localizedSeverity)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(report.summary)
                ForEach(report.suggestedActions, id: \.self) { action in
                    Label(action, systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var iconName: String {
        switch report.severity {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        Form {
            Section("启动") {
                TextField("默认离线用户名", text: $store.defaultOfflineUsername)
                Stepper("默认内存：\(store.defaultMemoryMegabytes) MB", value: $store.defaultMemoryMegabytes, in: 1024...16384, step: 512)
            }

            Section("显示") {
                HStack {
                    Text("默认分辨率")
                    Spacer()
                    Stepper("\(store.defaultResolutionWidth)x\(store.defaultResolutionHeight)", value: $store.defaultResolutionWidth, in: 640...3840, step: 32)
                }
            }

            Section("下载") {
                Picker("首选下载源", selection: $store.preferredDownloadSource) {
                    ForEach(DownloadSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
            }

            Section("语言") {
                Picker("界面语言", selection: $store.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
            }

            Section("JVM 预设") {
                ForEach(store.jvmPresets) { preset in
                    HStack {
                        Toggle(preset.name, isOn: Binding(
                            get: { preset.isEnabled },
                            set: { newValue in
                                if let idx = store.jvmPresets.firstIndex(where: { $0.id == preset.id }) {
                                    store.jvmPresets[idx].isEnabled = newValue
                                }
                            }
                        ))
                        Spacer()
                        Text(preset.arguments.joined(separator: " "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Section("外观") {
                Picker("配色方案", selection: $store.colorScheme) {
                    ForEach(AppColorScheme.allCases) { scheme in
                        Text(scheme.rawValue).tag(scheme)
                    }
                }
            }

            Section("账号") {
                ForEach(store.accounts) { account in
                    HStack {
                        Text(account.displayName)
                        Spacer()
                        Text(account.type == .microsoft ? "在线" : "离线")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            store.deleteAccount(account)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("添加离线账号") {
                    store.addOfflineAccount(username: store.defaultOfflineUsername)
                }

                Button {
                    Task { await store.startMicrosoftLogin() }
                } label: {
                    if store.isLoggingIn {
                        ProgressView()
                    } else {
                        Label("Microsoft 登录", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
                .disabled(store.isLoggingIn)

                if !store.deviceCodeMessage.isEmpty {
                    Text(store.deviceCodeMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("关于") {
                HStack {
                    Text("当前版本")
                    Spacer()
                    Text(store.currentVersion)
                }
                Button("检查更新") {
                    Task { await store.checkForUpdates() }
                }
                if store.updateAvailable, let v = store.latestVersion {
                    Text("新版本可用：\(v)")
                        .foregroundStyle(.blue)
                    Button {
                        Task { await store.downloadAndInstallUpdate() }
                    } label: {
                        Label(store.isDownloadingUpdate ? "下载中..." : "下载更新", systemImage: "arrow.down.circle.fill")
                    }
                    .disabled(store.isDownloadingUpdate || store.updateDownloadURL == nil)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 420)
    }
}
