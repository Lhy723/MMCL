import XCTest
@testable import MMCL

@MainActor
final class SemanticVersionTests: XCTestCase {
    func testSemanticVersionComparesNumericComponents() {
        XCTAssertTrue(SemanticVersion("0.10.0")! > SemanticVersion("0.9.0")!)
        XCTAssertTrue(SemanticVersion("0.2.0")! > SemanticVersion("0.1.9")!)
    }

    func testSemanticVersionOrdersPrereleaseIdentifiers() {
        XCTAssertTrue(SemanticVersion("1.0.0-alpha")! < SemanticVersion("1.0.0-beta")!)
        XCTAssertTrue(SemanticVersion("1.0.0-beta.1")! < SemanticVersion("1.0.0-beta.2")!)
        XCTAssertTrue(SemanticVersion("1.0.0-rc.1")! < SemanticVersion("1.0.0")!)
    }

    func testNewerVersionRejectsDowngradesAndInvalidVersions() {
        XCTAssertTrue(SemanticVersion.isNewerVersion("v0.10.0", than: "0.9.0"))
        XCTAssertTrue(SemanticVersion.isNewerVersion("0.2.0", than: "0.1.9"))
        XCTAssertFalse(SemanticVersion.isNewerVersion("0.9.0", than: "0.10.0"))
        XCTAssertFalse(SemanticVersion.isNewerVersion("1.0.0", than: "1.0.0"))
        XCTAssertFalse(SemanticVersion.isNewerVersion("1.0.0-rc.1", than: "1.0.0"))
        XCTAssertFalse(SemanticVersion.isNewerVersion("not-a-version", than: "0.1.0"))
        XCTAssertFalse(SemanticVersion.isNewerVersion("vv1.1.0", than: "1.0.0"))
    }

    func testSemanticVersionIgnoresBuildMetadataForPrecedence() {
        let first = SemanticVersion("1.0.0+build.1")
        let second = SemanticVersion("1.0.0+build.2")

        XCTAssertEqual(first, second)
        XCTAssertFalse(SemanticVersion.isNewerVersion("1.0.0+build.2", than: "1.0.0+build.1"))
    }
}

private struct StubAuthService: AuthServicing {
    func startDeviceCodeFlow() async throws -> DeviceCodeResponse {
        DeviceCodeResponse(
            userCode: "CODE",
            verificationUri: "https://example.com",
            expiresIn: 900,
            interval: 1,
            deviceCode: "device-code"
        )
    }

    func pollForToken(deviceCode: String, interval: Int) async throws -> MicrosoftTokenResponse {
        MicrosoftTokenResponse(
            accessToken: "microsoft-access-token",
            refreshToken: "new-refresh-token",
            expiresInSeconds: 3600
        )
    }

    func exchangeForXBLToken(accessToken: String) async throws -> XboxTokenResponse {
        XboxTokenResponse(token: "xbl-token", expiresInSeconds: 3600)
    }

    func exchangeForXSTSToken(xblToken: String) async throws -> XBLXSTSResponse {
        XBLXSTSResponse(
            token: "xsts-token",
            expiresInSeconds: 3600,
            xuid: "refreshed-xuid",
            userHash: "user-hash"
        )
    }

    func exchangeForMinecraftToken(xstsToken: String) async throws -> MinecraftTokenResponse {
        MinecraftTokenResponse(accessToken: "new-minecraft-token", expiresInSeconds: 3600)
    }

    func fetchMinecraftProfile(accessToken: String) async throws -> MinecraftProfileResponse {
        MinecraftProfileResponse(id: "refreshed-uuid", name: "RefreshedName")
    }

    func refreshMicrosoftToken(refreshToken: String) async throws -> MicrosoftTokenResponse {
        MicrosoftTokenResponse(
            accessToken: "refreshed-microsoft-access-token",
            refreshToken: "new-refresh-token",
            expiresInSeconds: 3600
        )
    }
}

private final class InMemoryCredentialStore: AccountCredentialStoring {
    private var storedCredentials: [UUID: AccountCredentials] = [:]

    func credentials(for accountID: UUID) throws -> AccountCredentials? {
        storedCredentials[accountID]
    }

    func save(_ credentials: AccountCredentials, for accountID: UUID) throws {
        storedCredentials[accountID] = credentials
    }

    func deleteCredentials(for accountID: UUID) throws {
        storedCredentials.removeValue(forKey: accountID)
    }
}

