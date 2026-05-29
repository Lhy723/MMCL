import Combine
import Foundation
import SwiftUI

enum GameLoader: String, Codable, CaseIterable, Identifiable {
    case vanilla = "Vanilla"
    case fabric = "Fabric"
    case quilt = "Quilt"
    case forge = "Forge"

    var id: String { rawValue }
}

enum VersionIsolation: String, Codable, CaseIterable, Identifiable {
    case off = "关闭"
    case moddableVersions = "隔离可安装 Mod 的版本"
    case snapshots = "隔离非正式版"
    case moddableAndSnapshots = "隔离可安装 Mod 的版本与非正式版"
    case all = "隔离所有版本"

    var id: String { rawValue }

    var helpText: String {
        switch self {
        case .off: return "所有版本共享存档、Mod、资源包"
        case .moddableVersions: return "Forge/Fabric 等互相独立，原版共享"
        case .snapshots: return "快照与发布版、远古版本等隔离"
        case .moddableAndSnapshots: return "同时隔离可安装 Mod 版本与非正式版"
        case .all: return "不同版本的存档、Mod、资源包均不互通"
        }
    }
}

enum LauncherVisibility: String, Codable, CaseIterable, Identifiable {
    case closeAfterLaunch = "游戏启动后立即关闭"
    case hideAndClose = "游戏启动后隐藏，退出后自动关闭"
    case hideAndReopen = "游戏启动后隐藏，退出后重新打开"
    case minimize = "游戏启动后最小化"
    case keep = "游戏启动后仍保持不变"

    var id: String { rawValue }
}

enum DownloadTabType: String, CaseIterable, Identifiable {
    case vanilla = "原版游戏"
    case mod = "Mod"
    case modpack = "整合包"
    case dataPack = "数据包"
    case resourcePack = "资源包"
    case shader = "光影包"
    case progress = "下载进度"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .vanilla: return "cube.box"
        case .mod: return "puzzlepiece.extension"
        case .modpack: return "shippingbox"
        case .dataPack: return "doc.text"
        case .resourcePack: return "photo.stack"
        case .shader: return "sparkles"
        case .progress: return "chart.line.uptrend.xyaxis"
        }
    }
}

enum WindowSizeMode: String, Codable, CaseIterable, Identifiable {
    case fullscreen = "全屏"
    case `default` = "默认"
    case launcherSized = "与启动器窗口一致"
    case custom = "自定义"
    case maximized = "最大化"

    var id: String { rawValue }
}

enum FileDownloadSourceMode: String, Codable, CaseIterable, Identifiable {
    case preferMirror = "镜像源优先"
    case officialWithFallback = "官方源优先（默认，切镜像）"
    case preferOfficial = "官方源优先"

    var id: String { rawValue }
}

enum VersionListSourceMode: String, Codable, CaseIterable, Identifiable {
    case preferMirror = "镜像源优先"
    case officialWithFallback = "官方源优先（默认，切镜像）"
    case preferOfficial = "官方源优先"

    var id: String { rawValue }
}

enum CommunitySourceMode: String, Codable, CaseIterable, Identifiable {
    case preferMirror = "镜像源优先"
    case officialWithFallback = "仅官方慢时切镜像"
    case preferOfficial = "官方源优先（默认）"

    var id: String { rawValue }
}

enum FilenameFormat: String, Codable, CaseIterable, Identifiable {
    case bracketCN = "【译名】"
    case bracketEN = "[译名]（默认）"
    case suffixDash = "译名-"
    case prefixDash = "-译名"
    case noTranslation = "不翻译"

    var id: String { rawValue }
}

enum ModListDisplayStyle: String, Codable, CaseIterable, Identifiable {
    case titleTranslationDetailFilename = "标题显示译名，详情显示文件名"
    case titleFilenameDetailTranslation = "标题显示文件名，详情显示译名"

    var id: String { rawValue }
}

enum ProcessPriority: String, Codable, CaseIterable, Identifiable {
    case high = "高 — 优先保证游戏运行，性能更佳，但可能造成其他程序卡顿"
    case normal = "中 — 平衡"
    case low = "低 — 优先保证其他程序运行，适合挂机"

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
    var resolutionWidth: Int
    var resolutionHeight: Int

