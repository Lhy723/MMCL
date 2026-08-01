import XCTest
@testable import MMCL

final class AssetIndexPlanningTests: XCTestCase {
    func testAssetIndexParsesObjectsAndTotals() throws {
        let index = try VersionManifestService().decodeAssetIndex(from: Data(Self.assetIndexJSON.utf8))

        XCTAssertEqual(index.objects.count, 2)
        XCTAssertEqual(index.totalBytes, 30)
        XCTAssertEqual(index.objects["minecraft/sounds/random/pop.ogg"]?.hash, "abcdef0123456789abcdef0123456789abcdef01")
        XCTAssertEqual(index.objects["minecraft/textures/gui/widgets.png"]?.size, 20)
    }

    func testDownloadServicePlansAssetObjectJobs() throws {
        let index = try VersionManifestService().decodeAssetIndex(from: Data(Self.assetIndexJSON.utf8))
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: URL(fileURLWithPath: "/Users/example/Instances/vanilla", isDirectory: true),
            status: .notInstalled
        )

        let jobs = DownloadService().makeAssetObjectJobs(assetIndex: index, instance: instance, source: .official)

        XCTAssertEqual(jobs.count, 2)
        XCTAssertEqual(jobs[0].title, "资源文件 minecraft/sounds/random/pop.ogg")
        XCTAssertEqual(jobs[0].remoteURL?.absoluteString, "https://resources.download.minecraft.net/ab/abcdef0123456789abcdef0123456789abcdef01")
        XCTAssertEqual(jobs[0].destination.path, "/Users/example/Instances/vanilla/.minecraft/assets/objects/ab/abcdef0123456789abcdef0123456789abcdef01")
        XCTAssertEqual(jobs[0].sha1, "abcdef0123456789abcdef0123456789abcdef01")
        XCTAssertEqual(jobs[1].remoteURL?.absoluteString, "https://resources.download.minecraft.net/12/1234567890abcdef1234567890abcdef12345678")
    }

    @MainActor
    func testStoreExpandsDownloadedAssetIndexIntoQueuedJobs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root.appendingPathComponent("instance", isDirectory: true),
            status: .notInstalled
        )
        let assetIndexPath = instance.rootDirectory
            .appendingPathComponent(".minecraft/assets/indexes/19.json")
        try FileManager.default.createDirectory(
            at: assetIndexPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(Self.assetIndexJSON.utf8).write(to: assetIndexPath)
        let store = LauncherStore(
            instances: [instance],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: []
        )

        try store.expandAssetIndexDownloads(assetIndexURL: assetIndexPath, for: instance)

        XCTAssertEqual(store.downloadJobs.count, 2)
        XCTAssertEqual(store.diagnostics.first?.title, "已展开资源文件")
        XCTAssertTrue(store.diagnostics.first?.summary.contains("2 个资源任务") == true)
    }

    @MainActor
    func testSelectedAssetIndexExpansionUsesAssetIndexIDFromLocalMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "资源索引 ID 测试",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root.appendingPathComponent("instance", isDirectory: true),
            status: .notInstalled
        )
        let metadata = try VersionManifestService().decodeVersionMetadata(
            from: Data(Self.versionMetadataJSON.utf8)
        )
        _ = try DownloadService().writeVersionMetadata(metadata: metadata, instance: instance)

        let assetIndexPath = instance.rootDirectory
            .appendingPathComponent(".minecraft/assets/indexes/19.json")
        try FileManager.default.createDirectory(
            at: assetIndexPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(Self.assetIndexJSON.utf8).write(to: assetIndexPath)

        let store = LauncherStore(
            instances: [instance],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: []
        )
        store.launcherSelectedInstanceID = instance.id

        store.expandSelectedInstanceAssetIndex()

        XCTAssertEqual(store.downloadJobs.count, 2)
        XCTAssertEqual(store.diagnostics.first?.title, "已展开资源文件")
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
      "libraries": []
    }
    """

    private static let assetIndexJSON = """
    {
      "objects": {
        "minecraft/sounds/random/pop.ogg": {
          "hash": "abcdef0123456789abcdef0123456789abcdef01",
          "size": 10
        },
        "minecraft/textures/gui/widgets.png": {
          "hash": "1234567890abcdef1234567890abcdef12345678",
          "size": 20
        }
      }
    }
    """
}
