import Foundation

enum GameLoader: String, Codable, CaseIterable, Identifiable {
    case vanilla = "Vanilla"
    case fabric = "Fabric"
    case quilt = "Quilt"
    case forge = "Forge"

    var id: String { rawValue }
}

enum InstanceStatus: String, Codable {
    case ready
    case missingFiles
    case needsJava
    case notInstalled

    var label: String {
        switch self {
        case .ready: return "可启动"
        case .missingFiles: return "需要修复"
        case .needsJava: return "需要 Java"
        case .notInstalled: return "未安装"
        }
    }
}

struct LaunchProfile: Codable, Equatable {
    var offlineUsername: String
    var memoryMegabytes: Int
    var jvmArguments: [String]

    static let `default` = LaunchProfile(
        offlineUsername: "Steve",
        memoryMegabytes: 4096,
        jvmArguments: ["-XX:+UseG1GC", "-XX:+UnlockExperimentalVMOptions"]
    )
}

struct LauncherInstance: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var gameVersion: String
    var loader: GameLoader
    var rootDirectory: URL
    var profile: LaunchProfile
    var status: InstanceStatus
    var lastPlayedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        gameVersion: String,
        loader: GameLoader,
        rootDirectory: URL,
        profile: LaunchProfile = .default,
        status: InstanceStatus = .notInstalled,
        lastPlayedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.gameVersion = gameVersion
        self.loader = loader
        self.rootDirectory = rootDirectory
        self.profile = profile
        self.status = status
        self.lastPlayedAt = lastPlayedAt
    }

    var subtitle: String {
        "\(gameVersion) · \(loader.rawValue)"
    }
}

struct MinecraftVersion: Identifiable, Codable, Equatable {
    enum ReleaseType: String, Codable {
        case release
        case snapshot
        case oldBeta = "old_beta"
        case oldAlpha = "old_alpha"

        var label: String {
            switch self {
            case .release: return "正式版"
            case .snapshot: return "快照版"
            case .oldBeta: return "Beta"
            case .oldAlpha: return "Alpha"
            }
        }
    }

    var id: String
    var type: ReleaseType
    var metadataURL: URL
    var releaseTime: Date
    var recommendedJavaMajorVersion: Int

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case metadataURL = "url"
        case releaseTime
        case recommendedJavaMajorVersion
    }

    init(
        id: String,
        type: ReleaseType,
        metadataURL: URL,
        releaseTime: Date,
        recommendedJavaMajorVersion: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.metadataURL = metadataURL
        self.releaseTime = releaseTime
        self.recommendedJavaMajorVersion = recommendedJavaMajorVersion ?? JavaRuntime.recommendedMajorVersion(for: id)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        self.id = id
        self.type = try container.decode(ReleaseType.self, forKey: .type)
        self.metadataURL = try container.decode(URL.self, forKey: .metadataURL)
        self.releaseTime = try container.decode(Date.self, forKey: .releaseTime)
        self.recommendedJavaMajorVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .recommendedJavaMajorVersion
        ) ?? JavaRuntime.recommendedMajorVersion(for: id)
    }
}

struct VersionManifest: Codable, Equatable {
    struct Latest: Codable, Equatable {
        var release: String
        var snapshot: String
    }

    var latest: Latest
    var versions: [MinecraftVersion]
}

struct VersionMetadata: Codable, Equatable {
    struct ArgumentSet: Codable, Equatable {
        var game: [LaunchArgument]
        var jvm: [LaunchArgument]
    }

    struct LaunchArgument: Codable, Equatable {
        struct Rule: Codable, Equatable {
            struct OS: Codable, Equatable {
                var name: String?
            }

            var action: String
            var os: OS?
            var features: [String: Bool]?
        }

        enum Value: Codable, Equatable {
            case string(String)
            case array([String])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let string = try? container.decode(String.self) {
                    self = .string(string)
                } else {
                    self = .array(try container.decode([String].self))
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .string(let string):
                    try container.encode(string)
                case .array(let array):
                    try container.encode(array)
                }
            }

