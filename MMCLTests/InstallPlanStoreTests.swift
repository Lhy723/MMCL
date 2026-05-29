import XCTest
@testable import MMCL

@MainActor
final class InstallPlanStoreTests: XCTestCase {
    func testStorePlansVanillaInstallForSelectedInstance() throws {
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
        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.versionMetadataJSON.utf8))
        let store = LauncherStore(
            instances: [instance],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: []
        )

        store.planVanillaInstall(metadata: metadata, for: instance)

        XCTAssertEqual(store.downloadJobs.count, 3)
        XCTAssertEqual(store.downloadJobs[0].title, "Minecraft 1.21.5 客户端")
        XCTAssertEqual(store.downloadJobs[0].status, .queued)
        XCTAssertEqual(store.plannedVersionMetadata, metadata)
        XCTAssertEqual(store.plannedInstanceID, instance.id)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".minecraft/versions/1.21.5/1.21.5.json").path
        ))
        XCTAssertEqual(store.diagnostics.first?.title, "已生成 Vanilla 安装计划")
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
}
