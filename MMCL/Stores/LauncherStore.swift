import Combine
import Foundation

final class LauncherStore: ObservableObject {
    enum Section: Hashable {
        case instance(UUID)
        case downloads
        case content
        case diagnostics
    }

    @Published var instances: [LauncherInstance]
    @Published var downloadJobs: [DownloadJob]
    @Published var featuredProjects: [ContentProject]
    @Published var diagnostics: [DiagnosticReport]
    @Published var javaRuntimes: [JavaRuntime]
    @Published var availableVersions: [MinecraftVersion]
    @Published var selectedSection: Section?
    @Published var selectedDownloadSource: DownloadSource
    @Published var selectedJavaRuntimeID: JavaRuntime.ID?
    @Published var currentLaunchSession: LaunchSession?
    @Published var plannedVersionMetadata: VersionMetadata?
    @Published var plannedInstanceID: LauncherInstance.ID?

    @Published var defaultMemoryMegabytes: Int = 4096
    @Published var defaultOfflineUsername: String = "Steve"
    @Published var preferredDownloadSource: DownloadSource = .bmclapi
    @Published var showingCreateSheet: Bool = false
    @Published var showingLogSheet: Bool = false
    @Published var showingRenameSheet: Bool = false
    @Published var showingModList: Bool = false
    @Published var showingResourcePacks: Bool = false

    @Published var accounts: [MinecraftAccount] = []
    @Published var selectedAccountID: MinecraftAccount.ID?
    @Published var isLoggingIn = false
    @Published var deviceCodeMessage: String = ""

    @Published var modrinthSearchResults: [ModrinthSearchResult] = []
    @Published var modrinthSearchQuery: String = ""
    @Published var showingModrinthDetail: Bool = false
    @Published var selectedModrinthProject: ModrinthSearchResult?

    private let launchService: LaunchServicing
    private let downloadService: DownloadServicing
    private let versionService: VersionManifestServicing
    private let javaRuntimeService: JavaRuntimeServicing
    private let instanceService: InstanceServicing
    private let fabricService: FabricServicing
    private let quiltService: QuiltServicing
    private let forgeService: ForgeServicing
    let modrinthService: ModrinthServicing
    private let authService: AuthServicing

    init(
        instances: [LauncherInstance] = LauncherStore.sampleInstances,
        downloadJobs: [DownloadJob] = LauncherStore.sampleDownloadJobs,
        featuredProjects: [ContentProject] = LauncherStore.sampleProjects,
        diagnostics: [DiagnosticReport] = LauncherStore.sampleDiagnostics,
        selectedDownloadSource: DownloadSource = .bmclapi,
        javaRuntimes: [JavaRuntime] = LauncherStore.sampleJavaRuntimes,
        availableVersions: [MinecraftVersion] = LauncherStore.sampleVersions,
        launchService: LaunchServicing = LaunchService(),
        downloadService: DownloadServicing = DownloadService(),
        versionService: VersionManifestServicing = VersionManifestService(),
        javaRuntimeService: JavaRuntimeServicing = JavaRuntimeService(),
        instanceService: InstanceServicing = InstanceService(),
        fabricService: FabricServicing = FabricService(),
        quiltService: QuiltServicing = QuiltService(),
        forgeService: ForgeServicing = ForgeService(),
        modrinthService: ModrinthServicing = ModrinthService(),
        authService: AuthServicing = AuthService()
    ) {
        self.instances = instances
        self.downloadJobs = downloadJobs
        self.featuredProjects = featuredProjects
        self.diagnostics = diagnostics
        self.selectedDownloadSource = selectedDownloadSource
        self.javaRuntimes = javaRuntimes
        self.availableVersions = availableVersions
        self.launchService = launchService
        self.downloadService = downloadService
        self.versionService = versionService
        self.javaRuntimeService = javaRuntimeService
        self.instanceService = instanceService
        self.fabricService = fabricService
        self.quiltService = quiltService
        self.forgeService = forgeService
        self.modrinthService = modrinthService
        self.authService = authService
        self.selectedJavaRuntimeID = javaRuntimes.first?.id
        self.selectedSection = instances.first.map { .instance($0.id) } ?? .downloads
    }

    var selectedInstance: LauncherInstance? {
        guard case .instance(let id) = selectedSection else { return nil }
        return instances.first { $0.id == id }
    }

    func selectFirstInstanceIfNeeded() {
        if selectedSection == nil {
            selectedSection = instances.first.map { .instance($0.id) }
        }
    }