            var strings: [String] {
                switch self {
                case .string(let string): return [string]
                case .array(let array): return array
                }
            }
        }

        var value: Value
        var rules: [Rule]?

        init(value: Value, rules: [Rule]? = nil) {
            self.value = value
            self.rules = rules
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self.value = .string(string)
                self.rules = nil
            } else {
                let keyed = try decoder.container(keyedBy: CodingKeys.self)
                self.value = try keyed.decode(Value.self, forKey: .value)
                self.rules = try keyed.decodeIfPresent([Rule].self, forKey: .rules)
            }
        }

        func applies(to operatingSystem: String) -> Bool {
            guard let rules, !rules.isEmpty else { return true }
            return rules.reduce(false) { current, rule in
                let matchesOS = rule.os?.name.map { $0 == operatingSystem } ?? true
                guard matchesOS else { return current }
                return rule.action == "allow"
            }
        }
    }

    struct Download: Codable, Equatable {
        var url: URL
        var sha1: String
        var size: Int64
    }

    struct Downloads: Codable, Equatable {
        var client: Download
    }

    struct AssetIndex: Codable, Equatable {
        var id: String
        var url: URL
        var sha1: String
        var size: Int64
    }

    struct Library: Codable, Equatable, Identifiable {
        struct Downloads: Codable, Equatable {
            var artifact: Artifact?
            var classifiers: [String: Artifact]? = nil
        }

        struct Artifact: Codable, Equatable {
            var path: String
            var url: URL
            var sha1: String
            var size: Int64
        }

        var name: String
        var natives: [String: String]? = nil
        var downloads: Downloads?

        var id: String { name }
        var artifact: Artifact? { downloads?.artifact }

        func nativeArtifact(for operatingSystem: String = "osx") -> Artifact? {
            guard let classifier = natives?[operatingSystem] else { return nil }
            return downloads?.classifiers?[classifier]
        }
    }

    var id: String
    var mainClass: String
    var assets: String
    var assetIndex: AssetIndex
    var downloads: Downloads
    var libraries: [Library]
    var arguments: ArgumentSet?
    var minecraftArguments: String?
}

struct AssetIndex: Codable, Equatable {
    struct Object: Codable, Equatable {
        var hash: String
        var size: Int64

        var pathPrefix: String {
            String(hash.prefix(2))
        }
    }

    var objects: [String: Object]

    var totalBytes: Int64 {
        objects.values.reduce(0) { $0 + $1.size }
    }
}

struct LaunchPreview: Equatable {
    var instance: LauncherInstance
    var java: JavaRuntime
    var command: [String]

    var commandLine: String {
        command.map { argument in
            if argument.contains(" ") {
                return "\"\(argument)\""
            }
            return argument
        }
        .joined(separator: " ")
    }
}

struct LaunchSession: Identifiable, Equatable {
    var id: UUID
    var processIdentifier: Int32
    var command: [String]
    var logFileURL: URL
    var startedAt: Date

    init(
        id: UUID = UUID(),
        processIdentifier: Int32,
        command: [String],
        logFileURL: URL,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.processIdentifier = processIdentifier
        self.command = command
        self.logFileURL = logFileURL
        self.startedAt = startedAt
    }

    var commandLine: String {
        command.map { argument in
            if argument.contains(" ") {
                return "\"\(argument)\""
            }
            return argument
        }
        .joined(separator: " ")
    }
}

struct LaunchPreflightReport: Equatable {
    var severity: DiagnosticSeverity
    var summary: String
    var suggestedActions: [String]

    var canLaunch: Bool {
        severity != .error
    }

    func diagnostic(title: String = "启动前检查未通过") -> DiagnosticReport {
        DiagnosticReport(
            title: title,
            severity: severity,
            summary: summary,
            suggestedActions: suggestedActions
        )
    }
}

enum RuntimeArchitecture: String, Codable {
    case arm64
    case x86_64
    case universal
    case unknown