    static let `default` = LaunchProfile(
        offlineUsername: "Steve",
        memoryMegabytes: 4096,
        jvmArguments: ["-XX:+UseG1GC", "-XX:+UnlockExperimentalVMOptions"],
        resolutionWidth: 854,
        resolutionHeight: 480
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

    var blockIcon: String {
        switch loader {
        case .forge: return "Anvil"
        case .fabric: return "Fabric"
        case .quilt: return "Egg"
        case .vanilla:
            if gameVersion.contains("w") || gameVersion.contains("-pre") || gameVersion.contains("rc") {
                return "CommandBlock"
            }
            if gameVersion.contains("Alpha") || gameVersion.contains("Beta") {
                return "CobbleStone"
            }
            return "Grass"
        }
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
            struct OperatingSystem: Codable, Equatable {
                var name: String?
            }

            var action: String
            var os: OperatingSystem?
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

            var result = false
            for rule in rules {
                var ruleMatches = true

                if let os = rule.os, let osName = os.name {
                    if osName == "unknown" {
                        // "unknown" OS: always matches (no exclusion)
                    } else if osName == operatingSystem {
                        // Matches target OS
                    } else {
                        ruleMatches = false
                    }
                }

                if let features = rule.features, !features.isEmpty {
                    // PCL: skip quick_play features entirely
                    if features.keys.contains(where: { $0.contains("quick_play") }) {
                        ruleMatches = false
                    }
                    // PCL: skip is_demo_user features
                    if features["is_demo_user"] == true {
                        ruleMatches = false
                    }
                }

                if ruleMatches {
                    result = (rule.action == "allow")
                }
            }
            return result
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
            var classifiers: [String: Artifact]?
        }

        struct Artifact: Codable, Equatable {
            var path: String
            var url: URL
            var sha1: String
            var size: Int64
        }

        var name: String
        var natives: [String: String]?
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
    case paused
    case completed
    case failed

    var label: String {
        switch self {
        case .queued: return "等待中"
        case .running: return "下载中"
        case .paused: return "已暂停"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }

    var isActive: Bool {
        self == .queued || self == .running || self == .paused
    }
}

struct DownloadJob: Identifiable, Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case id, title, source, remoteURL, destination, sha1
        case totalBytes, completedBytes, bytesPerSecond, status
        case taskGroupID, taskGroupName
    }

    var id: UUID
    var title: String
    var source: DownloadSource
    var remoteURL: URL?
    var destination: URL
    var sha1: String?
    var totalBytes: Int64
    var completedBytes: Int64
    var bytesPerSecond: Int64
    var status: DownloadStatus
    var taskGroupID: UUID?
    var taskGroupName: String?

    /// Resume data for paused downloads (not persisted)
    var resumeData: Data?

    init(
        id: UUID = UUID(),
        title: String,
        source: DownloadSource,
        remoteURL: URL? = nil,
        destination: URL,
        sha1: String? = nil,
        totalBytes: Int64,
        completedBytes: Int64 = 0,
        bytesPerSecond: Int64 = 0,
        status: DownloadStatus = .queued,
        taskGroupID: UUID? = nil,
        taskGroupName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.remoteURL = remoteURL
        self.destination = destination
        self.sha1 = sha1
        self.totalBytes = totalBytes
        self.completedBytes = completedBytes
        self.bytesPerSecond = bytesPerSecond
        self.status = status
        self.taskGroupID = taskGroupID
        self.taskGroupName = taskGroupName
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

struct DownloadTaskGroup: Identifiable {
    let id: UUID
    let name: String
    var jobs: [DownloadJob]

    var totalBytes: Int64 { jobs.reduce(0) { $0 + $1.totalBytes } }
    var completedBytes: Int64 { jobs.reduce(0) { $0 + $1.completedBytes } }
    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(Double(completedBytes) / Double(totalBytes), 1)
    }

    var status: DownloadStatus {
        if jobs.contains(where: { $0.status == .failed }) { return .failed }
        if jobs.allSatisfy({ $0.status == .completed }) { return .completed }
        if jobs.contains(where: { $0.status == .running }) { return .running }
        if jobs.contains(where: { $0.status == .paused }) { return .paused }
        return .queued
    }

    var currentFileName: String? {
        jobs.first(where: { $0.status == .running })?.title
    }

    var completedCount: Int { jobs.filter { $0.status == .completed }.count }
    var failedCount: Int { jobs.filter { $0.status == .failed }.count }
}

struct ModInfo: Identifiable, Equatable {
    var id: String { fileName }
    var fileName: String
    var isEnabled: Bool
    var size: Int64
}

struct ResourcePackInfo: Identifiable, Equatable {
    var id: String { fileName }
    var fileName: String
    var isEnabled: Bool
    var size: Int64
}

struct ShaderPackInfo: Identifiable, Equatable {
    var id: String { fileName }
    var fileName: String
    var isEnabled: Bool
    var size: Int64
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

enum DiagnosticSeverity: String, Codable, CaseIterable, Identifiable {
    case info
    case warning
    case error

    var id: String { rawValue }

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

struct NeoForgeVersion: Codable, Identifiable, Equatable {
    var id: String { version }
    var version: String
    var neoForgeVersion: String

    enum CodingKeys: String, CodingKey {
        case version
        case neoForgeVersion = "neo_version"
    }
}

struct CurseForgeSearchResult: Codable, Identifiable, Equatable {
    var id: Int
    var name: String
    var summary: String
    var downloadCount: Int
    var websiteUrl: String

    enum CodingKeys: String, CodingKey {
        case id, name, summary
        case downloadCount
        case websiteUrl
    }
}

struct CurseForgeSearchResponse: Codable, Equatable {
    var data: [CurseForgeSearchResult]
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
    var displayCategories: [String]?
    var color: Int?
    var author: String?
    var dateModified: String?

