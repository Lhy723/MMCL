import XCTest
@testable import MMCL

final class VersionFetchTests: XCTestCase {
    func testVersionManifestServiceFetchesManifestFromFileURL() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifestURL = root.appendingPathComponent("manifest.json")
        try Data(Self.manifestJSON.utf8).write(to: manifestURL)

        let manifest = try await VersionManifestService().fetchManifest(from: manifestURL)

        XCTAssertEqual(manifest.latest.release, "1.21.5")
        XCTAssertEqual(manifest.versions.first?.id, "1.21.5")
    }

    func testVersionManifestServiceFetchesVersionMetadataFromFileURL() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let metadataURL = root.appendingPathComponent("metadata.json")
        try Data(Self.versionMetadataJSON.utf8).write(to: metadataURL)

        let metadata = try await VersionManifestService().fetchVersionMetadata(from: metadataURL)

        XCTAssertEqual(metadata.id, "1.21.5")
        XCTAssertEqual(metadata.downloads.client.sha1, "client-sha1")
    }

    func testVersionManifestServiceFetchesAssetIndexFromFileURL() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let assetIndexURL = root.appendingPathComponent("asset-index.json")
        try Data(Self.assetIndexJSON.utf8).write(to: assetIndexURL)

        let assetIndex = try await VersionManifestService().fetchAssetIndex(from: assetIndexURL)

        XCTAssertEqual(assetIndex.objects.count, 1)
        XCTAssertEqual(assetIndex.totalBytes, 42)
        XCTAssertEqual(assetIndex.objects["minecraft/sounds/random/pop.ogg"]?.hash, "abcdef0123456789abcdef0123456789abcdef01")
    }

    @MainActor
    func testStoreRefreshesVersionsAndPlansInstallFromFetchedMetadata() async throws {
        let metadataURL = URL(string: "https://example.com/metadata.json")!
        let assetIndexURL = URL(string: "https://piston-meta.mojang.com/v1/packages/assets.json")!
        let version = MinecraftVersion(
            id: "1.21.5",
            type: .release,
            metadataURL: metadataURL,
            releaseTime: Date(timeIntervalSince1970: 1_700_000_000),
            recommendedJavaMajorVersion: 21
        )
        let versionService = StubVersionService(
            manifest: VersionManifest(latest: .init(release: "1.21.5", snapshot: "25w21a"), versions: [version]),
            metadata: try VersionManifestService().decodeVersionMetadata(from: Data(Self.versionMetadataJSON.utf8)),
            assetIndex: try VersionManifestService().decodeAssetIndex(from: Data(Self.assetIndexJSON.utf8)),
            expectedAssetIndexURL: assetIndexURL
        )
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: URL(fileURLWithPath: "/Users/example/Instances/vanilla", isDirectory: true),
            status: .notInstalled
        )
        let store = LauncherStore(
            instances: [instance],
            downloadJobs: [],
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: [],
            versionService: versionService
        )

        await store.refreshAvailableVersions()
        await store.planVanillaInstallFromRemoteMetadata(for: instance)

        XCTAssertEqual(store.availableVersions.map(\.id), ["1.21.5"])
        XCTAssertEqual(store.downloadJobs.first?.title, "Minecraft 1.21.5 客户端")
        XCTAssertEqual(store.downloadJobs.count, 3)
        XCTAssertEqual(store.downloadJobs[1].title, "Minecraft 1.21.5 资源索引")
        XCTAssertEqual(store.downloadJobs[2].title, "资源文件 minecraft/sounds/random/pop.ogg")
        XCTAssertEqual(store.downloadJobs.first?.sha1, "client-sha1")
        XCTAssertEqual(store.diagnostics.first?.title, "已生成 Vanilla 安装计划")
        XCTAssertTrue(store.diagnostics.first?.summary.contains("3 个下载任务") == true)
    }

    private struct StubVersionService: VersionManifestServicing {
        var manifestURL: URL = URL(string: "https://example.com/manifest.json")!
        let manifest: VersionManifest
        let metadata: VersionMetadata
        let assetIndex: AssetIndex
        let expectedAssetIndexURL: URL

        func decodeManifest(from data: Data) throws -> VersionManifest {
            manifest
        }

        func decodeVersionMetadata(from data: Data) throws -> VersionMetadata {
            metadata
        }

        func decodeAssetIndex(from data: Data) throws -> AssetIndex {
            assetIndex
        }

        func fetchManifest(from url: URL?) async throws -> VersionManifest {
            manifest
        }

        func fetchVersionMetadata(from url: URL) async throws -> VersionMetadata {
            metadata
        }

        func fetchAssetIndex(from url: URL) async throws -> AssetIndex {
            XCTAssertEqual(url, expectedAssetIndexURL)
            return assetIndex
        }
    }

    private static let manifestJSON = """
    {
      "latest": { "release": "1.21.5", "snapshot": "25w21a" },
      "versions": [
        {
          "id": "1.21.5",
          "type": "release",
          "url": "https://example.com/metadata.json",
          "time": "2026-05-20T10:00:00+00:00",
          "releaseTime": "2026-05-20T10:00:00+00:00"
        }
      ]
    }
    """

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
          "size": 42
        }
      }
    }
    """
}