    var label: String {
        switch self {
        case .arm64: return "Apple Silicon"
        case .x86_64: return "Intel"
        case .universal: return "通用"
        case .unknown: return "未知架构"
        }
    }
}

struct JavaRuntime: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var version: String
    var majorVersion: Int
    var architecture: RuntimeArchitecture
    var executableURL: URL

    init(
        id: UUID = UUID(),
        name: String,
        version: String,
        majorVersion: Int,
        architecture: RuntimeArchitecture,
        executableURL: URL
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.majorVersion = majorVersion
        self.architecture = architecture
        self.executableURL = executableURL
    }

    var displayName: String {
        "\(name) · Java \(majorVersion) · \(architecture.label)"
    }

    func isRecommended(for gameVersion: String) -> Bool {
        majorVersion == JavaRuntime.recommendedMajorVersion(for: gameVersion)
    }

    static func recommendedMajorVersion(for gameVersion: String) -> Int {
        let components = gameVersion.split(separator: ".").compactMap { Int($0) }
        guard components.count >= 2 else { return 17 }
        let minor = components[1]

        if minor >= 20 { return 21 }
        if minor >= 17 { return 17 }
        return 8
    }
}

enum DownloadSource: String, Codable, CaseIterable, Identifiable {
    case official = "官方源"
    case bmclapi = "BMCLAPI"
    case customMirror = "自定义镜像"

    var id: String { rawValue }
}

enum DownloadStatus: String, Codable {
    case queued
    case running
    case completed
    case failed

    var label: String {
        switch self {
        case .queued: return "等待中"
        case .running: return "下载中"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }
}

struct DownloadJob: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var source: DownloadSource
    var remoteURL: URL?
    var destination: URL
    var sha1: String?
    var totalBytes: Int64
    var completedBytes: Int64
    var status: DownloadStatus

    init(
        id: UUID = UUID(),
        title: String,
        source: DownloadSource,
        remoteURL: URL? = nil,
        destination: URL,
        sha1: String? = nil,
        totalBytes: Int64,
        completedBytes: Int64 = 0,
        status: DownloadStatus = .queued
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.remoteURL = remoteURL
        self.destination = destination
        self.sha1 = sha1
        self.totalBytes = totalBytes
        self.completedBytes = completedBytes
        self.status = status
    }

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(Double(completedBytes) / Double(totalBytes), 1)
    }

    mutating func update(completedBytes: Int64) {
        self.completedBytes = max(0, min(completedBytes, totalBytes))
        status = self.completedBytes >= totalBytes ? .completed : .running
    }
}

struct ContentProject: Identifiable, Codable, Equatable {
    enum ProjectType: String, Codable {
        case mod = "Mod"
        case modpack = "整合包"
        case resourcePack = "资源包"
        case shaderPack = "光影包"
    }

    var id: String
    var title: String
    var type: ProjectType
    var source: String
    var gameVersions: [String]
    var loaders: [GameLoader]
}

enum DiagnosticSeverity: String, Codable {
    case info
    case warning
    case error

    var localized: String {
        switch self {
        case .info: return "提示"
        case .warning: return "警告"
        case .error: return "错误"
        }
    }
}

struct DiagnosticReport: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var severity: DiagnosticSeverity
    var summary: String
    var suggestedActions: [String]

    init(
        id: UUID = UUID(),
        title: String,
        severity: DiagnosticSeverity,
        summary: String,
        suggestedActions: [String]
    ) {
        self.id = id
        self.title = title
        self.severity = severity
        self.summary = summary
        self.suggestedActions = suggestedActions
    }

    var localizedSeverity: String {
        severity.localized
    }

    var fullMessage: String {
        let actions = suggestedActions.map { "- \($0)" }.joined(separator: "\n")
        return "[\(localizedSeverity)] \(title)\n\(summary)\n\(actions)"
    }
}

struct FabricLoaderVersion: Codable, Identifiable, Equatable {
    var id: String { version }
    var version: String
    var stable: Bool
}