    var iconURLResolved: URL? {
        guard let iconURL, let url = URL(string: iconURL) else { return nil }
        return url
    }

    var tintColor: Color? {
        guard let color else { return nil }
        let r = Double((color >> 16) & 0xFF) / 255.0
        let g = Double((color >> 8) & 0xFF) / 255.0
        let b = Double(color & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    var formattedDate: String? {
        guard let dateModified else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateModified) ?? ISO8601DateFormatter().date(from: dateModified) else { return nil }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        return relative.localizedString(for: date, relativeTo: Date())
    }

    var displayTags: [String] {
        (displayCategories ?? categories).prefix(3).map { $0 }
    }

    enum CodingKeys: String, CodingKey {
        case id = "project_id"
        case slug, title, description
        case projectType = "project_type"
        case downloads
        case iconURL = "icon_url"
        case categories
        case displayCategories = "display_categories"
        case color, author
        case dateModified = "date_modified"
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

struct SkinInfo: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var model: SkinModel
    var localFileURL: URL?
    var remoteURL: URL?
    var isApplied: Bool = false

    enum SkinModel: String, Codable, CaseIterable {
        case steve = "Steve"
        case alex = "Alex"

        var label: String { rawValue }
    }
}

struct MinecraftAccount: Codable, Equatable, Identifiable {
    var id: UUID
    var username: String
    var uuid: String
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var type: AccountType
    var appliedSkin: SkinInfo?

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

    init(id: UUID = UUID(), username: String, uuid: String = "", accessToken: String = "", refreshToken: String = "", expiresAt: Date = Date(), type: AccountType = .offline, appliedSkin: SkinInfo? = nil) {
        self.id = id
        self.username = username
        self.uuid = uuid
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.type = type
        self.appliedSkin = appliedSkin
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

final class DownloadSpeedTracker: ObservableObject {
    @Published var bytesPerSecond: Int64 = 0
    private var totalBytes: Int64 = 0
    private var startTime: Date?

    func addBytes(_ bytes: Int64) {
        if startTime == nil { startTime = Date() }
        totalBytes += bytes
        guard let start = startTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        if elapsed > 0 {
            bytesPerSecond = Int64(Double(totalBytes) / elapsed)
        }
    }

    func reset() {
        totalBytes = 0
        startTime = nil
        bytesPerSecond = 0
    }
}

enum AppColorScheme: String, CaseIterable, Codable, Identifiable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"

    var id: String { rawValue }

    var swiftUIScheme: SwiftUI.ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case chinese = "中文"
    case english = "English"

    var id: String { rawValue }
}

struct JVMPreset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var arguments: [String]
    var isEnabled: Bool

    static let defaults = [
        JVMPreset(id: UUID(), name: "自动（推荐）", arguments: [], isEnabled: true),
        JVMPreset(id: UUID(), name: "Apple Silicon 优化", arguments: ["-XX:+UseZGC", "-XX:+ZGenerational", "-XX:+UnlockExperimentalVMOptions", "-XX:G1HeapRegionSize=16M"], isEnabled: false),
        JVMPreset(id: UUID(), name: "G1GC", arguments: ["-XX:+UseG1GC", "-XX:+UnlockExperimentalVMOptions"], isEnabled: false),
        JVMPreset(id: UUID(), name: "ZGC（低延迟）", arguments: ["-XX:+UseZGC", "-XX:+ZGenerational"], isEnabled: false),
        JVMPreset(id: UUID(), name: "大内存", arguments: ["-XX:+UseG1GC", "-XX:MaxGCPauseMillis=20", "-XX:+UnlockExperimentalVMOptions", "-XX:G1NewSizePercent=30", "-XX:G1MaxNewSizePercent=40"], isEnabled: false)
    ]
}

// MARK: - Server List

struct ServerInfo: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var address: String
    var port: Int = 25565
    var isFavorite: Bool = false
    var lastPingedAt: Date?
    var pingResult: ServerPingResult?

    var fullAddress: String {
        if port == 25565 { return address }
        return "\(address):\(port)"
    }

    struct ServerPingResult: Codable, Equatable {
        var motd: String
        var playerCount: Int
        var maxPlayers: Int
        var versionName: String
        var pingMs: Int
        var iconData: Data?
    }
}

// MARK: - Profile Import/Export

struct ProfileExportData: Codable {
    var version: String = "1.0"
    var exportDate: Date = Date()
    var instances: [LauncherInstance]
    var accounts: [MinecraftAccount]
    var settings: ProfileExportSettings
}

struct ProfileExportSettings: Codable {
    var defaultMemoryMegabytes: Int
    var defaultOfflineUsername: String
    var preferredDownloadSource: DownloadSource
    var defaultResolutionWidth: Int
    var defaultResolutionHeight: Int
    var jvmPresets: [JVMPreset]
}

// MARK: - Custom Background

struct BackgroundImage: Equatable {
    var url: URL?
    var opacity: Double = 0.3
    var blurRadius: CGFloat = 0
}
