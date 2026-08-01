import AppKit
import CryptoKit
import Foundation

struct AppUpdateAsset: Equatable {
    let name: String
    let browserDownloadURL: URL
    let contentType: String?
    let size: Int64?
    let digest: String?

    var isZipArchive: Bool {
        name.lowercased().hasSuffix(".zip") && !name.lowercased().contains("source code")
    }

    var isDiskImage: Bool {
        name.lowercased().hasSuffix(".dmg")
    }
}

struct AppUpdateRelease: Equatable {
    let tagName: String
    let version: SemanticVersion
    let title: String
    let notes: String
    let htmlURL: URL?
    let assets: [AppUpdateAsset]

    var automaticAsset: AppUpdateAsset? {
        assets
            .filter(\.isZipArchive)
            .sorted { Self.assetScore($0) > Self.assetScore($1) }
            .first
    }

    var manualAsset: AppUpdateAsset? {
        assets.first(where: \.isDiskImage)
    }

    private static func assetScore(_ asset: AppUpdateAsset) -> Int {
        let normalizedName = asset.name.lowercased()
        var score = 0
        if normalizedName.contains("mmcl") { score += 100 }
        if normalizedName.contains("mac") { score += 10 }
        if normalizedName.contains("universal") { score += 5 }
        return score
    }
}

enum AppUpdateError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case invalidReleasePayload
    case noAutomaticAsset
    case checksumMismatch
    case archiveExtractionFailed(String)
    case applicationNotFound
    case invalidApplication(String)
    case currentApplicationUnavailable
    case replacementFailed(String)
    case restartFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub 返回了无效的网络响应。"
        case .httpStatus(let status):
            return "GitHub 更新服务返回 HTTP \(status)。"
        case .invalidReleasePayload:
            return "GitHub Release 信息缺少有效版本号或下载地址。"
        case .noAutomaticAsset:
            return "该 Release 没有可用于自动更新的 MMCL ZIP 文件。"
        case .checksumMismatch:
            return "更新包校验失败，文件可能已损坏或被篡改。"
        case .archiveExtractionFailed(let details):
            return details.isEmpty ? "更新包解压失败。" : "更新包解压失败：\(details)"
        case .applicationNotFound:
            return "更新包中没有找到 MMCL.app。"
        case .invalidApplication(let reason):
            return "更新包中的应用无效：\(reason)"
        case .currentApplicationUnavailable:
            return "无法定位当前运行的 MMCL.app。"
        case .replacementFailed(let reason):
            return "无法准备应用替换：\(reason)"
        case .restartFailed(let reason):
            return "无法启动自动重启：\(reason)"
        }
    }
}

protocol AppUpdateServicing {
    func fetchLatestRelease() async throws -> AppUpdateRelease
    func installUpdate(_ release: AppUpdateRelease) async throws
}