struct FabricProfile: Codable, Equatable {
    var id: String
    var inheritsFrom: String
    var mainClass: String
    var arguments: FabricArguments?

    struct FabricArguments: Codable, Equatable {
        var game: [String]?
        var jvm: [String]?
    }
}

struct QuiltLoaderVersion: Codable, Identifiable, Equatable {
    var id: String { version }
    var version: String
    var stable: Bool
}

struct QuiltProfile: Codable, Equatable {
    var id: String
    var inheritsFrom: String
    var mainClass: String

    struct QuiltArguments: Codable, Equatable {
        var game: [String]?
        var jvm: [String]?
    }
    var arguments: QuiltArguments?
}

struct ForgeVersion: Codable, Identifiable, Equatable {
    var id: String { version }
    var version: String
    var installerURL: String

    enum CodingKeys: String, CodingKey {
        case version
        case installerURL = "installer_url"
    }
}

struct ModrinthSearchResult: Codable, Identifiable, Equatable {
    var id: String
    var slug: String
    var title: String
    var description: String
    var projectType: String
    var downloads: Int
    var iconURL: String?
    var categories: [String]

    enum CodingKeys: String, CodingKey {
        case id, slug, title, description, projectType, downloads
        case iconURL = "icon_url"
        case categories
    }
}

struct ModrinthSearchResponse: Codable, Equatable {
    var hits: [ModrinthSearchResult]
    var totalHits: Int

    enum CodingKeys: String, CodingKey {
        case hits
        case totalHits = "total_hits"
    }
}

struct ModrinthProject: Codable, Identifiable, Equatable {
    var id: String
    var slug: String
    var title: String
    var description: String
    var projectType: String
    var body: String
    var iconURL: String?
    var downloads: Int
    var gameVersions: [String]
    var loaders: [String]

    enum CodingKeys: String, CodingKey {
        case id, slug, title, description, projectType, body, downloads
        case iconURL = "icon_url"
        case gameVersions = "game_versions"
        case loaders
    }
}

struct ModrinthVersion: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var versionNumber: String
    var gameVersions: [String]
    var loaders: [String]
    var files: [ModrinthFile]

    enum CodingKeys: String, CodingKey {
        case id, name
        case versionNumber = "version_number"
        case gameVersions = "game_versions"
        case loaders, files
    }
}

struct ModrinthFile: Codable, Equatable {
    var filename: String
    var url: String
    var size: Int64
    var primary: Bool
}

struct MinecraftAccount: Codable, Equatable, Identifiable {
    var id: UUID
    var username: String
    var uuid: String
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var type: AccountType

    enum AccountType: String, Codable {
        case offline
        case microsoft
    }

    var displayName: String {
        switch type {
        case .offline: return "\(username)（离线）"
        case .microsoft: return username
        }
    }

    init(id: UUID = UUID(), username: String, uuid: String = "", accessToken: String = "", refreshToken: String = "", expiresAt: Date = Date(), type: AccountType = .offline) {
        self.id = id
        self.username = username
        self.uuid = uuid
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.type = type
    }
}

struct DeviceCodeResponse: Codable {
    var userCode: String
    var verificationUri: String
    var expiresIn: Int
    var interval: Int
    var deviceCode: String

    enum CodingKeys: String, CodingKey {
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
        case deviceCode = "device_code"
    }
}

struct MicrosoftTokenResponse: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresInSeconds = "expires_in"
    }
}

struct XboxTokenResponse: Codable {
    var token: String
    var expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case token
        case expiresInSeconds = "expiresIn"
    }
}

struct XBLXSTSResponse: Codable {
    var token: String
    var expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case token
        case expiresInSeconds = "expiresIn"
    }
}

struct MinecraftTokenResponse: Codable {
    var accessToken: String
    var expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresInSeconds = "expires_in"
    }
}

struct MinecraftProfileResponse: Codable {
    var id: String
    var name: String
}

extension JSONEncoder {
    static var mmcl: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var mmcl: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