final class LauncherStoreTests: XCTestCase {
    @MainActor
    func testStoreBuildsLaunchPreviewForSelectedInstanceAndJava() {
        let instanceID = UUID()
        let instance = LauncherInstance(
            id: instanceID,
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: URL(fileURLWithPath: "/Users/example/Instances/vanilla", isDirectory: true),
            profile: LaunchProfile(offlineUsername: "Steve", memoryMegabytes: 4096, jvmArguments: [], resolutionWidth: 854, resolutionHeight: 480),
            status: .ready
        )
        let runtime = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )
        let store = LauncherStore(
            instances: [instance],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [runtime],
            availableVersions: []
        )
        store.jvmPresets = [
            JVMPreset(
                id: UUID(),
                name: "ZGC",
                arguments: ["-XX:+UseZGC"],
                isEnabled: true
            )
        ]
        let offlineAccount = MinecraftAccount(username: "Steve", type: .offline)
        store.accounts = [offlineAccount]
        store.selectedAccountID = offlineAccount.id
        store.selectedSection = .launcher
        store.launcherSelectedInstanceID = instanceID
        store.selectedJavaRuntimeID = runtime.id

        let preview = store.launchPreviewForSelectedInstance()

        XCTAssertNotNil(preview)
        XCTAssertEqual(preview?.java.displayName, "Temurin 21 · Java 21 · Apple Silicon")
        XCTAssertTrue(preview?.command.contains("--username") == true)
        XCTAssertTrue(preview?.command.contains("Steve") == true)
        XCTAssertTrue(preview?.command.contains("-XX:+UseZGC") == true)
    }

    @MainActor
    func testStoreRefreshesJavaRuntimesAndSelectsRecommendedRuntimeForInstance() async {
        let instanceID = UUID()
        let instance = LauncherInstance(
            id: instanceID,
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: URL(fileURLWithPath: "/Users/example/Instances/vanilla", isDirectory: true),
            status: .ready
        )
        let java17 = JavaRuntime(
            name: "Zulu 17",
            version: "17.0.11",
            majorVersion: 17,
            architecture: .x86_64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home/bin/java")
        )
        let java21 = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )
        let store = LauncherStore(
            instances: [instance],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: [],
            javaRuntimeService: StubJavaRuntimeService(runtimes: [java17, java21])
        )
        let offlineAccount = MinecraftAccount(username: "Steve", type: .offline)
        store.accounts = [offlineAccount]
        store.selectedAccountID = offlineAccount.id
        store.selectedSection = .launcher
        store.launcherSelectedInstanceID = instanceID

        await store.refreshJavaRuntimes()

        XCTAssertEqual(store.javaRuntimes.map(\.majorVersion), [17, 21])
        XCTAssertEqual(store.selectedJavaRuntimeID, java21.id)
        XCTAssertEqual(store.diagnostics.first?.title, "Java 运行时已刷新")
    }

    @MainActor
    func testStoreReportsJDKInstallFailureInsteadOfCompletion() async {
        let store = LauncherStore(
            instances: [],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: [],
            javaRuntimeService: StubJavaRuntimeService(runtimes: []),
            portableJDKInstaller: FailingPortableJDKInstaller(
                error: PortableJDKInstallError.tarFailed(2, "损坏的压缩包")
            )
        )

        await store.installJDK(majorVersion: 21)

        XCTAssertEqual(store.jdkInstallProgress, 0)
        XCTAssertEqual(store.diagnostics.first?.title, "Java 安装失败")
        XCTAssertFalse(store.diagnostics.contains { $0.title == "Java 21 安装完成" })
    }

    @MainActor
    func testStoreLaunchesSelectedInstanceAndRecordsSession() async {
        let instanceID = UUID()
        let instance = LauncherInstance(
            id: instanceID,
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: URL(fileURLWithPath: "/Users/example/Instances/vanilla", isDirectory: true),
            status: .ready
        )
        let runtime = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )
        let expectedSession = LaunchSession(
            processIdentifier: 42,
            command: [runtime.executableURL.path, "-version"],
            logFileURL: URL(fileURLWithPath: "/Users/example/Instances/vanilla/logs/latest.log"),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let launchService = StubLaunchService(session: expectedSession)
        let store = LauncherStore(
            instances: [instance],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [runtime],
            availableVersions: [],
            launchService: launchService
        )
        store.jvmPresets = [
            JVMPreset(
                id: UUID(),
                name: "ZGC",
                arguments: ["-XX:+UseZGC"],
                isEnabled: true
            )
        ]
        let offlineAccount = MinecraftAccount(username: "Steve", type: .offline)
        store.accounts = [offlineAccount]
        store.selectedAccountID = offlineAccount.id
        store.selectedSection = .launcher
        store.launcherSelectedInstanceID = instanceID
        store.selectedJavaRuntimeID = runtime.id

        await store.launchSelectedInstance()

        XCTAssertEqual(store.currentLaunchSession, expectedSession)
        XCTAssertEqual(store.diagnostics.first?.title, "Minecraft 已启动")
        XCTAssertTrue(store.diagnostics.first?.summary.contains("42") == true)
        XCTAssertTrue(launchService.lastPreflightInstance?.profile.jvmArguments.contains("-XX:+UseZGC") == true)
        XCTAssertTrue(launchService.lastLaunchInstance?.profile.jvmArguments.contains("-XX:+UseZGC") == true)
    }

    @MainActor
    func testJVMCollectorPresetsAreMutuallyExclusiveButSameFamilyCanCombine() {
        let g1Preset = JVMPreset(
            id: UUID(),
            name: "G1GC",
            arguments: ["-XX:+UseG1GC"],
            isEnabled: false
        )
        let g1TuningPreset = JVMPreset(
            id: UUID(),
            name: "G1 调优",
            arguments: ["-XX:+UseG1GC", "-XX:MaxGCPauseMillis=50"],
            isEnabled: false
        )
        let zgcPreset = JVMPreset(
            id: UUID(),
            name: "ZGC",
            arguments: ["-XX:+UseZGC"],
            isEnabled: false
        )
        let store = LauncherStore(
            instances: [],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: []
        )
        store.jvmPresets = [g1Preset, g1TuningPreset, zgcPreset]

        store.setJVMPresetEnabled(id: g1Preset.id, enabled: true)
        store.setJVMPresetEnabled(id: g1TuningPreset.id, enabled: true)

        XCTAssertTrue(store.jvmPresets[0].isEnabled)
        XCTAssertTrue(store.jvmPresets[1].isEnabled)
        XCTAssertFalse(store.jvmPresets[2].isEnabled)
        XCTAssertEqual(store.enabledJVMArguments.filter { $0 == "-XX:+UseG1GC" }.count, 1)
        XCTAssertTrue(store.enabledJVMArguments.contains("-XX:MaxGCPauseMillis=50"))

        store.setJVMPresetEnabled(id: zgcPreset.id, enabled: true)

        XCTAssertFalse(store.jvmPresets[0].isEnabled)
        XCTAssertFalse(store.jvmPresets[1].isEnabled)
        XCTAssertTrue(store.jvmPresets[2].isEnabled)
        XCTAssertEqual(store.enabledJVMArguments, ["-XX:+UseZGC"])
    }

    @MainActor
    func testStoreRefreshesExpiredMicrosoftAccountBeforeLaunch() async throws {
        let instanceID = UUID()
        let instance = LauncherInstance(
            id: instanceID,
            name: "正版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: URL(fileURLWithPath: "/Users/example/Instances/vanilla", isDirectory: true),
            status: .ready
        )
        let runtime = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )
        let account = MinecraftAccount(
            username: "OldName",
            uuid: "old-uuid",
            xuid: "old-xuid",
            accessToken: "old-minecraft-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(-1),
            type: .microsoft
        )
        let launchService = StubLaunchService(
            session: LaunchSession(
                processIdentifier: 42,
                command: [runtime.executableURL.path, "--userType", "msa"],
                logFileURL: URL(fileURLWithPath: "/Users/example/Instances/vanilla/logs/latest.log")
            )
        )
        let accountFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("MMCL-refresh-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("accounts.json")
        defer { try? FileManager.default.removeItem(at: accountFile.deletingLastPathComponent()) }
        let store = LauncherStore(
            instances: [instance],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [runtime],
            availableVersions: [],
            launchService: launchService,
            authService: StubAuthService(),
            accountPersistence: AccountPersistence(
                fileURL: accountFile,
                credentialStore: InMemoryCredentialStore()
            )
        )
        store.accounts = [account]
        store.selectedAccountID = account.id
        store.selectedSection = .launcher
        store.launcherSelectedInstanceID = instanceID
        store.selectedJavaRuntimeID = runtime.id

        await store.launchSelectedInstance()

        XCTAssertEqual(store.currentLaunchSession?.processIdentifier, 42)
        XCTAssertEqual(launchService.lastPreflightAccount?.username, "RefreshedName")
        XCTAssertEqual(launchService.lastLaunchAccount?.uuid, "refreshed-uuid")
        XCTAssertEqual(launchService.lastLaunchAccount?.xuid, "refreshed-xuid")
        XCTAssertEqual(store.accounts.first?.accessToken, "new-minecraft-token")
        XCTAssertEqual(store.accounts.first?.refreshToken, "new-refresh-token")
    }

    @MainActor
    func testStoreScansSkinsForAccount() {
        let store = LauncherStore(
            instances: [],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: []
        )

        // Skin scanning with empty directory should return empty
        let account = MinecraftAccount(username: "Test", uuid: "test-uuid", type: .offline)
        store.scanSkinsForAccount(account)
        XCTAssertTrue(store.availableSkins.isEmpty)
    }

    @MainActor
    func testModOperationsUseScannedFileURLs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MMCL-mods-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let modsDirectory = root.appendingPathComponent("mods", isDirectory: true)
        try FileManager.default.createDirectory(at: modsDirectory, withIntermediateDirectories: true)
        let enabledURL = modsDirectory.appendingPathComponent("sodium.jar")
        let disabledURL = modsDirectory.appendingPathComponent("lithium.jar.disabled")
        let enabledData = Data("enabled-mod".utf8)
        let disabledData = Data("disabled-mod".utf8)
        try enabledData.write(to: enabledURL)
        try disabledData.write(to: disabledURL)

        let instance = LauncherInstance(
            name: "Mod 文件操作测试",
            gameVersion: "1.21.5",
            loader: .fabric,
            rootDirectory: root
        )
        let store = LauncherStore(
            instances: [instance],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: []
        )

        let scannedMods = store.scanInstalledMods(for: instance)
        let enabledMod = try XCTUnwrap(scannedMods.first { $0.fileName == "sodium.jar" })
        let disabledMod = try XCTUnwrap(scannedMods.first { $0.fileName == "lithium.jar" })
        XCTAssertEqual(enabledMod.fileURL.resolvingSymlinksInPath(), enabledURL.resolvingSymlinksInPath())
        XCTAssertEqual(disabledMod.fileURL.resolvingSymlinksInPath(), disabledURL.resolvingSymlinksInPath())
        XCTAssertEqual(enabledMod.size, Int64(enabledData.count))
        XCTAssertEqual(disabledMod.size, Int64(disabledData.count))

        store.toggleMod(for: instance, mod: enabledMod)
        XCTAssertFalse(FileManager.default.fileExists(atPath: enabledURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: enabledURL.appendingPathExtension("disabled").path))

        let reenabledMod = try XCTUnwrap(store.scanInstalledMods(for: instance).first { $0.fileName == "sodium.jar" })
        store.toggleMod(for: instance, mod: reenabledMod)
        XCTAssertTrue(FileManager.default.fileExists(atPath: enabledURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: enabledURL.appendingPathExtension("disabled").path))

        store.deleteMod(for: instance, mod: disabledMod)
        XCTAssertFalse(FileManager.default.fileExists(atPath: disabledURL.path))
    }

    @MainActor
    func testStoreBlocksLaunchWhenPreflightFails() async {
        let instanceID = UUID()
        let instance = LauncherInstance(
            id: instanceID,
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: URL(fileURLWithPath: "/Users/example/Instances/vanilla", isDirectory: true),
            status: .missingFiles
        )
        let runtime = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )
        let failingLaunchService = StubLaunchService(
            session: LaunchSession(
                processIdentifier: 42,
                command: [runtime.executableURL.path, "-version"],
                logFileURL: URL(fileURLWithPath: "/Users/example/Instances/vanilla/logs/latest.log")
            ),
            preflightReport: LaunchPreflightReport(
                severity: .error,
                summary: "缺少 client jar。",
                suggestedActions: ["生成安装计划并完成下载", "准备 Native"]
            )
        )
        let store = LauncherStore(
            instances: [instance],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [runtime],
            availableVersions: [],
            launchService: failingLaunchService
        )
        let offlineAccount = MinecraftAccount(username: "Steve", type: .offline)
        store.accounts = [offlineAccount]
        store.selectedAccountID = offlineAccount.id
        store.selectedSection = .launcher
        store.launcherSelectedInstanceID = instanceID
        store.selectedJavaRuntimeID = runtime.id

        await store.launchSelectedInstance()

        XCTAssertNil(store.currentLaunchSession)
        XCTAssertFalse(failingLaunchService.didLaunch)
        XCTAssertEqual(store.instances.first?.status, .missingFiles)
        XCTAssertEqual(store.diagnostics.first?.title, "启动前检查未通过")
        XCTAssertEqual(store.diagnostics.first?.suggestedActions.first, "生成安装计划并完成下载")
    }

    @MainActor
    func testStoreCreatesInstanceAndSelectsIt() {
        let store = LauncherStore(
            instances: [],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: [],
            instanceService: MockInstanceService()
        )

        store.createInstance(
            name: "测试实例",
            gameVersion: "1.21.5",
            loader: .vanilla
        )

        XCTAssertEqual(store.instances.count, 1)
        XCTAssertEqual(store.instances.first?.name, "测试实例")
        XCTAssertEqual(store.instances.first?.gameVersion, "1.21.5")
        XCTAssertNotNil(store.selectedInstance)
        XCTAssertEqual(store.selectedInstance?.name, "测试实例")
        XCTAssertFalse(store.showingCreateSheet)
    }

    @MainActor
    func testStoreDeletesInstanceAndUpdatesSelection() {
        let instanceID = UUID()
        let instance = LauncherInstance(
            id: instanceID,
            name: "待删除",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: URL(fileURLWithPath: "/tmp/mmcl-test-delete-\(UUID())", isDirectory: true),
            status: .notInstalled
        )
        let store = LauncherStore(
            instances: [instance],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: []
        )
        store.selectedSection = .launcher
        store.launcherSelectedInstanceID = instanceID

        store.deleteInstance(instance)

        XCTAssertTrue(store.instances.isEmpty)
        XCTAssertNil(store.selectedInstance)
    }

    @MainActor
    func testStoreInspectsSelectedInstanceAndReportsRepairActions() {
        let instanceID = UUID()
        let instance = LauncherInstance(
            id: instanceID,
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: URL(fileURLWithPath: "/Users/example/Instances/vanilla", isDirectory: true),
            status: .ready
        )
        let runtime = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )
        let store = LauncherStore(
            instances: [instance],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [runtime],
            availableVersions: [],
            launchService: StubLaunchService(
                session: LaunchSession(
                    processIdentifier: 42,
                    command: [runtime.executableURL.path, "-version"],
                    logFileURL: URL(fileURLWithPath: "/Users/example/Instances/vanilla/logs/latest.log")
                ),
                preflightReport: LaunchPreflightReport(
                    severity: .error,
                    summary: "缺少 asset index。",
                    suggestedActions: ["生成安装计划并完成下载"]
                )
            )
        )
        store.selectedSection = .launcher
        store.launcherSelectedInstanceID = instanceID
        store.selectedJavaRuntimeID = runtime.id

        store.inspectSelectedInstance()

        XCTAssertEqual(store.instances.first?.status, .missingFiles)
        XCTAssertEqual(store.diagnostics.first?.title, "实例需要修复")
        XCTAssertEqual(store.diagnostics.first?.summary, "缺少 asset index。")
    }

    @MainActor
    func testStorePreparesNativeLibrariesAndMarksInstanceReady() throws {
        let instanceID = UUID()
        let launchVersionID = "1.21.5-fabric-0.16.14"
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            id: instanceID,
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .fabric,
            rootDirectory: root,
            status: .notInstalled,
            launchVersionID: launchVersionID
        )
        var metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.versionMetadataJSON.utf8))
        metadata.id = launchVersionID
        metadata.mainClass = "net.fabricmc.loader.impl.launch.knot.KnotClient"
        metadata.libraries.append(
            VersionMetadata.Library(
                name: "net.fabricmc:fabric-loader:0.16.14",
                downloads: VersionMetadata.Library.Downloads(
                    artifact: VersionMetadata.Library.Artifact(
                        path: "net/fabricmc/fabric-loader/0.16.14/fabric-loader-0.16.14.jar",
                        url: URL(string: "https://maven.fabricmc.net/net/fabricmc/fabric-loader/0.16.14/fabric-loader-0.16.14.jar")!,
                        sha1: "loader-sha1",
                        size: 1
                    ),
                    classifiers: nil
                )
            )
        )
        let coreLibrary = root.appendingPathComponent(
            ".minecraft/libraries/net/fabricmc/fabric-loader/0.16.14/fabric-loader-0.16.14.jar"
        )
        try FileManager.default.createDirectory(at: coreLibrary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("loader".utf8).write(to: coreLibrary)
        let nativeArchive = root
            .appendingPathComponent(".minecraft/libraries/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3-natives-macos.jar")
        try FileManager.default.createDirectory(
            at: nativeArchive.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let zipSource = root.appendingPathComponent("zip-source", isDirectory: true)
        try FileManager.default.createDirectory(at: zipSource, withIntermediateDirectories: true)
        try Data("native".utf8).write(to: zipSource.appendingPathComponent("libmmcl.dylib"))
        try Self.zip(contentsOf: zipSource, destination: nativeArchive)
        let store = LauncherStore(
            instances: [instance],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: []
        )
        store.selectedSection = .launcher
        store.launcherSelectedInstanceID = instanceID
        store.planVanillaInstall(metadata: metadata, for: instance)

        store.prepareNativeLibrariesForSelectedInstance()

        XCTAssertEqual(store.instances.first?.status, .ready)
        XCTAssertEqual(store.diagnostics.first?.title, "Native libraries 已准备")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".minecraft/versions/\(launchVersionID)/natives/libmmcl.dylib").path
        ))
    }

    @MainActor
    func testStorePersistsLoaderLaunchVersionIDAfterInstallation() async throws {
        let launchVersionID = "1.21.5-fabric-0.16.14"
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "Fabric 生存",
            gameVersion: "1.21.5",
            loader: .fabric,
            rootDirectory: root
        )
        var metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.versionMetadataJSON.utf8))
        metadata.id = launchVersionID
        let store = LauncherStore(
            instances: [instance],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: [],
            fabricService: StubFabricService(metadata: metadata)
        )

        await store.installFabricLoader(for: instance)

        XCTAssertEqual(store.instances.first?.launchVersionID, launchVersionID)
        let persistedData = try Data(contentsOf: root.appendingPathComponent("instance.json"))
        let persisted = try JSONDecoder.mmcl.decode(LauncherInstance.self, from: persistedData)
        XCTAssertEqual(persisted.launchVersionID, launchVersionID)
    }

    private static func zip(contentsOf directory: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", destination.path, "."]
        process.currentDirectoryURL = directory
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private final class StubLaunchService: LaunchServicing {
        let session: LaunchSession
        let preflightReport: LaunchPreflightReport
        private(set) var didLaunch = false
        private(set) var lastPreflightInstance: LauncherInstance?
        private(set) var lastLaunchInstance: LauncherInstance?
        private(set) var lastPreflightAccount: MinecraftAccount?
        private(set) var lastLaunchAccount: MinecraftAccount?

        init(
            session: LaunchSession,
            preflightReport: LaunchPreflightReport = LaunchPreflightReport(
                severity: .info,
                summary: "启动前检查通过。",
                suggestedActions: []
            )
        ) {
            self.session = session
            self.preflightReport = preflightReport
        }

        func previewCommand(for instance: LauncherInstance, java: JavaRuntime, account: MinecraftAccount) -> [String] {
            session.command
        }

        func preflight(instance: LauncherInstance, java: JavaRuntime, account: MinecraftAccount) -> LaunchPreflightReport {
            lastPreflightInstance = instance
            lastPreflightAccount = account
            return preflightReport
        }

        func launch(instance: LauncherInstance, java: JavaRuntime, account: MinecraftAccount) throws -> LaunchSession {
            lastLaunchInstance = instance
            lastLaunchAccount = account
            didLaunch = true
            return session
        }
    }

    private struct StubFabricService: FabricServicing {
        let metadata: VersionMetadata

        func fetchLoaderVersions(gameVersion: String) async throws -> [FabricLoaderVersion] {
            []
        }

        func fetchProfile(gameVersion: String, loaderVersion: String) async throws -> FabricProfile {
            FabricProfile(
                id: metadata.id,
                inheritsFrom: gameVersion,
                mainClass: metadata.mainClass,
                arguments: nil
            )
        }

        func installFabric(
            gameVersion: String,
            loaderVersion: String?,
            instance: LauncherInstance
        ) async throws -> VersionMetadata {
            metadata
        }
    }

    private struct StubJavaRuntimeService: JavaRuntimeServicing {
        let runtimes: [JavaRuntime]

        var portableJDKDirectory: URL {
            FileManager.default.temporaryDirectory.appendingPathComponent("MMCL-JDK-Test")
        }

        func bundledSearchLocations() -> [URL] {
            []
        }

        func recommendedMajorVersion(for gameVersion: String) -> Int {
            JavaRuntime.recommendedMajorVersion(for: gameVersion)
        }

        func parseJavaHomeVerboseOutput(_ output: String) -> [JavaRuntime] {
            []
        }

        func discoverInstalledRuntimes() async throws -> [JavaRuntime] {
            runtimes
        }
    }

    private struct FailingPortableJDKInstaller: PortableJDKInstalling {
        let error: Error

        func install(
            majorVersion: Int,
            architecture: String,
            targetDirectory: URL
        ) async throws {
            throw error
        }
    }

    private struct MockInstanceService: InstanceServicing {
        let rootDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MMCLTests-\(UUID().uuidString)", isDirectory: true)

        var instancesDirectory: URL {
            rootDirectory.appendingPathComponent("Instances", isDirectory: true)
        }

        func createInstance(
            name: String,
            gameVersion: String,
            loader: GameLoader,
            profile: LaunchProfile
        ) throws -> LauncherInstance {
            let instanceID = UUID()
            let instanceRoot = instancesDirectory.appendingPathComponent(instanceID.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: instanceRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: instanceRoot.appendingPathComponent(".minecraft", isDirectory: true),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: instanceRoot.appendingPathComponent("logs", isDirectory: true),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: instanceRoot.appendingPathComponent("mods", isDirectory: true),
                withIntermediateDirectories: true
            )
            let instance = LauncherInstance(
                id: instanceID,
                name: name,
                gameVersion: gameVersion,
                loader: loader,
                rootDirectory: instanceRoot,
                profile: profile,
                status: .notInstalled
            )
            try JSONEncoder.mmcl.encode(instance).write(
                to: instanceFileURL(for: instance),
                options: .atomic
            )
            return instance
        }

        func copyInstance(_ instance: LauncherInstance, name: String) throws -> LauncherInstance {
            let copyID = UUID()
            let copyRoot = instancesDirectory.appendingPathComponent(copyID.uuidString, isDirectory: true)
            let copy = LauncherInstance(
                id: copyID,
                name: name,
                gameVersion: instance.gameVersion,
                loader: instance.loader,
                rootDirectory: copyRoot,
                profile: instance.profile,
                status: instance.status,
                lastPlayedAt: instance.lastPlayedAt,
                launchVersionID: instance.effectiveLaunchVersionID
            )
            let fileManager = FileManager.default
            try fileManager.copyItem(at: instance.rootDirectory, to: copyRoot)
            try encode(copy).write(to: instanceFileURL(for: copy), options: .atomic)
            return copy
        }

        func loadAllInstances() throws -> [LauncherInstance] {
            let fm = FileManager.default
            guard fm.fileExists(atPath: instancesDirectory.path) else { return [] }
            let dirs = try fm.contentsOfDirectory(
                at: instancesDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return dirs.compactMap { dir in
                let file = dir.appendingPathComponent("instance.json")
                guard fm.fileExists(atPath: file.path),
                      let data = try? Data(contentsOf: file),
                      let instance = try? JSONDecoder.mmcl.decode(LauncherInstance.self, from: data) else { return nil }
                return instance
            }
        }

        func instanceFileURL(for instance: LauncherInstance) -> URL {
            instance.rootDirectory.appendingPathComponent("instance.json")
        }

        func encode(_ instance: LauncherInstance) throws -> Data {
            try JSONEncoder.mmcl.encode(instance)
        }

        func decode(from data: Data) throws -> LauncherInstance {
            try JSONDecoder.mmcl.decode(LauncherInstance.self, from: data)
        }
    }

    @MainActor
    func testLaunchSessionTrackingResetsOnExit() {
        let store = LauncherStore(
            instances: [],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: []
        )
        XCTAssertNil(store.currentLaunchSession)
    }

    @MainActor
    func testCancelDownloadsMarksAllQueuedAndRunningAsFailed() {
        let store = LauncherStore(
            instances: [],
            downloadJobs: [
                DownloadJob(title: "A", source: .official, destination: URL(fileURLWithPath: "/tmp/a"), totalBytes: 100, status: .queued),
                DownloadJob(title: "B", source: .official, destination: URL(fileURLWithPath: "/tmp/b"), totalBytes: 100, status: .running),
                DownloadJob(title: "C", source: .official, destination: URL(fileURLWithPath: "/tmp/c"), totalBytes: 100, status: .completed),
            ],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: []
        )

        store.cancelDownloads()

        XCTAssertEqual(store.downloadJobs[0].status, .failed)
        XCTAssertEqual(store.downloadJobs[1].status, .failed)
        XCTAssertEqual(store.downloadJobs[2].status, .completed)
    }

    @MainActor
    func testCancellingQueuedDownloadRemovesItBeforeNextDownloadStarts() async throws {
        let service = ControlledDownloadService()
        let first = DownloadJob(title: "第一个", source: .official, destination: URL(fileURLWithPath: "/tmp/first"), totalBytes: 1)
        let cancelled = DownloadJob(title: "取消项", source: .official, destination: URL(fileURLWithPath: "/tmp/cancelled"), totalBytes: 1)
        let next = DownloadJob(title: "下一项", source: .official, destination: URL(fileURLWithPath: "/tmp/next"), totalBytes: 1)
        let store = LauncherStore(
            instances: [],
            downloadJobs: [first, cancelled, next],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: [],
            downloadService: service
        )
        store.maxDownloadThreads = 1

        await store.executeQueuedDownloads()
        XCTAssertEqual(service.startedJobs.map(\.id), [first.id])

        store.cancelJob(id: cancelled.id)
        XCTAssertEqual(store.downloadJobs.first { $0.id == cancelled.id }?.status, .failed)

        var completedFirst = first
        completedFirst.status = .completed
        completedFirst.completedBytes = completedFirst.totalBytes
        service.onComplete?(first.id, completedFirst)
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(service.startedJobs.map(\.id), [first.id, next.id])
        XCTAssertEqual(store.downloadJobs.first { $0.id == cancelled.id }?.status, .failed)
        XCTAssertEqual(store.downloadJobs.first { $0.id == next.id }?.status, .running)
    }

    @MainActor
    func testCancellingRunningDownloadReleasesSlotAfterCancellationCallback() async throws {
        let service = ControlledDownloadService()
        let running = DownloadJob(title: "正在下载", source: .official, destination: URL(fileURLWithPath: "/tmp/running"), totalBytes: 1)
        let next = DownloadJob(title: "排队下一项", source: .official, destination: URL(fileURLWithPath: "/tmp/next"), totalBytes: 1)
        let store = LauncherStore(
            instances: [],
            downloadJobs: [running, next],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: [],
            downloadService: service
        )
        store.maxDownloadThreads = 1

        await store.executeQueuedDownloads()
        store.cancelJob(id: running.id)
        XCTAssertEqual(service.cancelledIDs, [running.id])

        service.onCancelled?(running.id)
        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertEqual(store.downloadJobs.first { $0.id == running.id }?.status, .failed)
        XCTAssertEqual(store.downloadJobs.first { $0.id == next.id }?.status, .running)
        XCTAssertEqual(service.startedJobs.map(\.id), [running.id, next.id])
    }

    @MainActor
    func testStoreExposesNewGitHubReleaseAndAutomaticZIPAsset() async {
        let service = StubAppUpdateService(release: Self.makeUpdateRelease(version: "0.1.2"))
        let store = LauncherStore(
            instances: [],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: [],
            appUpdateService: service
        )

        await store.checkForUpdates(showDiagnostics: false)

        XCTAssertTrue(store.updateAvailable)
        XCTAssertEqual(store.latestVersion, "0.1.2")
        XCTAssertEqual(store.updateDownloadURL, service.release.automaticAsset?.browserDownloadURL)
        XCTAssertEqual(store.updateReleaseURL, service.release.htmlURL)
    }

    @MainActor
    func testStoreDelegatesUpdateInstallationToReleaseService() async {
        let service = StubAppUpdateService(release: Self.makeUpdateRelease(version: "0.1.2"))
        let store = LauncherStore(
            instances: [],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: [],
            appUpdateService: service
        )

        await store.checkForUpdates(showDiagnostics: false)
        await store.downloadAndInstallUpdate()

        XCTAssertEqual(service.installedRelease, service.release)
        XCTAssertEqual(store.diagnostics.first?.title, "更新准备完成")
    }

    private static func makeUpdateRelease(version: String) -> AppUpdateRelease {
        AppUpdateRelease(
            tagName: "v\(version)",
            version: SemanticVersion(version)!,
            title: "v\(version)",
            notes: "更新说明",
            htmlURL: URL(string: "https://github.com/Lhy723/MMCL/releases/tag/v\(version)"),
            assets: [
                AppUpdateAsset(
                    name: "MMCL-v\(version).zip",
                    browserDownloadURL: URL(string: "https://example.com/MMCL-v\(version).zip")!,
                    contentType: "application/zip",
                    size: 1,
                    digest: nil
                )
            ]
        )
    }

    private static let versionMetadataJSON = """
    {
      "id": "1.21.5",
      "mainClass": "net.minecraft.client.main.Main",
      "assets": "19",
      "assetIndex": {
        "id": "19",
        "url": "https://piston-meta.mojang.com/v1/packages/assets.json",
        "sha1": "asset-sha1",
        "size": 321
      },
      "downloads": {
        "client": {
          "url": "https://piston-data.mojang.com/v1/objects/client.jar",
          "sha1": "client-sha1",
          "size": 123
        }
      },
      "libraries": [
        {
          "name": "org.lwjgl:lwjgl:3.3.3",
          "natives": {
            "osx": "natives-macos"
          },
          "downloads": {
            "classifiers": {
              "natives-macos": {
                "path": "org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3-natives-macos.jar",
                "url": "https://libraries.minecraft.net/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3-natives-macos.jar",
                "sha1": "native-sha1",
                "size": 789
              }
            }
          }
        }
      ]
    }
    """
}

private final class StubAppUpdateService: AppUpdateServicing {
    let release: AppUpdateRelease
    private(set) var installedRelease: AppUpdateRelease?

    init(release: AppUpdateRelease) {
        self.release = release
    }

    func fetchLatestRelease() async throws -> AppUpdateRelease {
        release
    }

    func installUpdate(_ release: AppUpdateRelease) async throws {
        installedRelease = release
    }
}

private final class ControlledDownloadService: DownloadServicing {
    var onProgress: ((UUID, Int64) -> Void)?
    var onComplete: ((UUID, DownloadJob) -> Void)?
    var onError: ((UUID, Error) -> Void)?
    var onCancelled: ((UUID) -> Void)?

    private(set) var startedJobs: [DownloadJob] = []
    private(set) var cancelledIDs: [UUID] = []

    func makeVanillaClientJob(version: String, destination: URL) -> DownloadJob {
        DownloadJob(title: version, source: .official, destination: destination, totalBytes: 1)
    }

    func writeVersionMetadata(metadata: VersionMetadata, instance: LauncherInstance) throws -> URL {
        instance.rootDirectory.appendingPathComponent("\(metadata.id).json")
    }

    func makeVanillaInstallJobs(
        metadata: VersionMetadata,
        instance: LauncherInstance,
        source: DownloadSource
    ) -> [DownloadJob] {
        []
    }

    func makeVanillaRepairJobs(
        metadata: VersionMetadata,
        instance: LauncherInstance,
        source: DownloadSource
    ) -> [DownloadJob] {
        []
    }

    func makeAssetObjectJobs(
        assetIndex: AssetIndex,
        instance: LauncherInstance,
        source: DownloadSource,
        taskGroupID: UUID?,
        taskGroupName: String?
    ) -> [DownloadJob] {
        []
    }

    func prepareNativeLibraries(metadata: VersionMetadata, instance: LauncherInstance) throws -> [URL] {
        []
    }

    func validateLoaderInstallation(metadata: VersionMetadata, instance: LauncherInstance) throws {}

    func startDownload(_ job: DownloadJob) {
        startedJobs.append(job)
    }

    func pauseDownload(id: UUID) {}

    func resumeDownload(id: UUID) {}

    func cancelDownload(id: UUID) {
        cancelledIDs.append(id)
    }

    func cancelAllDownloads() {}
}
