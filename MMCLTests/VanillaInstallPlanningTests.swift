import XCTest
@testable import MMCL

@MainActor
final class VanillaInstallPlanningTests: XCTestCase {
    func testVersionMetadataParsesClientAssetIndexAndLibraries() throws {
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
          "libraries": [
            {
              "name": "org.lwjgl:lwjgl:3.3.3",
              "natives": {
                "osx": "natives-macos"
              },
              "downloads": {
                "artifact": {
                  "path": "org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar",
                  "url": "https://libraries.minecraft.net/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar",
                  "sha1": "library-sha1",
                  "size": 456
                },
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

        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(json.utf8))

        XCTAssertEqual(metadata.id, "1.21.5")
        XCTAssertEqual(metadata.mainClass, "net.minecraft.client.main.Main")
        XCTAssertEqual(metadata.assetIndex.id, "19")
        XCTAssertEqual(metadata.downloads.client.size, 123)
        XCTAssertEqual(metadata.libraries[0].artifact?.path, "org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar")
        XCTAssertEqual(metadata.libraries[0].nativeArtifact()?.path, "org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3-natives-macos.jar")
    }

    func testDownloadServicePlansVanillaInstallJobs() throws {
        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.versionMetadataJSON.utf8))
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: URL(fileURLWithPath: "/Users/example/Instances/vanilla", isDirectory: true),
            status: .notInstalled
        )

        let jobs = DownloadService().makeVanillaInstallJobs(metadata: metadata, instance: instance, source: .official)

        XCTAssertEqual(jobs.map(\.title), [
            "Minecraft 1.21.5 客户端",
            "Minecraft 1.21.5 资源索引",
            "org.lwjgl:lwjgl:3.3.3",
            "org.lwjgl:lwjgl:3.3.3 native"
        ])
        XCTAssertEqual(jobs[0].remoteURL?.absoluteString, "https://piston-data.mojang.com/v1/objects/client.jar")
        XCTAssertEqual(jobs[0].sha1, "client-sha1")
        XCTAssertEqual(jobs[0].destination.path, "/Users/example/Instances/vanilla/.minecraft/versions/1.21.5/1.21.5.jar")
        XCTAssertEqual(jobs[1].destination.path, "/Users/example/Instances/vanilla/.minecraft/assets/indexes/19.json")
        XCTAssertEqual(jobs[2].destination.path, "/Users/example/Instances/vanilla/.minecraft/libraries/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar")
        XCTAssertEqual(jobs[3].destination.path, "/Users/example/Instances/vanilla/.minecraft/libraries/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3-natives-macos.jar")
        XCTAssertEqual(jobs[3].sha1, "native-sha1")
    }

    func testDownloadServicePlansOnlyMissingRepairJobs() throws {
        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.versionMetadataJSON.utf8))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root,
            status: .missingFiles
        )
        let assetIndex = root.appendingPathComponent(".minecraft/assets/indexes/19.json")
        let library = root.appendingPathComponent(".minecraft/libraries/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar")
        try FileManager.default.createDirectory(at: assetIndex.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("asset-index".utf8).write(to: assetIndex)
        try Data("library".utf8).write(to: library)

        let jobs = DownloadService().makeVanillaRepairJobs(metadata: metadata, instance: instance, source: .official)

        XCTAssertEqual(jobs.map(\.title), [
            "Minecraft 1.21.5 客户端",
            "org.lwjgl:lwjgl:3.3.3 native"
        ])
    }

    func testDownloadServiceWritesVersionMetadataToVersionDirectory() throws {
        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.versionMetadataJSON.utf8))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root,
            status: .notInstalled
        )

        let metadataURL = try DownloadService().writeVersionMetadata(metadata: metadata, instance: instance)
        let saved = try VersionManifestService().decodeVersionMetadata(from: Data(contentsOf: metadataURL))

        XCTAssertEqual(metadataURL.path, root.appendingPathComponent(".minecraft/versions/1.21.5/1.21.5.json").path)
        XCTAssertEqual(saved, metadata)
    }

    func testInstanceServiceCreatesVanillaInstanceOnDisk() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let service = InstanceService(applicationSupportDirectory: temporaryRoot)

        let instance = try service.createInstance(
            name: "原版 生存!",
            gameVersion: "1.21.5",
            loader: .vanilla,
            profile: LaunchProfile(offlineUsername: "Steve", memoryMegabytes: 4096, jvmArguments: [], resolutionWidth: 854, resolutionHeight: 480)
        )

        XCTAssertEqual(instance.name, "原版 生存!")
        XCTAssertEqual(instance.rootDirectory.lastPathComponent, "yuan-ban-sheng-cun")
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.instanceFileURL(for: instance).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: instance.rootDirectory.appendingPathComponent(".minecraft").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: instance.rootDirectory.appendingPathComponent("logs").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: instance.rootDirectory.appendingPathComponent("mods").path))

        let saved = try service.decode(from: Data(contentsOf: service.instanceFileURL(for: instance)))
        XCTAssertEqual(saved, instance)
    }

    func testDownloadServicePreparesNativeLibraries() throws {
        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.versionMetadataJSON.utf8))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root,
            status: .notInstalled
        )
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

        let preparedArchives = try DownloadService().prepareNativeLibraries(metadata: metadata, instance: instance)

        XCTAssertEqual(preparedArchives.map(\.path), [nativeArchive.path])
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
            "artifact": {
              "path": "org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar",
              "url": "https://libraries.minecraft.net/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar",
              "sha1": "library-sha1",
              "size": 456
            },
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
