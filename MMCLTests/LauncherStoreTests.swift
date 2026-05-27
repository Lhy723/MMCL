import XCTest
@testable import MMCL

final class LauncherStoreTests: XCTestCase {
    func testStoreBuildsLaunchPreviewForSelectedInstanceAndJava() {
        let instanceID = UUID()
        let instance = LauncherInstance(
            id: instanceID,
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: URL(fileURLWithPath: "/Users/example/Instances/vanilla", isDirectory: true),
            profile: LaunchProfile(offlineUsername: "Steve", memoryMegabytes: 4096, jvmArguments: []),
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
        store.selectedSection = .instance(instanceID)
        store.selectedJavaRuntimeID = runtime.id

        let preview = store.launchPreviewForSelectedInstance()

        XCTAssertNotNil(preview)
        XCTAssertEqual(preview?.java.displayName, "Temurin 21 · Java 21 · Apple Silicon")
        XCTAssertTrue(preview?.command.contains("--username") == true)
        XCTAssertTrue(preview?.command.contains("Steve") == true)
    }

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
        store.selectedSection = .instance(instanceID)

        await store.refreshJavaRuntimes()

        XCTAssertEqual(store.javaRuntimes.map(\.majorVersion), [17, 21])
        XCTAssertEqual(store.selectedJavaRuntimeID, java21.id)
        XCTAssertEqual(store.diagnostics.first?.title, "Java 运行时已刷新")
    }

    func testStoreLaunchesSelectedInstanceAndRecordsSession() {
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
        let store = LauncherStore(
            instances: [instance],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [runtime],
            availableVersions: [],
            launchService: StubLaunchService(session: expectedSession)
        )
        store.selectedSection = .instance(instanceID)
        store.selectedJavaRuntimeID = runtime.id

        store.launchSelectedInstance()

        XCTAssertEqual(store.currentLaunchSession, expectedSession)
        XCTAssertEqual(store.diagnostics.first?.title, "Minecraft 已启动")
        XCTAssertTrue(store.diagnostics.first?.summary.contains("42") == true)
    }

    func testStoreBlocksLaunchWhenPreflightFails() {
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
        store.selectedSection = .instance(instanceID)
        store.selectedJavaRuntimeID = runtime.id

        store.launchSelectedInstance()

        XCTAssertNil(store.currentLaunchSession)
        XCTAssertFalse(failingLaunchService.didLaunch)
        XCTAssertEqual(store.instances.first?.status, .missingFiles)
        XCTAssertEqual(store.diagnostics.first?.title, "启动前检查未通过")
        XCTAssertEqual(store.diagnostics.first?.suggestedActions.first, "生成安装计划并完成下载")
    }

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
        store.selectedSection = .instance(instanceID)

        store.deleteInstance(instance)

        XCTAssertTrue(store.instances.isEmpty)
        XCTAssertNil(store.selectedInstance)
    }

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
        store.selectedSection = .instance(instanceID)
        store.selectedJavaRuntimeID = runtime.id

        store.inspectSelectedInstance()

        XCTAssertEqual(store.instances.first?.status, .missingFiles)
        XCTAssertEqual(store.diagnostics.first?.title, "实例需要修复")
        XCTAssertEqual(store.diagnostics.first?.summary, "缺少 asset index。")
    }

    func testStorePreparesNativeLibrariesAndMarksInstanceReady() throws {
        let instanceID = UUID()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            id: instanceID,
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root,
            status: .notInstalled
        )
        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.versionMetadataJSON.utf8))
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
        store.selectedSection = .instance(instanceID)
        store.planVanillaInstall(metadata: metadata, for: instance)

        store.prepareNativeLibrariesForSelectedInstance()

        XCTAssertEqual(store.instances.first?.status, .ready)
        XCTAssertEqual(store.diagnostics.first?.title, "Native libraries 已准备")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".minecraft/versions/1.21.5/natives/libmmcl.dylib").path
        ))
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

        func previewCommand(for instance: LauncherInstance, java: JavaRuntime) -> [String] {
            session.command
        }

        func preflight(instance: LauncherInstance, java: JavaRuntime) -> LaunchPreflightReport {
            preflightReport
        }

        func launch(instance: LauncherInstance, java: JavaRuntime) throws -> LaunchSession {
            didLaunch = true
            return session
        }
    }

    private struct StubJavaRuntimeService: JavaRuntimeServicing {
        let runtimes: [JavaRuntime]

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
            let slug = InstanceService.slug(for: name)
            let instanceRoot = instancesDirectory.appendingPathComponent(slug, isDirectory: true)
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