    func startMicrosoftLogin() async {
        isLoggingIn = true
        do {
            let deviceCode = try await authService.startDeviceCodeFlow()
            deviceCodeMessage = "请在浏览器中打开 \(deviceCode.verificationUri)，输入代码：\(deviceCode.userCode)"
            let token = try await authService.pollForToken(deviceCode: deviceCode.deviceCode, interval: deviceCode.interval)

            let xblToken = try await authService.exchangeForXBLToken(accessToken: token.accessToken)
            let xstsToken = try await authService.exchangeForXSTSToken(xblToken: xblToken.token)
            let mcToken = try await authService.exchangeForMinecraftToken(xstsToken: xstsToken.token)
            let profile = try await authService.fetchMinecraftProfile(accessToken: mcToken.accessToken)

            let account = MinecraftAccount(
                username: profile.name,
                uuid: profile.id,
                accessToken: mcToken.accessToken,
                refreshToken: token.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(mcToken.expiresInSeconds)),
                type: .microsoft
            )

            if !accounts.contains(where: { $0.uuid == account.uuid }) {
                accounts.append(account)
            }
            selectedAccountID = account.id
            isLoggingIn = false
            deviceCodeMessage = ""
            diagnostics.insert(
                DiagnosticReport(
                    title: "登录成功",
                    severity: .info,
                    summary: "已登录 Microsoft 账号 \(profile.name)。",
                    suggestedActions: ["启动游戏将使用在线模式"]
                ),
                at: 0
            )
        } catch {
            isLoggingIn = false
            deviceCodeMessage = ""
            diagnostics.insert(
                DiagnosticReport(
                    title: "登录失败",
                    severity: .error,
                    summary: error.localizedDescription,
                    suggestedActions: ["检查网络连接", "确认 Microsoft 账号已购买 Minecraft"]
                ),
                at: 0
            )
        }
    }

    func addOfflineAccount(username: String) {
        let account = MinecraftAccount(username: username, type: .offline)
        accounts.append(account)
        selectedAccountID = account.id
    }

    func deleteAccount(_ account: MinecraftAccount) {
        accounts.removeAll { $0.id == account.id }
        if selectedAccountID == account.id {
            selectedAccountID = accounts.first?.id
        }
    }

    var selectedAccount: MinecraftAccount? {
        guard let selectedAccountID else { return accounts.first }
        return accounts.first { $0.id == selectedAccountID } ?? accounts.first
    }

    func createInstance(
        name: String,
        gameVersion: String,
        loader: GameLoader,
        memory: Int? = nil,
        username: String? = nil,
        jvmArgs: [String] = []
    ) {
        let profile = LaunchProfile(
            offlineUsername: username ?? defaultOfflineUsername,
            memoryMegabytes: memory ?? defaultMemoryMegabytes,
            jvmArguments: jvmArgs
        )
        do {
            let instance = try instanceService.createInstance(
                name: name,
                gameVersion: gameVersion,
                loader: loader,
                profile: profile
            )
            instances.append(instance)
            selectedSection = .instance(instance.id)
            showingCreateSheet = false
            diagnostics.insert(
                DiagnosticReport(
                    title: "实例已创建",
                    severity: .info,
                    summary: "\(name) 已创建，游戏版本 \(gameVersion)，加载器 \(loader.rawValue)。",
                    suggestedActions: ["生成安装计划并下载游戏文件"]
                ),
                at: 0
            )
        } catch {
            diagnostics.insert(
                DiagnosticReport(
                    title: "实例创建失败",
                    severity: .error,
                    summary: error.localizedDescription,
                    suggestedActions: ["检查磁盘空间和目录权限"]
                ),
                at: 0
            )
        }
    }

    func loadLogContent(for instance: LauncherInstance) -> String {
        let logURL = instance.rootDirectory
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("latest.log")
        guard let data = try? Data(contentsOf: logURL) else {
            return "日志文件不存在：\(logURL.path)"
        }
        return String(decoding: data, as: UTF8.self)
    }

    func deleteInstance(_ instance: LauncherInstance) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: instance.rootDirectory.path) {
            do {
                try fileManager.removeItem(at: instance.rootDirectory)
            } catch {
                diagnostics.insert(
                    DiagnosticReport(
                        title: "删除实例目录失败",
                        severity: .warning,
                        summary: "\(instance.name)：\(error.localizedDescription)",
                        suggestedActions: ["检查文件权限", "手动删除目录"]
                    ),
                    at: 0
                )
            }
        }
        instances.removeAll { $0.id == instance.id }
        if case .instance(let id) = selectedSection, id == instance.id {
            selectedSection = instances.first.map { .instance($0.id) } ?? .downloads
        }
        diagnostics.insert(
            DiagnosticReport(
                title: "实例已删除",
                severity: .info,
                summary: "\(instance.name) 已移除。",
                suggestedActions: []
            ),
            at: 0
        )
    }

    func renameInstance(_ instance: LauncherInstance, to newName: String) {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let index = instances.firstIndex(where: { $0.id == instance.id }) else { return }
        instances[index].name = newName
        do {
            let data = try instanceService.encode(instances[index])
            try data.write(to: instanceService.instanceFileURL(for: instances[index]), options: .atomic)
        } catch {
            diagnostics.insert(
                DiagnosticReport(title: "重命名失败", severity: .error, summary: error.localizedDescription, suggestedActions: ["检查文件权限"]),
                at: 0
            )
        }
    }

    func copyInstance(_ instance: LauncherInstance) {
        let newName = "\(instance.name)（副本）"
        let profile = LaunchProfile(
            offlineUsername: instance.profile.offlineUsername,
            memoryMegabytes: instance.profile.memoryMegabytes,
            jvmArguments: instance.profile.jvmArguments
        )
        do {
            let copy = try instanceService.createInstance(
                name: newName,
                gameVersion: instance.gameVersion,
                loader: instance.loader,
                profile: profile
            )
            instances.append(copy)
            selectedSection = .instance(copy.id)
            diagnostics.insert(
                DiagnosticReport(title: "实例已复制", severity: .info, summary: "\(instance.name) 已复制为 \(newName)。", suggestedActions: []),
                at: 0
            )
        } catch {
            diagnostics.insert(
                DiagnosticReport(title: "复制失败", severity: .error, summary: error.localizedDescription, suggestedActions: []),
                at: 0
            )
        }
    }

    func scanInstalledMods(for instance: LauncherInstance) -> [ModInfo] {
        let modsDir = instance.rootDirectory.appendingPathComponent("mods", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: modsDir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "jar" || $0.pathExtension == "disabled" }
            .map { url in
                let isEnabled = url.pathExtension == "jar"
                let actualURL = isEnabled ? url : url.deletingPathExtension()
                let size = (try? actualURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let name = actualURL.lastPathComponent
                return ModInfo(fileName: name, isEnabled: isEnabled, size: Int64(size))
            }
            .sorted { $0.fileName < $1.fileName }
    }

    func toggleMod(for instance: LauncherInstance, mod: ModInfo) {
        let modsDir = instance.rootDirectory.appendingPathComponent("mods", isDirectory: true)
        let currentURL = modsDir.appendingPathComponent(mod.fileName + (mod.isEnabled ? ".jar" : ".jar.disabled"))
        let newURL = modsDir.appendingPathComponent(mod.fileName + (mod.isEnabled ? ".jar.disabled" : ".jar"))
        try? FileManager.default.moveItem(at: currentURL, to: newURL)
    }

    func deleteMod(for instance: LauncherInstance, mod: ModInfo) {
        let modsDir = instance.rootDirectory.appendingPathComponent("mods", isDirectory: true)
        let fileName = mod.fileName + (mod.isEnabled ? ".jar" : ".jar.disabled")
        try? FileManager.default.removeItem(at: modsDir.appendingPathComponent(fileName))
    }

    func scanResourcePacks(for instance: LauncherInstance) -> [ResourcePackInfo] {
        let dir = instance.rootDirectory.appendingPathComponent(".minecraft/resourcepacks", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return [] }
        return files
            .filter { $0.pathExtension == "zip" }
            .map { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return ResourcePackInfo(fileName: url.lastPathComponent, isEnabled: true, size: Int64(size))
            }
            .sorted { $0.fileName < $1.fileName }
    }

    func deleteResourcePack(for instance: LauncherInstance, pack: ResourcePackInfo) {
        let dir = instance.rootDirectory.appendingPathComponent(".minecraft/resourcepacks", isDirectory: true)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(pack.fileName))
    }

    var selectedJavaRuntime: JavaRuntime? {
        guard let selectedJavaRuntimeID else { return javaRuntimes.first }
        return javaRuntimes.first { $0.id == selectedJavaRuntimeID } ?? javaRuntimes.first
    }

    func launchPreviewForSelectedInstance() -> LaunchPreview? {
        guard let selectedInstance, let selectedJavaRuntime else { return nil }
        return LaunchPreview(
            instance: selectedInstance,
            java: selectedJavaRuntime,
            command: launchService.previewCommand(for: selectedInstance, java: selectedJavaRuntime)
        )
    }

    func launchSelectedInstance() {
        guard let selectedInstance else {
            diagnostics.insert(
                DiagnosticReport(
                    title: "未选择实例",
                    severity: .error,
                    summary: "需要先选择实例才能启动 Minecraft。",
                    suggestedActions: ["从侧边栏选择一个实例"]
                ),
                at: 0
            )
            return
        }

        guard let selectedJavaRuntime else {
            diagnostics.insert(
                DiagnosticReport(
                    title: "缺少 Java 运行时",
                    severity: .error,
                    summary: "没有可用于启动 \(selectedInstance.name) 的 Java。",
                    suggestedActions: ["点击重新扫描 Java", "安装推荐版本 Java \(javaRuntimeService.recommendedMajorVersion(for: selectedInstance.gameVersion))"]
                ),
                at: 0
            )
            return
        }

        let preflightReport = launchService.preflight(instance: selectedInstance, java: selectedJavaRuntime)
        guard preflightReport.canLaunch else {
            updateInstanceStatus(selectedInstance.id, status: .missingFiles)
            diagnostics.insert(preflightReport.diagnostic(), at: 0)
            return
        }

        if preflightReport.severity == .warning {
            diagnostics.insert(
                preflightReport.diagnostic(title: "启动前检查有提醒"),
                at: 0
            )
        }

        do {
            let session = try launchService.launch(instance: selectedInstance, java: selectedJavaRuntime)
            currentLaunchSession = session
            monitorLaunchSession()
            diagnostics.insert(
                DiagnosticReport(
                    title: "Minecraft 已启动",
                    severity: .info,
                    summary: "进程 \(session.processIdentifier) 已启动，日志写入 \(session.logFileURL.path)。",
                    suggestedActions: ["打开日志查看启动输出", "如果游戏窗口未出现，检查诊断日志"]
                ),
                at: 0
            )
        } catch {
            diagnostics.insert(
                DiagnosticReport(
                    title: "启动失败",
                    severity: .error,
                    summary: error.localizedDescription,
                    suggestedActions: ["检查 Java 路径是否存在", "确认实例文件已经下载完整"]
                ),
                at: 0
            )
        }
    }

    func inspectSelectedInstance() {
        guard let selectedInstance else {
            diagnostics.insert(
                DiagnosticReport(
                    title: "未选择实例",
                    severity: .error,
                    summary: "需要先选择实例才能检查启动环境。",
                    suggestedActions: ["从侧边栏选择一个实例"]
                ),
                at: 0
            )
            return
        }

        guard let selectedJavaRuntime else {
            updateInstanceStatus(selectedInstance.id, status: .needsJava)
            diagnostics.insert(
                DiagnosticReport(
                    title: "实例需要 Java",
                    severity: .error,
                    summary: "没有可用于检查 \(selectedInstance.name) 的 Java。",
                    suggestedActions: ["点击重新扫描 Java", "安装推荐版本 Java \(javaRuntimeService.recommendedMajorVersion(for: selectedInstance.gameVersion))"]
                ),
                at: 0
            )
            return
        }

        let report = launchService.preflight(instance: selectedInstance, java: selectedJavaRuntime)
        let title: String
        switch report.severity {
        case .info:
            title = "实例可启动"
            updateInstanceStatus(selectedInstance.id, status: .ready)
        case .warning:
            title = "实例有启动提醒"
        case .error:
            title = "实例需要修复"
            updateInstanceStatus(selectedInstance.id, status: .missingFiles)
        }
        diagnostics.insert(report.diagnostic(title: title), at: 0)
    }

    func repairSelectedInstance() async {
        guard let selectedInstance else {
            diagnostics.insert(
                DiagnosticReport(
                    title: "未选择实例",
                    severity: .error,
                    summary: "需要先选择实例才能生成修复任务。",
                    suggestedActions: ["从侧边栏选择一个实例"]
                ),
                at: 0
            )
            return
        }

        do {
            let metadata = try await repairMetadata(for: selectedInstance)
            plannedVersionMetadata = metadata
            plannedInstanceID = selectedInstance.id
            _ = try downloadService.writeVersionMetadata(metadata: metadata, instance: selectedInstance)

            let jobs = downloadService.makeVanillaRepairJobs(
                metadata: metadata,
                instance: selectedInstance,
                source: selectedDownloadSource
            )
            downloadJobs = jobs
            updateInstanceStatus(selectedInstance.id, status: jobs.isEmpty ? .ready : .missingFiles)
            diagnostics.insert(
                DiagnosticReport(
                    title: jobs.isEmpty ? "实例文件已完整" : "已生成修复任务",
                    severity: jobs.isEmpty ? .info : .warning,
                    summary: jobs.isEmpty ? "\(selectedInstance.name) 没有发现需要重新下载的核心文件。" : "已为 \(selectedInstance.name) 生成 \(jobs.count) 个缺失文件下载任务。",
                    suggestedActions: jobs.isEmpty ? ["准备 Native 后启动"] : ["打开下载中心执行修复任务", "下载完成后准备 Native"]
                ),
                at: 0
            )
            selectedSection = jobs.isEmpty ? .instance(selectedInstance.id) : .downloads
        } catch {
            diagnostics.insert(
                DiagnosticReport(
                    title: "修复任务生成失败",
                    severity: .error,
                    summary: error.localizedDescription,
                    suggestedActions: ["刷新版本列表", "重新生成安装计划"]
                ),
                at: 0
            )
        }
    }

    func refreshJavaRuntimes() async {
        do {
            let runtimes = try await javaRuntimeService.discoverInstalledRuntimes()
            javaRuntimes = runtimes
            selectRecommendedJavaRuntime()
            diagnostics.insert(
                DiagnosticReport(
                    title: "Java 运行时已刷新",
                    severity: runtimes.isEmpty ? .warning : .info,
                    summary: runtimes.isEmpty ? "没有发现可用的 Java 运行时。" : "发现 \(runtimes.count) 个 Java 运行时。",
                    suggestedActions: runtimes.isEmpty ? ["安装 Temurin Java 21", "刷新后重新选择实例"] : ["确认实例使用推荐 Java 版本"]
                ),
                at: 0
            )
        } catch {
            diagnostics.insert(
                DiagnosticReport(
                    title: "Java 扫描失败",
                    severity: .error,
                    summary: error.localizedDescription,
                    suggestedActions: ["确认 /usr/libexec/java_home 可用", "手动安装 Java 后重试"]
                ),
                at: 0
            )
        }
    }

    private func selectRecommendedJavaRuntime() {
        guard let selectedInstance else {
            selectedJavaRuntimeID = javaRuntimes.first?.id
            return
        }
        let recommendedMajor = javaRuntimeService.recommendedMajorVersion(for: selectedInstance.gameVersion)
        selectedJavaRuntimeID = javaRuntimes.first { $0.majorVersion == recommendedMajor }?.id ?? javaRuntimes.first?.id
    }

    func planVanillaInstall(metadata: VersionMetadata, assetIndex: AssetIndex? = nil, for instance: LauncherInstance) {
        plannedVersionMetadata = metadata
        plannedInstanceID = instance.id
        do {
            _ = try downloadService.writeVersionMetadata(metadata: metadata, instance: instance)
        } catch {
            diagnostics.insert(
                DiagnosticReport(
                    title: "版本元数据写入失败",
                    severity: .error,
                    summary: error.localizedDescription,
                    suggestedActions: ["检查实例目录权限", "重新创建实例后再生成安装计划"]
                ),
                at: 0
            )
        }
        var jobs = downloadService.makeVanillaInstallJobs(
            metadata: metadata,
            instance: instance,
            source: selectedDownloadSource
        )
        if let assetIndex {
            jobs.append(contentsOf: downloadService.makeAssetObjectJobs(
                assetIndex: assetIndex,
                instance: instance,
                source: selectedDownloadSource
            ))
        }
        downloadJobs = jobs
        diagnostics.insert(
            DiagnosticReport(
                title: "已生成 Vanilla 安装计划",
                severity: .info,
                summary: "已为 \(instance.name) 生成 \(downloadJobs.count) 个下载任务。",
                suggestedActions: ["打开下载中心检查任务", "点击开始下载执行任务并校验 SHA-1"]
            ),
            at: 0
        )
        selectedSection = .downloads
    }

    func installFabricLoader(for instance: LauncherInstance) async {
        do {
            let metadata = try await fabricService.installFabric(
                gameVersion: instance.gameVersion,
                loaderVersion: nil,
                instance: instance
            )
            plannedVersionMetadata = metadata
            plannedInstanceID = instance.id

            // Generate install jobs for the new metadata
            let jobs = downloadService.makeVanillaInstallJobs(
                metadata: metadata,
                instance: instance,
                source: selectedDownloadSource
            )
            downloadJobs = jobs
            updateInstanceStatus(instance.id, status: .missingFiles)
            diagnostics.insert(
                DiagnosticReport(
                    title: "Fabric loader 已安装",
                    severity: .info,
                    summary: "已为 \(instance.name) 安装 Fabric loader，生成 \(jobs.count) 个下载任务。",
                    suggestedActions: ["打开下载中心执行任务", "下载完成后启动游戏"]
                ),
                at: 0
            )
            selectedSection = .downloads
        } catch {
            diagnostics.insert(
                DiagnosticReport(
                    title: "Fabric loader 安装失败",
                    severity: .error,
                    summary: error.localizedDescription,
                    suggestedActions: ["确认已安装基础版本", "检查网络连接"]
                ),
                at: 0
            )
        }
    }

    func installQuiltLoader(for instance: LauncherInstance) async {
        do {
            let metadata = try await quiltService.installQuilt(gameVersion: instance.gameVersion, loaderVersion: nil, instance: instance)
            plannedVersionMetadata = metadata
            plannedInstanceID = instance.id
            let jobs = downloadService.makeVanillaInstallJobs(metadata: metadata, instance: instance, source: selectedDownloadSource)
            downloadJobs = jobs
            updateInstanceStatus(instance.id, status: .missingFiles)
            diagnostics.insert(DiagnosticReport(title: "Quilt loader 已安装", severity: .info, summary: "已为 \(instance.name) 安装 Quilt loader，生成 \(jobs.count) 个下载任务。", suggestedActions: ["打开下载中心执行任务"]), at: 0)
            selectedSection = .downloads
        } catch {
            diagnostics.insert(DiagnosticReport(title: "Quilt loader 安装失败", severity: .error, summary: error.localizedDescription, suggestedActions: ["确认已安装基础版本", "检查网络连接"]), at: 0)
        }
    }

    func installForgeLoader(for instance: LauncherInstance) async {
        do {
            let metadata = try await forgeService.installForge(gameVersion: instance.gameVersion, forgeVersion: nil, instance: instance)
            plannedVersionMetadata = metadata
            plannedInstanceID = instance.id
            let jobs = downloadService.makeVanillaInstallJobs(metadata: metadata, instance: instance, source: selectedDownloadSource)
            downloadJobs = jobs
            updateInstanceStatus(instance.id, status: .missingFiles)
            diagnostics.insert(DiagnosticReport(title: "Forge 已安装", severity: .info, summary: "已为 \(instance.name) 安装 Forge，生成 \(jobs.count) 个下载任务。", suggestedActions: ["打开下载中心执行任务"]), at: 0)
            selectedSection = .downloads
        } catch {
            diagnostics.insert(DiagnosticReport(title: "Forge 安装失败", severity: .error, summary: error.localizedDescription, suggestedActions: ["确认已安装基础版本", "检查网络连接"]), at: 0)
        }
    }

    func refreshAvailableVersions() async {
        do {
            let manifest = try await versionService.fetchManifest(from: nil)
            availableVersions = manifest.versions
            diagnostics.insert(
                DiagnosticReport(
                    title: "版本列表已刷新",
                    severity: .info,
                    summary: "已从 Mojang manifest 获取 \(manifest.versions.count) 个版本。",
                    suggestedActions: ["选择实例后生成 Vanilla 安装计划"]
                ),
                at: 0
            )
        } catch {
            diagnostics.insert(
                DiagnosticReport(
                    title: "版本列表刷新失败",
                    severity: .error,
                    summary: error.localizedDescription,
                    suggestedActions: ["检查网络连接", "稍后重试"]
                ),
                at: 0
            )
        }
    }

    func searchModrinth(query: String) async {
        modrinthSearchQuery = query
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            modrinthSearchResults = []
            return
        }
        do {
            let response = try await modrinthService.search(query: query, facets: nil)
            modrinthSearchResults = response.hits
        } catch {
            diagnostics.insert(
                DiagnosticReport(
                    title: "Modrinth 搜索失败",
                    severity: .error,
                    summary: error.localizedDescription,
                    suggestedActions: ["检查网络连接", "稍后重试"]
                ),
                at: 0
            )
        }
    }

    func installModrinthMod(version: ModrinthVersion, file: ModrinthFile, for instance: LauncherInstance) async {
        let modsDir = instance.rootDirectory.appendingPathComponent("mods", isDirectory: true)
        let destination = modsDir.appendingPathComponent(file.filename)
        do {
            try await modrinthService.downloadFile(from: file.url, to: destination)
            diagnostics.insert(
                DiagnosticReport(
                    title: "Mod 已安装",
                    severity: .info,
                    summary: "\(version.name) 已下载到 \(instance.name) 的 mods 目录。",
                    suggestedActions: ["启动游戏加载 mod"]
                ),
                at: 0
            )
        } catch {
            diagnostics.insert(
                DiagnosticReport(
                    title: "Mod 下载失败",
                    severity: .error,
                    summary: "\(file.filename)：\(error.localizedDescription)",
                    suggestedActions: ["检查网络连接", "重新尝试下载"]
                ),
                at: 0
            )
        }
    }

    func planVanillaInstallFromRemoteMetadata(for instance: LauncherInstance) async {
        guard let version = availableVersions.first(where: { $0.id == instance.gameVersion }) else {
            diagnostics.insert(
                DiagnosticReport(
                    title: "未找到版本元数据",
                    severity: .error,
                    summary: "版本列表中没有 \(instance.gameVersion)。",
                    suggestedActions: ["先刷新版本列表", "检查实例版本号是否正确"]
                ),
                at: 0
            )
            return
        }

        do {
            let metadata = try await versionService.fetchVersionMetadata(from: version.metadataURL)
            let assetIndex = try await versionService.fetchAssetIndex(from: metadata.assetIndex.url)
            planVanillaInstall(metadata: metadata, assetIndex: assetIndex, for: instance)
        } catch {
            diagnostics.insert(
                DiagnosticReport(
                    title: "版本元数据获取失败",
                    severity: .error,
                    summary: error.localizedDescription,
                    suggestedActions: ["检查网络连接", "重新刷新版本列表"]
                ),
                at: 0
            )
        }
    }

    func expandAssetIndexDownloads(assetIndexURL: URL, for instance: LauncherInstance) throws {
        let data = try Data(contentsOf: assetIndexURL)
        let assetIndex = try versionService.decodeAssetIndex(from: data)
        let assetJobs = downloadService.makeAssetObjectJobs(
            assetIndex: assetIndex,
            instance: instance,
            source: selectedDownloadSource
        )
        downloadJobs = assetJobs
        diagnostics.insert(
            DiagnosticReport(
                title: "已展开资源文件",
                severity: .info,
                summary: "已从 asset index 生成 \(assetJobs.count) 个资源任务，共 \(assetIndex.totalBytes) 字节。",
                suggestedActions: ["点击开始下载执行资源任务", "下载完成后即可进入 native 解压和启动阶段"]
            ),
            at: 0
        )
        selectedSection = .downloads
    }

    func expandSelectedInstanceAssetIndex() {
        guard let selectedInstance else {
            diagnostics.insert(
                DiagnosticReport(
                    title: "未选择实例",
                    severity: .error,
                    summary: "需要先选择一个实例才能展开资源索引。",
                    suggestedActions: ["从侧边栏选择实例"]
                ),
                at: 0
            )
            return
        }

        let assetIndexURL = selectedInstance.rootDirectory
            .appendingPathComponent(".minecraft", isDirectory: true)
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("indexes", isDirectory: true)
            .appendingPathComponent("\(selectedInstance.gameVersion).json")

        do {
            try expandAssetIndexDownloads(assetIndexURL: assetIndexURL, for: selectedInstance)
        } catch {
            diagnostics.insert(
                DiagnosticReport(
                    title: "资源索引展开失败",
                    severity: .error,
                    summary: "\(assetIndexURL.path)：\(error.localizedDescription)",
                    suggestedActions: ["先下载资源索引任务", "确认实例版本号和 asset index 文件名一致"]
                ),
                at: 0
            )
        }
    }

    func executeQueuedDownloads() async {
        let queuedIndices = downloadJobs.indices.filter { downloadJobs[$0].status == .queued }
        guard !queuedIndices.isEmpty else { return }

        for index in queuedIndices {
            downloadJobs[index].status = .running
        }

        await withTaskGroup(of: (Int, DownloadJob?).self) { group in
            var activeTasks = 0
            var nextIndex = 0

            func startNext() -> Bool {
                guard nextIndex < queuedIndices.count else { return false }
                let index = queuedIndices[nextIndex]
                nextIndex += 1
                group.addTask { [self] in
                    do {
                        let completedJob = try await downloadService.execute(job: downloadJobs[index])
                        return (index, completedJob)
                    } catch {
                        var failedJob = downloadJobs[index]
                        failedJob.status = .failed
                        return (index, failedJob)
                    }
                }
                activeTasks += 1
                return true
            }

            // Start initial batch (max 4)
            for _ in 0..<min(4, queuedIndices.count) {
                _ = startNext()
            }

            for await (index, result) in group {
                activeTasks -= 1
                if let result {
                    downloadJobs[index] = result
                    if result.status == .failed {
                        diagnostics.insert(
                            DiagnosticReport(
                                title: "下载失败",
                                severity: .error,
                                summary: "\(result.title)：下载失败",
                                suggestedActions: ["检查网络连接和下载源", "重新生成安装计划后重试"]
                            ),
                            at: 0
                        )
                    }
                }
                _ = startNext()
            }
        }

        finalizeDownloadedPlanIfPossible()
    }

    func cancelDownloads() {
        for index in downloadJobs.indices {
            if downloadJobs[index].status == .queued || downloadJobs[index].status == .running {
                downloadJobs[index].status = .failed
            }
        }
        diagnostics.insert(
            DiagnosticReport(
                title: "下载已取消",
                severity: .info,
                summary: "所有排队和进行中的下载任务已取消。",
                suggestedActions: []
            ),
            at: 0
        )
    }

    func prepareNativeLibrariesForSelectedInstance() {
        guard let instance = selectedInstance ?? instances.first(where: { $0.id == plannedInstanceID }) else {
            diagnostics.insert(
                DiagnosticReport(
                    title: "未选择实例",
                    severity: .error,
                    summary: "需要先选择实例才能准备 native libraries。",
                    suggestedActions: ["从侧边栏选择实例"]
                ),
                at: 0
            )
            return
        }

        guard let plannedVersionMetadata else {
            diagnostics.insert(
                DiagnosticReport(
                    title: "缺少版本元数据",
                    severity: .error,
                    summary: "需要先生成安装计划，才能知道要解压哪些 native libraries。",
                    suggestedActions: ["点击生成安装计划", "完成下载后再准备 native libraries"]
                ),
                at: 0
            )
            return
        }

        do {
            let archives = try downloadService.prepareNativeLibraries(
                metadata: plannedVersionMetadata,
                instance: instance
            )
            updateInstanceStatus(instance.id, status: .ready)
            diagnostics.insert(
                DiagnosticReport(
                    title: "Native libraries 已准备",
                    severity: .info,
                    summary: "已解压 \(archives.count) 个 native library，实例 \(instance.name) 已标记为可启动。",
                    suggestedActions: ["点击启动进入游戏", "如启动失败，查看 latest.log"]
                ),
                at: 0
            )
        } catch {
            diagnostics.insert(
                DiagnosticReport(
                    title: "Native libraries 准备失败",
                    severity: .error,
                    summary: error.localizedDescription,
                    suggestedActions: ["确认下载任务已全部完成", "重新生成安装计划并下载 native library"]
                ),
                at: 0
            )
        }
    }

    func monitorLaunchSession() {
        guard let session = currentLaunchSession else { return }
        let pid = session.processIdentifier

        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            let result = kill(pid, 0)
            if result != 0 {
                DispatchQueue.main.async {
                    guard let self else { return }
                    timer.invalidate()
                    let exitTime = Date()
                    let duration = exitTime.timeIntervalSince(session.startedAt)
                    let minutes = Int(duration) / 60
                    let seconds = Int(duration) % 60
                    self.currentLaunchSession = nil
                    self.diagnostics.insert(
                        DiagnosticReport(
                            title: "Minecraft 已退出",
                            severity: .info,
                            summary: "进程 \(pid) 已退出，运行时长 \(minutes)分\(seconds)秒。日志：\(session.logFileURL.path)",
                            suggestedActions: ["打开日志查看退出原因", "如果异常退出，检查 Java 版本和内存设置"]
                        ),
                        at: 0
                    )
                }
            }
        }
    }

    private func updateInstanceStatus(_ id: LauncherInstance.ID, status: InstanceStatus) {
        guard let index = instances.firstIndex(where: { $0.id == id }) else { return }
        instances[index].status = status
    }

    private func finalizeDownloadedPlanIfPossible() {
        guard downloadJobs.contains(where: { $0.status == .completed }) else { return }
        guard !downloadJobs.contains(where: { $0.status == .queued || $0.status == .running || $0.status == .failed }) else {
            return
        }
        guard let plannedVersionMetadata,
              let plannedInstanceID,
              let instance = instances.first(where: { $0.id == plannedInstanceID })
        else {
            return
        }

        do {
            let archives = try downloadService.prepareNativeLibraries(
                metadata: plannedVersionMetadata,
                instance: instance
            )
            updateInstanceStatus(instance.id, status: .ready)
            diagnostics.insert(
                DiagnosticReport(
                    title: "安装收尾完成",
                    severity: .info,
                    summary: "下载任务已完成，已自动解压 \(archives.count) 个 native library，\(instance.name) 已标记为可启动。",
                    suggestedActions: ["点击启动进入游戏", "如启动失败，查看 latest.log"]
                ),
                at: 0
            )
        } catch {
            updateInstanceStatus(instance.id, status: .missingFiles)
            diagnostics.insert(
                DiagnosticReport(
                    title: "安装收尾失败",
                    severity: .error,
                    summary: error.localizedDescription,
                    suggestedActions: ["确认 native library 下载完成", "手动点击准备 Native"]
                ),
                at: 0
            )
        }
    }

    private func repairMetadata(for instance: LauncherInstance) async throws -> VersionMetadata {
        if plannedInstanceID == instance.id, let plannedVersionMetadata {
            return plannedVersionMetadata
        }

        if let localMetadata = localVersionMetadata(for: instance) {
            return localMetadata
        }

        guard let version = availableVersions.first(where: { $0.id == instance.gameVersion }) else {
            throw RepairPlanningError.missingVersionMetadata(instance.gameVersion)
        }

        return try await versionService.fetchVersionMetadata(from: version.metadataURL)
    }

    private func localVersionMetadata(for instance: LauncherInstance) -> VersionMetadata? {
        let metadataURL = instance.rootDirectory
            .appendingPathComponent(".minecraft", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(instance.gameVersion, isDirectory: true)
            .appendingPathComponent("\(instance.gameVersion).json")
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? JSONDecoder.mmcl.decode(VersionMetadata.self, from: data)
    }
}

