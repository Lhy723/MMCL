import Foundation
import XCTest
@testable import MMCL

@MainActor
final class AppUpdateServiceTests: XCTestCase {
    func testFetchLatestReleaseRejectsNonSuccessfulHTTPStatus() async {
        let service = AppUpdateService(dataLoader: { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        })

        do {
            _ = try await service.fetchLatestRelease()
            XCTFail("Expected HTTP failure")
        } catch let error as AppUpdateError {
            XCTAssertEqual(error, .httpStatus(503))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchLatestReleaseSelectsMMCLZipForAutomaticUpdate() async throws {
        let service = AppUpdateService(dataLoader: { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(Self.releaseJSON.utf8), response)
        }, architectureProvider: { .arm64 })

        let release = try await service.fetchLatestRelease()

        XCTAssertEqual(release.version, SemanticVersion("0.1.1"))
        XCTAssertEqual(release.automaticAsset?.name, "MMCL-v0.1.1-arm64.zip")
        XCTAssertEqual(release.manualAsset?.name, "MMCL-v0.1.1-arm64.dmg")
        XCTAssertEqual(release.notes, "修复更新流程")
    }

    func testFetchLatestReleaseSelectsIntelAssetOnX86Architecture() async throws {
        let service = AppUpdateService(dataLoader: { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(Self.releaseJSON.utf8), response)
        }, architectureProvider: { .x86_64 })

        let release = try await service.fetchLatestRelease()

        XCTAssertEqual(release.targetArchitecture, .x86_64)
        XCTAssertEqual(release.automaticAsset?.name, "MMCL-v0.1.1-x86_64.zip")
        XCTAssertEqual(release.manualAsset?.name, "MMCL-v0.1.1-x86_64.dmg")
    }

    func testReleaseDoesNotSelectTheOppositeArchitecture() {
        let release = AppUpdateRelease(
            tagName: "v0.1.1",
            version: SemanticVersion("0.1.1")!,
            title: "v0.1.1",
            notes: "",
            htmlURL: nil,
            assets: [
                AppUpdateAsset(
                    name: "MMCL-v0.1.1-x86_64.zip",
                    browserDownloadURL: URL(string: "https://example.com/MMCL-v0.1.1-x86_64.zip")!,
                    contentType: "application/zip",
                    size: 1,
                    digest: nil
                )
            ],
            targetArchitecture: .arm64
        )

        XCTAssertNil(release.automaticAsset)
    }

    func testInstallUpdateValidatesBundleAndSchedulesReplacementAndRestart() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let currentApplication = root.appendingPathComponent("MMCL.app", isDirectory: true)
        let extractedApplication = root.appendingPathComponent("downloaded/MMCL.app", isDirectory: true)
        try Self.makeTestApplication(at: currentApplication, version: "0.1.0")
        try Self.makeTestApplication(at: extractedApplication, version: "0.1.1")

        let archiveURL = root.appendingPathComponent("MMCL-v0.1.1.zip")
        try Data("archive".utf8).write(to: archiveURL)
        let release = AppUpdateRelease(
            tagName: "v0.1.1",
            version: SemanticVersion("0.1.1")!,
            title: "v0.1.1",
            notes: "",
            htmlURL: nil,
            assets: [
                AppUpdateAsset(
                    name: "MMCL-v0.1.1.zip",
                    browserDownloadURL: URL(string: "https://example.com/MMCL-v0.1.1.zip")!,
                    contentType: "application/zip",
                    size: 7,
                    digest: nil
                )
            ]
        )

        var launchedScript: URL?
        var launchedArguments: [String] = []
        var didTerminate = false
        let service = AppUpdateService(
            downloadLoader: { request in
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (archiveURL, response)
            },
            archiveExtractor: { _, destination in
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                try fileManager.copyItem(
                    at: extractedApplication,
                    to: destination.appendingPathComponent("MMCL.app", isDirectory: true)
                )
            },
            processLauncher: { scriptURL, arguments in
                launchedScript = scriptURL
                launchedArguments = arguments
            },
            currentApplicationURLProvider: { currentApplication },
            applicationTerminator: {
                didTerminate = true
            }
        )

        try await service.installUpdate(release)

        XCTAssertTrue(didTerminate)
        XCTAssertNotNil(launchedScript)
        XCTAssertEqual(launchedArguments.first, currentApplication.path)
        XCTAssertEqual(launchedArguments.count, 6)
        XCTAssertTrue(fileManager.fileExists(atPath: launchedArguments[1]))
        XCTAssertTrue(fileManager.fileExists(atPath: launchedArguments[4]))
        XCTAssertTrue(fileManager.fileExists(atPath: launchedArguments[5]))

        let replacementBundle = Bundle(url: URL(fileURLWithPath: launchedArguments[1]))
        XCTAssertEqual(replacementBundle?.bundleIdentifier, "melody.MMCL")
        XCTAssertEqual(
            replacementBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            "0.1.1"
        )

        if let launchedScript {
            try? fileManager.removeItem(at: launchedScript.deletingLastPathComponent())
        }
    }

    private static func makeTestApplication(at url: URL, version: String) throws {
        let fileManager = FileManager.default
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        try fileManager.createDirectory(at: macOS, withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleIdentifier": "melody.MMCL",
            "CFBundleExecutable": "MMCL",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": version
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))

        let executable = macOS.appendingPathComponent("MMCL")
        try Data("executable".utf8).write(to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    private static let releaseJSON = """
    {
      "tag_name": "v0.1.1",
      "name": "v0.1.1",
      "body": "修复更新流程",
      "html_url": "https://github.com/Lhy723/MMCL/releases/tag/v0.1.1",
      "draft": false,
      "prerelease": false,
      "assets": [
        {
          "name": "Source code (zip)",
          "browser_download_url": "https://example.com/source.zip",
          "content_type": "application/zip",
          "size": 10
        },
        {
          "name": "MMCL-v0.1.1.dmg",
          "browser_download_url": "https://example.com/MMCL-v0.1.1.dmg",
          "content_type": "application/x-apple-diskimage",
          "size": 20
        },
        {
          "name": "MMCL-v0.1.1-arm64.dmg",
          "browser_download_url": "https://example.com/MMCL-v0.1.1-arm64.dmg",
          "content_type": "application/x-apple-diskimage",
          "size": 21
        },
        {
          "name": "MMCL-v0.1.1-x86_64.dmg",
          "browser_download_url": "https://example.com/MMCL-v0.1.1-x86_64.dmg",
          "content_type": "application/x-apple-diskimage",
          "size": 22
        },
        {
          "name": "MMCL-v0.1.1-arm64.zip",
          "browser_download_url": "https://example.com/MMCL-v0.1.1-arm64.zip",
          "content_type": "application/zip",
          "size": 31
        },
        {
          "name": "MMCL-v0.1.1-x86_64.zip",
          "browser_download_url": "https://example.com/MMCL-v0.1.1-x86_64.zip",
          "content_type": "application/zip",
          "size": 32
        },
        {
          "name": "MMCL-v0.1.1.zip",
          "browser_download_url": "https://example.com/MMCL-v0.1.1.zip",
          "content_type": "application/zip",
          "size": 30
        }
      ]
    }
    """
}
