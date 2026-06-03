import XCTest
@testable import MMCL

final class LauncherServiceTests: XCTestCase {
    func testApplicationSupportRootUsesMMCLDirectory() throws {
        let service = InstanceService(applicationSupportDirectory: URL(fileURLWithPath: "/Users/example/Library/Application Support", isDirectory: true))

        XCTAssertEqual(service.rootDirectory.path, "/Users/example/Library/Application Support/MMCL")
        XCTAssertEqual(service.instancesDirectory.path, "/Users/example/Library/Application Support/MMCL/Instances")
    }

    func testVersionManifestParsesLatestReleaseAndVersions() throws {
        let json = """
        {
          "latest": { "release": "1.21.5", "snapshot": "25w21a" },
          "versions": [
            {
              "id": "1.21.5",
              "type": "release",
              "url": "https://piston-meta.mojang.com/v1/packages/1.21.5.json",
              "time": "2026-05-20T10:00:00+00:00",
              "releaseTime": "2026-05-20T10:00:00+00:00"
            },
            {
              "id": "25w21a",
              "type": "snapshot",
              "url": "https://piston-meta.mojang.com/v1/packages/25w21a.json",
              "time": "2026-05-21T10:00:00+00:00",
              "releaseTime": "2026-05-21T10:00:00+00:00"
            }
          ]
        }
        """

        let manifest = try VersionManifestService().decodeManifest(from: Data(json.utf8))

        XCTAssertEqual(manifest.latest.release, "1.21.5")
        XCTAssertEqual(manifest.latest.snapshot, "25w21a")
        XCTAssertEqual(manifest.versions.map(\.id), ["1.21.5", "25w21a"])
        XCTAssertEqual(manifest.versions[0].type, .release)
        XCTAssertEqual(manifest.versions[0].recommendedJavaMajorVersion, 21)
        XCTAssertEqual(manifest.versions[0].metadataURL.absoluteString, "https://piston-meta.mojang.com/v1/packages/1.21.5.json")
    }

    func testJavaRuntimeServiceParsesJavaHomeOutput() throws {
        let output = """
        Matching Java Virtual Machines (2):
            21.0.3 (arm64) \"Eclipse Adoptium\" - \"Temurin 21\" /Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
            17.0.11 (x86_64) \"Azul Systems\" - \"Zulu 17\" /Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home
        /Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
        """

        let runtimes = JavaRuntimeService().parseJavaHomeVerboseOutput(output)

        XCTAssertEqual(runtimes.count, 2)
        XCTAssertEqual(runtimes[0].name, "Temurin 21")
        XCTAssertEqual(runtimes[0].version, "21.0.3")
        XCTAssertEqual(runtimes[0].majorVersion, 21)
        XCTAssertEqual(runtimes[0].architecture, .arm64)
        XCTAssertEqual(runtimes[0].executableURL.path, "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        XCTAssertEqual(runtimes[1].architecture, .x86_64)
    }

    func testLaunchServiceBuildsMinecraftArgumentPreview() {
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: URL(fileURLWithPath: "/Users/example/Instances/vanilla", isDirectory: true),
            profile: LaunchProfile(offlineUsername: "Steve", memoryMegabytes: 4096, jvmArguments: ["-XX:+UseG1GC"], resolutionWidth: 854, resolutionHeight: 480),
            status: .ready
        )
        let java = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )

        let command = LaunchService().previewCommand(for: instance, java: java)

        XCTAssertEqual(command[0], "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        XCTAssertTrue(command.contains("-Xmx4096m"))
        XCTAssertTrue(command.contains("-Djava.library.path=/Users/example/Instances/vanilla/.minecraft/versions/1.21.5/natives"))
        XCTAssertTrue(command.contains("--username"))
        XCTAssertTrue(command.contains("Steve"))
        XCTAssertTrue(command.contains("--gameDir"))
        XCTAssertTrue(command.contains("/Users/example/Instances/vanilla/.minecraft"))
        XCTAssertTrue(command.contains("--version"))
        XCTAssertTrue(command.contains("1.21.5"))
    }