enum RepairPlanningError: LocalizedError, Equatable {
    case missingVersionMetadata(String)

    var errorDescription: String? {
        switch self {
        case .missingVersionMetadata(let version):
            return "缺少 \(version) 的版本元数据。"
        }
    }
}

extension LauncherStore {
    static let sampleInstances: [LauncherInstance] = {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MMCL/Instances", isDirectory: true)
        return [
            LauncherInstance(
                name: "原版生存",
                gameVersion: "1.21.5",
                loader: .vanilla,
                rootDirectory: base.appendingPathComponent("vanilla-survival"),
                profile: LaunchProfile(offlineUsername: "Steve", memoryMegabytes: 4096, jvmArguments: ["-XX:+UseG1GC"]),
                status: .ready,
                lastPlayedAt: Date(timeIntervalSinceNow: -3600)
            ),
            LauncherInstance(
                name: "Fabric 科技包",
                gameVersion: "1.20.1",
                loader: .fabric,
                rootDirectory: base.appendingPathComponent("fabric-tech"),
                profile: LaunchProfile(offlineUsername: "Alex", memoryMegabytes: 6144, jvmArguments: ["-XX:+UseG1GC", "-Dfml.ignoreInvalidMinecraftCertificates=true"]),
                status: .missingFiles,
                lastPlayedAt: Date(timeIntervalSinceNow: -86_400)
            ),
            LauncherInstance(
                name: "快照测试",
                gameVersion: "25w21a",
                loader: .vanilla,
                rootDirectory: base.appendingPathComponent("snapshot-lab"),
                profile: LaunchProfile(offlineUsername: "Tester", memoryMegabytes: 3072, jvmArguments: []),
                status: .needsJava,
                lastPlayedAt: nil
            )
        ]
    }()

