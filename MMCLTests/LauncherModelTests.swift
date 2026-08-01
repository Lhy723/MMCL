import XCTest
@testable import MMCL

final class LauncherModelTests: XCTestCase {
    func testNeoForgeIsFirstClassGameLoader() throws {
        XCTAssertTrue(GameLoader.allCases.contains(.neoForge))
        XCTAssertEqual(GameLoader(rawValue: "NeoForge"), .neoForge)
        XCTAssertEqual(GameLoader.neoForge.modrinthLoaderName, "neoforge")

        let root = URL(fileURLWithPath: "/Users/example/Library/Application Support/MMCL/Instances/neoforge")
        let instance = LauncherInstance(
            name: "NeoForge 生存",
            gameVersion: "1.21.5",
            loader: .neoForge,
            rootDirectory: root
        )

        XCTAssertEqual(instance.subtitle, "1.21.5 · NeoForge")
        XCTAssertEqual(instance.blockIcon, "NeoForge")

        let data = try JSONEncoder.mmcl.encode(instance)
        let decoded = try JSONDecoder.mmcl.decode(LauncherInstance.self, from: data)
        XCTAssertEqual(decoded.loader, .neoForge)
        XCTAssertEqual(decoded.launchVersionID, "1.21.5")
    }

    func testContentProjectRoundTripsNeoForgeLoader() throws {
        let project = ContentProject(
            id: "neoforge-project",
            title: "NeoForge Mod",
            type: .mod,
            source: "Modrinth",
            gameVersions: ["1.21.5"],
            loaders: [.neoForge]
        )

        let data = try JSONEncoder.mmcl.encode(project)
        let decoded = try JSONDecoder.mmcl.decode(ContentProject.self, from: data)

        XCTAssertEqual(decoded.loaders, [.neoForge])
    }

    func testLauncherInstanceRoundTripsThroughJSON() throws {
        let root = URL(fileURLWithPath: "/Users/example/Library/Application Support/MMCL/Instances/vanilla")
        let instance = LauncherInstance(
            name: "生存 1.21",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root,
            profile: LaunchProfile(offlineUsername: "Steve", memoryMegabytes: 4096, jvmArguments: ["-XX:+UseG1GC"], resolutionWidth: 854, resolutionHeight: 480),
            status: .ready,
            lastPlayedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder.mmcl.encode(instance)
        let decoded = try JSONDecoder.mmcl.decode(LauncherInstance.self, from: data)

        XCTAssertEqual(decoded.name, "生存 1.21")
        XCTAssertEqual(decoded.gameVersion, "1.21.5")
        XCTAssertEqual(decoded.launchVersionID, "1.21.5")
        XCTAssertEqual(decoded.loader, .vanilla)
        XCTAssertEqual(decoded.rootDirectory.path, root.path)
        XCTAssertEqual(decoded.profile.offlineUsername, "Steve")
        XCTAssertEqual(decoded.profile.memoryMegabytes, 4096)
        XCTAssertEqual(decoded.profile.jvmArguments, ["-XX:+UseG1GC"])
        XCTAssertEqual(decoded.status, .ready)
        XCTAssertEqual(decoded.lastPlayedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testLegacyLauncherInstanceDefaultsLaunchVersionIDToGameVersion() throws {
        let instance = LauncherInstance(
            name: "旧实例",
            gameVersion: "1.20.1",
            loader: .vanilla,
            rootDirectory: URL(fileURLWithPath: "/Users/example/Instances/legacy")
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder.mmcl.encode(instance)
            ) as? [String: Any]
        )
        object.removeValue(forKey: "launchVersionID")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder.mmcl.decode(LauncherInstance.self, from: legacyData)

        XCTAssertEqual(decoded.launchVersionID, "1.20.1")
        XCTAssertEqual(decoded.effectiveLaunchVersionID, "1.20.1")
    }

    func testJavaRuntimeReportsArchitectureAndRecommendedState() {
        let runtime = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )

        XCTAssertEqual(runtime.displayName, "Temurin 21 · Java 21 · Apple Silicon")
        XCTAssertTrue(runtime.isRecommended(for: "1.21.5"))
        XCTAssertFalse(runtime.isRecommended(for: "1.16.5"))
    }

    func testDownloadJobProgressAndCompletion() {
        var job = DownloadJob(
            title: "Minecraft 1.21.5",
            source: .official,
            destination: URL(fileURLWithPath: "/tmp/client.jar"),
            totalBytes: 100
        )

        job.update(completedBytes: 25)
        XCTAssertEqual(job.progress, 0.25, accuracy: 0.001)
        XCTAssertEqual(job.status, .running)

        job.update(completedBytes: 100)
        XCTAssertEqual(job.progress, 1.0, accuracy: 0.001)
        XCTAssertEqual(job.status, .completed)
    }

    func testDiagnosticReportProducesChineseSummary() {
        let report = DiagnosticReport(
            title: "Java 架构不匹配",
            severity: .warning,
            summary: "当前实例需要 arm64 Java 运行时。",
            suggestedActions: ["安装 Apple Silicon 版本的 Java 21", "在实例设置中重新选择 Java"]
        )

        XCTAssertEqual(report.localizedSeverity, "警告")
        XCTAssertTrue(report.fullMessage.contains("Java 架构不匹配"))
        XCTAssertTrue(report.fullMessage.contains("安装 Apple Silicon 版本的 Java 21"))
    }

    func testVersionMetadataParsesModernLaunchArguments() throws {
        let json = """
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
          "libraries": [],
          "arguments": {
            "jvm": [
              "-cp",
              "${classpath}",
              {
                "rules": [{ "action": "allow", "os": { "name": "osx" } }],
                "value": ["-XstartOnFirstThread", "-Xdock:name=${launcher_name}"]
              }
            ],
            "game": ["--username", "${auth_player_name}"]
          }
        }
        """

        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(json.utf8))

        XCTAssertEqual(metadata.arguments?.jvm.count, 3)
        XCTAssertEqual(metadata.arguments?.jvm[0].value.strings, ["-cp"])
        XCTAssertEqual(metadata.arguments?.jvm[2].value.strings, ["-XstartOnFirstThread", "-Xdock:name=${launcher_name}"])
        XCTAssertTrue(metadata.arguments?.jvm[2].applies(to: "osx") == true)
        XCTAssertFalse(metadata.arguments?.jvm[2].applies(to: "windows") == true)
    }
}