final class AppUpdateService: AppUpdateServicing {
    typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)
    typealias DownloadLoader = (URLRequest) async throws -> (URL, URLResponse)
    typealias ArchiveExtractor = (URL, URL) throws -> Void
    typealias ProcessLauncher = (URL, [String]) throws -> Void
    typealias CurrentApplicationURLProvider = () -> URL
    typealias ApplicationTerminator = @MainActor () -> Void

    static let latestReleaseURL = URL(string: "https://api.github.com/repos/Lhy723/MMCL/releases/latest")!
    private static let applicationBundleIdentifier = "melody.MMCL"

    private let dataLoader: DataLoader
    private let downloadLoader: DownloadLoader
    private let archiveExtractor: ArchiveExtractor
    private let processLauncher: ProcessLauncher
    private let currentApplicationURLProvider: CurrentApplicationURLProvider
    private let applicationTerminator: ApplicationTerminator

    init(
        dataLoader: @escaping DataLoader = { request in
            try await URLSession.shared.data(for: request)
        },
        downloadLoader: @escaping DownloadLoader = { request in
            try await URLSession.shared.download(for: request)
        },
        archiveExtractor: @escaping ArchiveExtractor = AppUpdateService.extractArchive,
        processLauncher: @escaping ProcessLauncher = AppUpdateService.launchUpdater,
        currentApplicationURLProvider: @escaping CurrentApplicationURLProvider = { Bundle.main.bundleURL },
        applicationTerminator: @escaping ApplicationTerminator = {
            NSApplication.shared.terminate(nil)
        }
    ) {
        self.dataLoader = dataLoader
        self.downloadLoader = downloadLoader
        self.archiveExtractor = archiveExtractor
        self.processLauncher = processLauncher
        self.currentApplicationURLProvider = currentApplicationURLProvider
        self.applicationTerminator = applicationTerminator
    }

    func fetchLatestRelease() async throws -> AppUpdateRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MMCL", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await dataLoader(request)
        try Self.validateHTTPResponse(response)

        do {
            let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
            guard !payload.draft, !payload.prerelease,
                  let version = SemanticVersion(payload.tagName) else {
                throw AppUpdateError.invalidReleasePayload
            }

            let assets = payload.assets.compactMap { asset -> AppUpdateAsset? in
                guard let url = URL(string: asset.browserDownloadURL) else { return nil }
                return AppUpdateAsset(
                    name: asset.name,
                    browserDownloadURL: url,
                    contentType: asset.contentType,
                    size: asset.size,
                    digest: asset.digest
                )
            }
            guard !assets.isEmpty else { throw AppUpdateError.invalidReleasePayload }

            return AppUpdateRelease(
                tagName: payload.tagName,
                version: version,
                title: payload.name ?? payload.tagName,
                notes: payload.body ?? "",
                htmlURL: payload.htmlURL.flatMap(URL.init(string:)),
                assets: assets
            )
        } catch let error as AppUpdateError {
            throw error
        } catch {
            throw AppUpdateError.invalidReleasePayload
        }
    }

    func installUpdate(_ release: AppUpdateRelease) async throws {
        guard let asset = release.automaticAsset else {
            throw AppUpdateError.noAutomaticAsset
        }

        var request = URLRequest(url: asset.browserDownloadURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("MMCL", forHTTPHeaderField: "User-Agent")
        let (downloadedURL, response) = try await downloadLoader(request)
        try Self.validateHTTPResponse(response)

        let fileManager = FileManager.default
        let updateID = UUID().uuidString
        let workingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MMCL-update-\(updateID)", isDirectory: true)
        let archiveURL = workingDirectory.appendingPathComponent(asset.name)
        let extractionDirectory = workingDirectory.appendingPathComponent("extracted", isDirectory: true)
        var replacementURL: URL?
        var restartScheduled = false

        defer {
            if !restartScheduled {
                if let replacementURL {
                    try? fileManager.removeItem(at: replacementURL)
                }
                try? fileManager.removeItem(at: workingDirectory)
            }
        }

        do {
            try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: downloadedURL, to: archiveURL)
            try verifyDigest(of: archiveURL, expected: asset.digest)
            try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
            try archiveExtractor(archiveURL, extractionDirectory)
        } catch let error as AppUpdateError {
            throw error
        } catch {
            throw AppUpdateError.archiveExtractionFailed(error.localizedDescription)
        }

        guard let extractedApplication = findApplication(in: extractionDirectory) else {
            throw AppUpdateError.applicationNotFound
        }
        try validateApplication(extractedApplication, expectedVersion: release.version)

        let currentApplicationURL = currentApplicationURLProvider().resolvingSymlinksInPath()
        guard currentApplicationURL.pathExtension.lowercased() == "app",
              fileManager.fileExists(atPath: currentApplicationURL.path) else {
            throw AppUpdateError.currentApplicationUnavailable
        }

        let applicationDirectory = currentApplicationURL.deletingLastPathComponent()
        let replacement = applicationDirectory
            .appendingPathComponent(".MMCL-update-\(updateID).app", isDirectory: true)
        do {
            try fileManager.copyItem(at: extractedApplication, to: replacement)
            replacementURL = replacement
        } catch {
            throw AppUpdateError.replacementFailed(error.localizedDescription)
        }

        let backup = applicationDirectory
            .appendingPathComponent(".MMCL-backup-\(updateID).app", isDirectory: true)
        let scriptURL = workingDirectory.appendingPathComponent("restart.sh")
        do {
            try Self.restartScript.data(using: .utf8)?.write(to: scriptURL, options: .atomic)
            try processLauncher(
                scriptURL,
                [
                    currentApplicationURL.path,
                    replacement.path,
                    String(ProcessInfo.processInfo.processIdentifier),
                    backup.path,
                    scriptURL.path,
                    workingDirectory.path
                ]
            )
        } catch {
            throw AppUpdateError.restartFailed(error.localizedDescription)
        }

        restartScheduled = true
        applicationTerminator()
    }

    private func verifyDigest(of fileURL: URL, expected digest: String?) throws {
        guard let digest,
              let expected = digest.split(separator: ":", maxSplits: 1).last,
              digest.lowercased().hasPrefix("sha256:") else {
            return
        }

        let data = try Data(contentsOf: fileURL)
        let actual = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actual.caseInsensitiveCompare(String(expected)) == .orderedSame else {
            throw AppUpdateError.checksumMismatch
        }
    }

    private func findApplication(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "app",
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            return url
        }
        return nil
    }

    private func validateApplication(_ applicationURL: URL, expectedVersion: SemanticVersion) throws {
        guard let bundle = Bundle(url: applicationURL) else {
            throw AppUpdateError.invalidApplication("无法读取应用包信息")
        }
        guard bundle.bundleIdentifier == Self.applicationBundleIdentifier else {
            throw AppUpdateError.invalidApplication("Bundle ID 不匹配")
        }
        guard let versionString = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let version = SemanticVersion(versionString), version == expectedVersion else {
            throw AppUpdateError.invalidApplication("版本号与 Release 不匹配")
        }
        guard let executableName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
              FileManager.default.isExecutableFile(
                  atPath: applicationURL.appendingPathComponent("Contents/MacOS/\(executableName)").path
              ) else {
            throw AppUpdateError.invalidApplication("缺少可执行文件")
        }
    }

    private static func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AppUpdateError.httpStatus(httpResponse.statusCode)
        }
    }

    private nonisolated static func extractArchive(archiveURL: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, destination.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let details = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw AppUpdateError.archiveExtractionFailed(details)
        }
    }

    private nonisolated static func launchUpdater(scriptURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path] + arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static let restartScript = """
    #!/bin/sh
    set -eu

    old_app="$1"
    replacement_app="$2"
    process_id="$3"
    backup_app="$4"
    script_path="$5"
    cleanup_directory="$6"

    while kill -0 "$process_id" 2>/dev/null; do
        sleep 0.2
    done

    if [ -e "$old_app" ]; then
        mv "$old_app" "$backup_app"
    fi

    if ! mv "$replacement_app" "$old_app"; then
        if [ -e "$backup_app" ]; then
            mv "$backup_app" "$old_app" || true
        fi
        rm -rf "$cleanup_directory"
        exit 1
    fi

    if ! open -n "$old_app"; then
        rm -rf "$old_app"
        if [ -e "$backup_app" ]; then
            mv "$backup_app" "$old_app" || true
        fi
        rm -rf "$cleanup_directory"
        exit 1
    fi

    rm -rf "$backup_app"
    rm -rf "$cleanup_directory"
    """
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAssetPayload]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

private struct GitHubReleaseAssetPayload: Decodable {
    let name: String
    let browserDownloadURL: String
    let contentType: String?
    let size: Int64?
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case contentType = "content_type"
        case size
        case digest
    }
}