    static let sampleDownloadJobs: [DownloadJob] = [
        DownloadJob(
            title: "Minecraft 1.21.5 资源文件",
            source: .bmclapi,
            destination: URL(fileURLWithPath: "/tmp/assets"),
            totalBytes: 120_000_000,
            completedBytes: 78_000_000,
            status: .running
        ),
        DownloadJob(
            title: "Fabric Loader 0.16",
            source: .official,
            destination: URL(fileURLWithPath: "/tmp/fabric"),
            totalBytes: 6_000_000,
            completedBytes: 6_000_000,
            status: .completed
        )
    ]

    static let sampleProjects: [ContentProject] = [
        ContentProject(id: "sodium", title: "Sodium", type: .mod, source: "Modrinth", gameVersions: ["1.21.5", "1.20.1"], loaders: [.fabric, .quilt]),
        ContentProject(id: "iris", title: "Iris Shaders", type: .mod, source: "Modrinth", gameVersions: ["1.21.5"], loaders: [.fabric]),
        ContentProject(id: "fabulously-optimized", title: "Fabulously Optimized", type: .modpack, source: "Modrinth", gameVersions: ["1.21.5"], loaders: [.fabric])
    ]

    static let sampleJavaRuntimes: [JavaRuntime] = [
        JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        ),
        JavaRuntime(
            name: "Zulu 17",
            version: "17.0.11",
            majorVersion: 17,
            architecture: .x86_64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home/bin/java")
        )
    ]

    static let sampleVersions: [MinecraftVersion] = [
        MinecraftVersion(
            id: "1.21.5",
            type: .release,
            metadataURL: URL(string: "https://piston-meta.mojang.com/v1/packages/1.21.5.json")!,
            releaseTime: Date(timeIntervalSince1970: 1_747_740_000),
            recommendedJavaMajorVersion: 21
        ),
        MinecraftVersion(
            id: "1.20.1",
            type: .release,
            metadataURL: URL(string: "https://piston-meta.mojang.com/v1/packages/1.20.1.json")!,
            releaseTime: Date(timeIntervalSince1970: 1_685_640_000),
            recommendedJavaMajorVersion: 17
        )
    ]

    static let sampleVersionMetadata = VersionMetadata(
        id: "1.21.5",
        mainClass: "net.minecraft.client.main.Main",
        assets: "19",
        assetIndex: VersionMetadata.AssetIndex(
            id: "19",
            url: URL(string: "https://piston-meta.mojang.com/v1/packages/assets.json")!,
            sha1: "asset-sha1",
            size: 321
        ),
        downloads: VersionMetadata.Downloads(
            client: VersionMetadata.Download(
                url: URL(string: "https://piston-data.mojang.com/v1/objects/client.jar")!,
                sha1: "client-sha1",
                size: 123
            )
        ),
        libraries: [
            VersionMetadata.Library(
                name: "org.lwjgl:lwjgl:3.3.3",
                downloads: VersionMetadata.Library.Downloads(
                    artifact: VersionMetadata.Library.Artifact(
                        path: "org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar",
                        url: URL(string: "https://libraries.minecraft.net/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar")!,
                        sha1: "library-sha1",
                        size: 456
                    )
                )
            )
        ]
    )

    static let sampleDiagnostics: [DiagnosticReport] = [
        DiagnosticReport(
            title: "Fabric 科技包缺少资源库",
            severity: .warning,
            summary: "检测到 3 个 libraries 文件缺失，可能导致启动失败。",
            suggestedActions: ["点击修复实例重新下载缺失文件", "确认下载源可访问"]
        ),
        DiagnosticReport(
            title: "快照测试需要 Java 21",
            severity: .error,
            summary: "当前未选择可用的 Java 21 Apple Silicon 运行时。",
            suggestedActions: ["安装 Temurin 21", "在设置中重新扫描 Java"]
        )
    ]
}