    func testLaunchServiceBuildsPreciseClasspathFromLocalVersionMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root,
            profile: LaunchProfile(offlineUsername: "Steve", memoryMegabytes: 4096, jvmArguments: [], resolutionWidth: 854, resolutionHeight: 480),
            status: .ready
        )
        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.versionMetadataJSON.utf8))
        _ = try DownloadService().writeVersionMetadata(metadata: metadata, instance: instance)
        let java = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )

        let command = LaunchService().previewCommand(for: instance, java: java)
        let classpath = try XCTUnwrap(command.argument(after: "-cp"))

        XCTAssertFalse(classpath.contains("libraries/*"))
        XCTAssertTrue(classpath.contains(root.appendingPathComponent(".minecraft/libraries/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar").path))
        XCTAssertTrue(classpath.contains(root.appendingPathComponent(".minecraft/versions/1.21.5/1.21.5.jar").path))
        XCTAssertTrue(command.contains("net.minecraft.client.main.Main"))
        XCTAssertEqual(command.argument(after: "--assetIndex"), "19")
    }

    func testLaunchServiceExpandsModernMojangArguments() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root,
            profile: LaunchProfile(offlineUsername: "Steve", memoryMegabytes: 4096, jvmArguments: ["-XX:+UseG1GC"], resolutionWidth: 854, resolutionHeight: 480),
            status: .ready
        )
        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.modernArgumentsMetadataJSON.utf8))
        _ = try DownloadService().writeVersionMetadata(metadata: metadata, instance: instance)
        let java = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )

        let command = LaunchService().previewCommand(for: instance, java: java)
        let classpath = try XCTUnwrap(command.argument(after: "-cp"))

        XCTAssertTrue(command.contains("-XX:+UseG1GC"))
        XCTAssertTrue(command.contains("-Djava.library.path=\(root.path)/.minecraft/versions/1.21.5/natives"))
        XCTAssertTrue(command.contains("-Xdock:name=MMCL"))
        XCTAssertFalse(command.contains("-Dos.name=Windows"))
        XCTAssertEqual(classpath, [
            root.appendingPathComponent(".minecraft/libraries/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar").path,
            root.appendingPathComponent(".minecraft/versions/1.21.5/1.21.5.jar").path
        ].joined(separator: ":"))
        XCTAssertEqual(command.argument(after: "--username"), "Steve")
        XCTAssertEqual(command.argument(after: "--assetsDir"), root.appendingPathComponent(".minecraft/assets").path)
        XCTAssertEqual(command.argument(after: "--assetIndex"), "19")
    }

    func testLaunchServiceExpandsLegacyMinecraftArguments() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "旧版生存",
            gameVersion: "1.12.2",
            loader: .vanilla,
            rootDirectory: root,
            profile: LaunchProfile(offlineUsername: "Alex", memoryMegabytes: 2048, jvmArguments: [], resolutionWidth: 854, resolutionHeight: 480),
            status: .ready
        )
        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.legacyArgumentsMetadataJSON.utf8))
        _ = try DownloadService().writeVersionMetadata(metadata: metadata, instance: instance)
        let java = JavaRuntime(
            name: "Temurin 8",
            version: "1.8.0",
            majorVersion: 8,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-8.jdk/Contents/Home/bin/java")
        )

        let command = LaunchService().previewCommand(for: instance, java: java)

        XCTAssertEqual(command.argument(after: "--username"), "Alex")
        XCTAssertEqual(command.argument(after: "--version"), "1.12.2")
        XCTAssertEqual(command.argument(after: "--assetIndex"), "legacy")
        XCTAssertTrue(command.contains("net.minecraft.client.main.Main"))
    }

    func testLaunchServicePreflightReportsMissingInstallFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root,
            status: .ready
        )
        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.versionMetadataJSON.utf8))
        _ = try DownloadService().writeVersionMetadata(metadata: metadata, instance: instance)
        let java = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )

        let report = LaunchService().preflight(instance: instance, java: java)

        XCTAssertFalse(report.canLaunch)
        XCTAssertEqual(report.severity, .error)
        XCTAssertTrue(report.summary.contains("client jar"))
        XCTAssertTrue(report.summary.contains("asset index"))
        XCTAssertTrue(report.summary.contains("library"))
        XCTAssertEqual(report.suggestedActions.first, "生成安装计划并完成下载")
    }

    func testLaunchServicePreflightPassesForCompleteVanillaInstance() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root,
            status: .ready
        )
        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.versionMetadataJSON.utf8))
        _ = try DownloadService().writeVersionMetadata(metadata: metadata, instance: instance)
        try Data("client".utf8).write(to: root.appendingPathComponent(".minecraft/versions/1.21.5/1.21.5.jar"))
        let assetIndex = root.appendingPathComponent(".minecraft/assets/indexes/19.json")
        try FileManager.default.createDirectory(at: assetIndex.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("assets".utf8).write(to: assetIndex)
        let library = root.appendingPathComponent(".minecraft/libraries/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar")
        try FileManager.default.createDirectory(at: library.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("library".utf8).write(to: library)
        let java = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )

        let report = LaunchService().preflight(instance: instance, java: java)

        XCTAssertTrue(report.canLaunch)
        XCTAssertEqual(report.severity, .info)
        XCTAssertEqual(report.summary, "启动前检查通过。")
        XCTAssertTrue(report.suggestedActions.isEmpty)
    }

    func testLaunchServiceStartsProcessAndCreatesLatestLog() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root,
            profile: LaunchProfile(offlineUsername: "Steve", memoryMegabytes: 512, jvmArguments: [], resolutionWidth: 854, resolutionHeight: 480),
            status: .ready
        )
        let java = JavaRuntime(
            name: "Echo",
            version: "1.0",
            majorVersion: 21,
            architecture: .universal,
            executableURL: URL(fileURLWithPath: "/bin/echo")
        )

        let session = try LaunchService().launch(instance: instance, java: java)

        XCTAssertGreaterThan(session.processIdentifier, 0)
        XCTAssertEqual(session.logFileURL.path, root.appendingPathComponent("logs/latest.log").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".minecraft").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.logFileURL.path))
        XCTAssertEqual(session.command.first, "/bin/echo")
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
          "downloads": {
            "artifact": {
              "path": "org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar",
              "url": "https://libraries.minecraft.net/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar",
              "sha1": "library-sha1",
              "size": 456
            }
          }
        }
      ]
    }
    """

    private static let modernArgumentsMetadataJSON = """
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
          "downloads": {
            "artifact": {
              "path": "org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar",
              "url": "https://libraries.minecraft.net/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar",
              "sha1": "library-sha1",
              "size": 456
            }
          }
        }
      ],
      "arguments": {
        "jvm": [
          "-Djava.library.path=${natives_directory}",
          "-cp",
          "${classpath}",
          {
            "rules": [{ "action": "allow", "os": { "name": "osx" } }],
            "value": "-Xdock:name=${launcher_name}"
          },
          {
            "rules": [{ "action": "allow", "os": { "name": "windows" } }],
            "value": "-Dos.name=Windows"
          }
        ],
        "game": [
          "--username",
          "${auth_player_name}",
          "--version",
          "${version_name}",
          "--gameDir",
          "${game_directory}",
          "--assetsDir",
          "${assets_root}",
          "--assetIndex",
          "${assets_index_name}",
          "--accessToken",
          "${auth_access_token}",
          "--userType",
          "${user_type}"
        ]
      }
    }
    """

    func testFabricServiceFetchesLoaderVersionsFromAPI() async throws {
        // Test with local file would be ideal, but the API is simple enough
        // to test the model parsing
        let json = """
        [{"version":"0.16.14","stable":true},{"version":"0.16.13","stable":false}]
        """.data(using: .utf8)!
        let versions = try JSONDecoder.mmcl.decode([FabricLoaderVersion].self, from: json)
        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(versions.first?.version, "0.16.14")
        XCTAssertTrue(versions.first?.stable == true)
    }

    func testFabricProfileParsesMainClassAndInheritsFrom() throws {
        let json = """
        {
            "id": "1.21.5-fabric-0.16.14",
            "inheritsFrom": "1.21.5",
            "mainClass": "net.fabricmc.loader.impl.launch.knot.KnotClient",
            "arguments": {
                "game": ["--assetIndex", "${assets_index_name}"]
            }
        }
        """.data(using: .utf8)!
        let profile = try JSONDecoder.mmcl.decode(FabricProfile.self, from: json)
        XCTAssertEqual(profile.id, "1.21.5-fabric-0.16.14")
        XCTAssertEqual(profile.inheritsFrom, "1.21.5")
        XCTAssertEqual(profile.mainClass, "net.fabricmc.loader.impl.launch.knot.KnotClient")
        XCTAssertEqual(profile.arguments?.game?.first, "--assetIndex")
    }

    func testModrinthSearchResponseParsesHits() throws {
        let json = """
        {
            "hits": [
                {"project_id": "AqQJnBxM", "slug": "sodium", "title": "Sodium", "description": "A modern rendering engine", "project_type": "mod", "downloads": 5000000, "categories": ["performance", "optimization"]}
            ],
            "total_hits": 1
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder.mmcl.decode(ModrinthSearchResponse.self, from: json)
        XCTAssertEqual(response.totalHits, 1)
        XCTAssertEqual(response.hits.first?.title, "Sodium")
        XCTAssertEqual(response.hits.first?.downloads, 5000000)
    }

    func testModrinthVersionParsesFilesAndLoaders() throws {
        let json = """
        [
            {
                "id": "abc123",
                "name": "Sodium 0.6.0",
                "version_number": "0.6.0",
                "game_versions": ["1.21.5"],
                "loaders": ["fabric"],
                "files": [
                    {"filename": "sodium-fabric-0.6.0.jar", "url": "https://example.com/sodium.jar", "size": 12345, "primary": true}
                ]
            }
        ]
        """.data(using: .utf8)!
        let versions = try JSONDecoder.mmcl.decode([ModrinthVersion].self, from: json)
        XCTAssertEqual(versions.count, 1)
        XCTAssertEqual(versions.first?.files.first?.filename, "sodium-fabric-0.6.0.jar")
        XCTAssertEqual(versions.first?.loaders, ["fabric"])
    }

    func testQuiltLoaderVersionParsesCorrectly() throws {
        let json = """
        [{"version":"0.5.0","stable":true},{"version":"0.4.0","stable":false}]
        """.data(using: .utf8)!
        let versions = try JSONDecoder.mmcl.decode([QuiltLoaderVersion].self, from: json)
        XCTAssertEqual(versions.count, 2)
        XCTAssertTrue(versions[0].stable)
    }

    func testForgeVersionParsesPromotions() throws {
        let json = """
        {"promos":{"1.21.5-latest":"56.0.1","1.21.5-recommended":"56.0.0","1.20.1-latest":"47.3.0"}}
        """.data(using: .utf8)!
        let promo = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        let promos = promo?["promos"] as? [String: String] ?? [:]
        XCTAssertEqual(promos["1.21.5-latest"], "56.0.1")
        XCTAssertEqual(promos["1.20.1-latest"], "47.3.0")
    }

    func testModrinthVersionRowDisplaysCorrectInfo() throws {
        let file = ModrinthFile(filename: "mod.jar", url: "https://example.com/mod.jar", size: 1000, primary: true)
        let version = ModrinthVersion(id: "v1", name: "Mod 1.0", versionNumber: "1.0.0", gameVersions: ["1.21.5"], loaders: ["fabric"], files: [file])
        XCTAssertEqual(version.files.first?.filename, "mod.jar")
        XCTAssertEqual(version.loaders, ["fabric"])
    }

    private static let legacyArgumentsMetadataJSON = """
    {
      "id": "1.12.2",
      "mainClass": "net.minecraft.client.main.Main",
      "assets": "legacy",
      "assetIndex": {
        "id": "legacy",
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
      "minecraftArguments": "--username ${auth_player_name} --version ${version_name} --gameDir ${game_directory} --assetsDir ${assets_root} --assetIndex ${assets_index_name} --accessToken ${auth_access_token} --userType ${user_type}"
    }
    """

    func testMinecraftAccountDisplayNames() {
        let offline = MinecraftAccount(username: "Steve", type: .offline)
        let online = MinecraftAccount(username: "Notch", uuid: "abc", accessToken: "token", refreshToken: "refresh", type: .microsoft)
        XCTAssertEqual(offline.displayName, "Steve（离线）")
        XCTAssertEqual(online.displayName, "Notch")
    }

    func testMinecraftAccountRoundTripsThroughJSON() throws {
        let account = MinecraftAccount(username: "Test", uuid: "uuid-123", accessToken: "at", refreshToken: "rt", expiresAt: Date(timeIntervalSince1970: 1000), type: .microsoft)
        let data = try JSONEncoder.mmcl.encode(account)
        let decoded = try JSONDecoder.mmcl.decode(MinecraftAccount.self, from: data)
        XCTAssertEqual(decoded.username, "Test")
        XCTAssertEqual(decoded.type, .microsoft)
    }
}

private extension Array where Element == String {
    func argument(after marker: String) -> String? {
        guard let index = firstIndex(of: marker) else { return nil }
        let nextIndex = self.index(after: index)
        guard nextIndex < endIndex else { return nil }
        return self[nextIndex]
    }
}
