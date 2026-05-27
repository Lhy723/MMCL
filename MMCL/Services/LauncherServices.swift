import CryptoKit
import Foundation

protocol InstanceServicing {
    var rootDirectory: URL { get }
    var instancesDirectory: URL { get }
    func createInstance(
        name: String,
        gameVersion: String,
        loader: GameLoader,
        profile: LaunchProfile
    ) throws -> LauncherInstance
    func instanceFileURL(for instance: LauncherInstance) -> URL
    func encode(_ instance: LauncherInstance) throws -> Data
    func decode(from data: Data) throws -> LauncherInstance
}

struct InstanceService: InstanceServicing {
    let rootDirectory: URL

    init(applicationSupportDirectory: URL? = nil) {
        let supportDirectory = applicationSupportDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        self.rootDirectory = supportDirectory.appendingPathComponent("MMCL", isDirectory: true)
    }

    var instancesDirectory: URL {
        rootDirectory.appendingPathComponent("Instances", isDirectory: true)
    }

    func createInstance(
        name: String,
        gameVersion: String,
        loader: GameLoader,
        profile: LaunchProfile
    ) throws -> LauncherInstance {
        let slug = Self.slug(for: name)
        let instanceRoot = instancesDirectory.appendingPathComponent(slug, isDirectory: true)
        let instance = LauncherInstance(
            name: name,
            gameVersion: gameVersion,
            loader: loader,
            rootDirectory: instanceRoot,
            profile: profile,
            status: .notInstalled
        )

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: instanceRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: instanceRoot.appendingPathComponent(".minecraft", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: instanceRoot.appendingPathComponent("logs", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: instanceRoot.appendingPathComponent("mods", isDirectory: true),
            withIntermediateDirectories: true
        )
        try encode(instance).write(to: instanceFileURL(for: instance), options: .atomic)

        return instance
    }

    func instanceFileURL(for instance: LauncherInstance) -> URL {
        instance.rootDirectory.appendingPathComponent("instance.json")
    }

    func encode(_ instance: LauncherInstance) throws -> Data {
        try JSONEncoder.mmcl.encode(instance)
    }

    func decode(from data: Data) throws -> LauncherInstance {
        try JSONDecoder.mmcl.decode(LauncherInstance.self, from: data)
    }

    static func slug(for name: String) -> String {
        let transliterations: [Character: String] = [
            "原": "yuan", "版": "ban", "生": "sheng", "存": "cun"
        ]
        var parts: [String] = []
        var current = ""

        for character in name.lowercased() {
            if let replacement = transliterations[character] {
                if !current.isEmpty {
                    parts.append(current)
                    current = ""
                }
                parts.append(replacement)
            } else if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                parts.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            parts.append(current)
        }

        let slug = parts.joined(separator: "-")
        return slug.isEmpty ? "instance" : slug
    }
}

protocol VersionManifestServicing {
    var manifestURL: URL { get }
    func decodeManifest(from data: Data) throws -> VersionManifest
    func decodeVersionMetadata(from data: Data) throws -> VersionMetadata
    func decodeAssetIndex(from data: Data) throws -> AssetIndex
    func fetchManifest(from url: URL?) async throws -> VersionManifest
    func fetchVersionMetadata(from url: URL) async throws -> VersionMetadata
    func fetchAssetIndex(from url: URL) async throws -> AssetIndex
}

struct VersionManifestService: VersionManifestServicing {
    let manifestURL = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!

    func decodeManifest(from data: Data) throws -> VersionManifest {
        try JSONDecoder.mmcl.decode(VersionManifest.self, from: data)
    }

    func decodeVersionMetadata(from data: Data) throws -> VersionMetadata {
        try JSONDecoder.mmcl.decode(VersionMetadata.self, from: data)
    }

    func decodeAssetIndex(from data: Data) throws -> AssetIndex {
        try JSONDecoder.mmcl.decode(AssetIndex.self, from: data)
    }

    func fetchManifest(from url: URL? = nil) async throws -> VersionManifest {
        let data = try await loadData(from: url ?? manifestURL)
        return try decodeManifest(from: data)
    }

    func fetchVersionMetadata(from url: URL) async throws -> VersionMetadata {
        let data = try await loadData(from: url)
        return try decodeVersionMetadata(from: data)
    }

    func fetchAssetIndex(from url: URL) async throws -> AssetIndex {
        let data = try await loadData(from: url)
        return try decodeAssetIndex(from: data)
    }

    private func loadData(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }
        let response = try await URLSession.shared.data(from: url)
        return response.0
    }
}

protocol DownloadServicing {
    func makeVanillaClientJob(version: String, destination: URL) -> DownloadJob
    func writeVersionMetadata(metadata: VersionMetadata, instance: LauncherInstance) throws -> URL
    func makeVanillaInstallJobs(
        metadata: VersionMetadata,
        instance: LauncherInstance,
        source: DownloadSource
    ) -> [DownloadJob]
    func makeVanillaRepairJobs(
        metadata: VersionMetadata,
        instance: LauncherInstance,
        source: DownloadSource
    ) -> [DownloadJob]
    func makeAssetObjectJobs(
        assetIndex: AssetIndex,
        instance: LauncherInstance,
        source: DownloadSource
    ) -> [DownloadJob]
    func prepareNativeLibraries(metadata: VersionMetadata, instance: LauncherInstance) throws -> [URL]
    func execute(job: DownloadJob) async throws -> DownloadJob
}

struct DownloadService: DownloadServicing {
    func makeVanillaClientJob(version: String, destination: URL) -> DownloadJob {
        DownloadJob(title: "Minecraft \(version) 客户端", source: .official, destination: destination, totalBytes: 1)
    }

    func writeVersionMetadata(metadata: VersionMetadata, instance: LauncherInstance) throws -> URL {
        let versionDirectory = instance.rootDirectory
            .appendingPathComponent(".minecraft", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(metadata.id, isDirectory: true)
        try FileManager.default.createDirectory(at: versionDirectory, withIntermediateDirectories: true)

        let metadataURL = versionDirectory.appendingPathComponent("\(metadata.id).json")
        try JSONEncoder.mmcl.encode(metadata).write(to: metadataURL, options: .atomic)
        return metadataURL
    }

    func makeVanillaInstallJobs(
        metadata: VersionMetadata,
        instance: LauncherInstance,
        source: DownloadSource
    ) -> [DownloadJob] {
        let minecraftDirectory = instance.rootDirectory.appendingPathComponent(".minecraft", isDirectory: true)
        let versionDirectory = minecraftDirectory
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(metadata.id, isDirectory: true)

        var jobs: [DownloadJob] = [
            DownloadJob(
                title: "Minecraft \(metadata.id) 客户端",
                source: source,
                remoteURL: metadata.downloads.client.url,
                destination: versionDirectory.appendingPathComponent("\(metadata.id).jar"),
                sha1: metadata.downloads.client.sha1,
                totalBytes: metadata.downloads.client.size
            ),
            DownloadJob(
                title: "Minecraft \(metadata.id) 资源索引",
                source: source,
                remoteURL: metadata.assetIndex.url,
                destination: minecraftDirectory
                    .appendingPathComponent("assets", isDirectory: true)
                    .appendingPathComponent("indexes", isDirectory: true)
                    .appendingPathComponent("\(metadata.assetIndex.id).json"),
                sha1: metadata.assetIndex.sha1,
                totalBytes: metadata.assetIndex.size
            )
        ]

        let libraryJobs = metadata.libraries.compactMap { library -> DownloadJob? in
            guard let artifact = library.artifact else { return nil }
            return DownloadJob(
                title: library.name,
                source: source,
                remoteURL: artifact.url,
                destination: minecraftDirectory
                    .appendingPathComponent("libraries", isDirectory: true)
                    .appendingPathComponent(artifact.path),
                sha1: artifact.sha1,
                totalBytes: artifact.size
            )
        }

        jobs.append(contentsOf: libraryJobs)
        let nativeJobs = metadata.libraries.compactMap { library -> DownloadJob? in
            guard let artifact = library.nativeArtifact() else { return nil }
            return DownloadJob(
                title: "\(library.name) native",
                source: source,
                remoteURL: artifact.url,
                destination: minecraftDirectory
                    .appendingPathComponent("libraries", isDirectory: true)
                    .appendingPathComponent(artifact.path),
                sha1: artifact.sha1,
                totalBytes: artifact.size
            )
        }

        jobs.append(contentsOf: nativeJobs)
        return jobs
    }

    func makeVanillaRepairJobs(
        metadata: VersionMetadata,
        instance: LauncherInstance,
        source: DownloadSource
    ) -> [DownloadJob] {
        makeVanillaInstallJobs(metadata: metadata, instance: instance, source: source)
            .filter { !FileManager.default.fileExists(atPath: $0.destination.path) }
    }

    func makeAssetObjectJobs(
        assetIndex: AssetIndex,
        instance: LauncherInstance,
        source: DownloadSource
    ) -> [DownloadJob] {
        let objectsDirectory = instance.rootDirectory
            .appendingPathComponent(".minecraft", isDirectory: true)
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("objects", isDirectory: true)

        return assetIndex.objects
            .sorted { $0.key < $1.key }
            .map { name, object in
                let objectPath = "\(object.pathPrefix)/\(object.hash)"
                return DownloadJob(
                    title: "资源文件 \(name)",
                    source: source,
                    remoteURL: URL(string: "https://resources.download.minecraft.net/\(objectPath)")!,
                    destination: objectsDirectory
                        .appendingPathComponent(object.pathPrefix, isDirectory: true)
                        .appendingPathComponent(object.hash),
                    sha1: object.hash,
                    totalBytes: object.size
                )
            }
    }

    func prepareNativeLibraries(metadata: VersionMetadata, instance: LauncherInstance) throws -> [URL] {
        let minecraftDirectory = instance.rootDirectory.appendingPathComponent(".minecraft", isDirectory: true)
        let librariesDirectory = minecraftDirectory.appendingPathComponent("libraries", isDirectory: true)
        let nativesDirectory = minecraftDirectory
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(metadata.id, isDirectory: true)
            .appendingPathComponent("natives", isDirectory: true)
        try FileManager.default.createDirectory(at: nativesDirectory, withIntermediateDirectories: true)

        return try metadata.libraries.compactMap { library -> URL? in
            guard let artifact = library.nativeArtifact() else { return nil }
            let archiveURL = librariesDirectory.appendingPathComponent(artifact.path)
            guard FileManager.default.fileExists(atPath: archiveURL.path) else {
                throw NativeLibraryPreparationError.missingArchive(archiveURL)
            }
            try Self.unzip(archiveURL: archiveURL, destination: nativesDirectory)
            return archiveURL
        }
    }

    private static func unzip(archiveURL: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-qq", archiveURL.path, "-d", destination.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NativeLibraryPreparationError.unzipFailed(archiveURL)
        }
    }

    func execute(job: DownloadJob) async throws -> DownloadJob {
        guard let remoteURL = job.remoteURL else {
            throw DownloadExecutionError.missingRemoteURL(jobTitle: job.title)
        }

        var runningJob = job
        runningJob.status = .running

        let data: Data
        if remoteURL.isFileURL {
            data = try Data(contentsOf: remoteURL)
        } else {
            let response = try await URLSession.shared.data(from: remoteURL)
            data = response.0
        }

        let parentDirectory = runningJob.destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        try data.write(to: runningJob.destination, options: .atomic)

        if let expectedSHA1 = runningJob.sha1 {
            let actualSHA1 = Self.sha1Hex(for: data)
            guard actualSHA1.caseInsensitiveCompare(expectedSHA1) == .orderedSame else {
                var failedJob = runningJob
                failedJob.status = .failed
                failedJob.completedBytes = Int64(data.count)
                throw DownloadExecutionError.sha1Mismatch(
                    jobTitle: runningJob.title,
                    expected: expectedSHA1,
                    actual: actualSHA1
                )
            }
        }

        runningJob.update(completedBytes: Int64(data.count))
        return runningJob
    }

    static func sha1Hex(for data: Data) -> String {
        Insecure.SHA1.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum NativeLibraryPreparationError: LocalizedError, Equatable {
    case missingArchive(URL)
    case unzipFailed(URL)

    var errorDescription: String? {
        switch self {
        case .missingArchive(let url):
            return "缺少 native library：\(url.path)"
        case .unzipFailed(let url):
            return "native library 解压失败：\(url.path)"
        }
    }
}

enum DownloadExecutionError: LocalizedError, Equatable {
    case missingRemoteURL(jobTitle: String)
    case sha1Mismatch(jobTitle: String, expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .missingRemoteURL(let jobTitle):
            return "缺少下载地址：\(jobTitle)"
        case .sha1Mismatch(let jobTitle, _, _):
            return "SHA-1 校验失败：\(jobTitle)"
        }
    }
}

protocol JavaRuntimeServicing {
    func bundledSearchLocations() -> [URL]
    func recommendedMajorVersion(for gameVersion: String) -> Int
    func parseJavaHomeVerboseOutput(_ output: String) -> [JavaRuntime]
    func discoverInstalledRuntimes() async throws -> [JavaRuntime]
}

struct JavaRuntimeService: JavaRuntimeServicing {
    var javaHomeExecutable: URL = URL(fileURLWithPath: "/usr/libexec/java_home")

    func bundledSearchLocations() -> [URL] {
        [
            URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Java/JavaVirtualMachines")
        ]
    }

    func recommendedMajorVersion(for gameVersion: String) -> Int {
        JavaRuntime.recommendedMajorVersion(for: gameVersion)
    }

    func parseJavaHomeVerboseOutput(_ output: String) -> [JavaRuntime] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { parseJavaHomeLine(String($0)) }
    }

    func discoverInstalledRuntimes() async throws -> [JavaRuntime] {
        let process = Process()
        process.executableURL = javaHomeExecutable
        process.arguments = ["-V"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        return parseJavaHomeVerboseOutput(output)
    }

    private func parseJavaHomeLine(_ line: String) -> JavaRuntime? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let pattern = #"^([0-9]+(?:\.[0-9]+)*) \(([^)]+)\) ".+" - "(.+)" (/.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.numberOfRanges == 5,
              let versionRange = Range(match.range(at: 1), in: trimmed),
              let architectureRange = Range(match.range(at: 2), in: trimmed),
              let nameRange = Range(match.range(at: 3), in: trimmed),
              let homeRange = Range(match.range(at: 4), in: trimmed)
        else {
            return nil
        }

        let version = String(trimmed[versionRange])
        let architecture = RuntimeArchitecture(rawValue: String(trimmed[architectureRange])) ?? .unknown
        let name = String(trimmed[nameRange])
        let homeURL = URL(fileURLWithPath: String(trimmed[homeRange]), isDirectory: true)
        let majorVersion = Int(version.split(separator: ".").first ?? "") ?? 0

        return JavaRuntime(
            name: name,
            version: version,
            majorVersion: majorVersion,
            architecture: architecture,
            executableURL: homeURL.appendingPathComponent("bin/java")
        )
    }
}

protocol LaunchServicing {
    func previewCommand(for instance: LauncherInstance, java: JavaRuntime) -> [String]
    func preflight(instance: LauncherInstance, java: JavaRuntime) -> LaunchPreflightReport
    func launch(instance: LauncherInstance, java: JavaRuntime) throws -> LaunchSession
}

struct LaunchService: LaunchServicing {
    func previewCommand(for instance: LauncherInstance, java: JavaRuntime) -> [String] {
        let minecraftDirectory = instance.rootDirectory.appendingPathComponent(".minecraft", isDirectory: true)
        let versionDirectory = minecraftDirectory
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(instance.gameVersion, isDirectory: true)
        let nativesDirectory = versionDirectory.appendingPathComponent("natives", isDirectory: true)
        let clientJar = versionDirectory.appendingPathComponent("\(instance.gameVersion).jar")
        let librariesDirectory = minecraftDirectory.appendingPathComponent("libraries", isDirectory: true)
        let metadata = localVersionMetadata(for: instance)
        let classpath = metadata.map {
            classpathEntries(metadata: $0, minecraftDirectory: minecraftDirectory, clientJar: clientJar)
                .map(\.path)
                .joined(separator: ":")
        } ?? "\(librariesDirectory.path)/*:\(clientJar.path)"
        let mainClass = metadata?.mainClass ?? "net.minecraft.client.main.Main"
        let assetIndex = metadata?.assetIndex.id ?? instance.gameVersion
        let substitutions = launchSubstitutions(
            instance: instance,
            minecraftDirectory: minecraftDirectory,
            nativesDirectory: nativesDirectory,
            classpath: classpath,
            assetIndex: assetIndex
        )

        if let metadata, let arguments = metadata.arguments {
            let jvmArguments = expand(arguments.jvm, substitutions: substitutions, operatingSystem: "osx")
            let gameArguments = expand(arguments.game, substitutions: substitutions, operatingSystem: "osx")
            return [
                java.executableURL.path,
                "-Xmx\(instance.profile.memoryMegabytes)m"
            ]
            + instance.profile.jvmArguments
            + jvmArguments
            + [mainClass]
            + gameArguments
        }

        if let metadata, let legacyArguments = metadata.minecraftArguments {
            return [
                java.executableURL.path,
                "-Xmx\(instance.profile.memoryMegabytes)m",
                "-Djava.library.path=\(nativesDirectory.path)"
            ]
            + instance.profile.jvmArguments
            + [
                "-cp",
                classpath,
                mainClass
            ]
            + expandLegacyArguments(legacyArguments, substitutions: substitutions)
        }

        return [
            java.executableURL.path,
            "-Xmx\(instance.profile.memoryMegabytes)m",
            "-Djava.library.path=\(nativesDirectory.path)"
        ]
        + instance.profile.jvmArguments
        + [
            "-cp",
            classpath,
            mainClass,
            "--username",
            instance.profile.offlineUsername,
            "--version",
            instance.gameVersion,
            "--gameDir",
            minecraftDirectory.path,
            "--assetsDir",
            minecraftDirectory.appendingPathComponent("assets", isDirectory: true).path,
            "--assetIndex",
            assetIndex,
            "--accessToken",
            "0",
            "--userType",
            "legacy"
        ]
    }

    func preflight(instance: LauncherInstance, java: JavaRuntime) -> LaunchPreflightReport {
        let fileManager = FileManager.default
        let minecraftDirectory = instance.rootDirectory.appendingPathComponent(".minecraft", isDirectory: true)
        let versionDirectory = minecraftDirectory
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(instance.gameVersion, isDirectory: true)
        let metadataURL = versionDirectory.appendingPathComponent("\(instance.gameVersion).json")
        var blockingIssues: [String] = []
        var warnings: [String] = []
        var actions: [String] = []

        guard let metadata = localVersionMetadata(for: instance) else {
            blockingIssues.append("缺少 version JSON：\(metadataURL.path)")
            actions.append("生成安装计划并完成下载")
            actions.append("刷新版本列表后重新生成安装计划")
            return LaunchPreflightReport(
                severity: .error,
                summary: blockingIssues.joined(separator: "\n"),
                suggestedActions: actions
            )
        }

        let clientJar = versionDirectory.appendingPathComponent("\(instance.gameVersion).jar")
        if !fileManager.fileExists(atPath: clientJar.path) {
            blockingIssues.append("缺少 client jar：\(clientJar.path)")
            actions.append("生成安装计划并完成下载")
        }

        let assetIndex = minecraftDirectory
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("indexes", isDirectory: true)
            .appendingPathComponent("\(metadata.assetIndex.id).json")
        if !fileManager.fileExists(atPath: assetIndex.path) {
            blockingIssues.append("缺少 asset index：\(assetIndex.path)")
            actions.append("生成安装计划并完成下载")
        }

        let librariesDirectory = minecraftDirectory.appendingPathComponent("libraries", isDirectory: true)
        let missingLibraries = metadata.libraries.compactMap { library -> String? in
            guard let artifact = library.artifact else { return nil }
            let artifactURL = librariesDirectory.appendingPathComponent(artifact.path)
            return fileManager.fileExists(atPath: artifactURL.path) ? nil : library.name
        }
        if !missingLibraries.isEmpty {
            let names = missingLibraries.prefix(3).joined(separator: ", ")
            let suffix = missingLibraries.count > 3 ? " 等 \(missingLibraries.count) 个" : ""
            blockingIssues.append("缺少 library：\(names)\(suffix)")
            actions.append("生成安装计划并完成下载")
        }

        let nativeArtifacts = metadata.libraries.compactMap { $0.nativeArtifact() }
        if !nativeArtifacts.isEmpty {
            let missingNativeArchives = nativeArtifacts.filter { artifact in
                !fileManager.fileExists(atPath: librariesDirectory.appendingPathComponent(artifact.path).path)
            }
            if !missingNativeArchives.isEmpty {
                blockingIssues.append("缺少 native library：\(missingNativeArchives.count) 个")
                actions.append("生成安装计划并完成下载")
            }

            let nativesDirectory = versionDirectory.appendingPathComponent("natives", isDirectory: true)
            let nativeContents = (try? fileManager.contentsOfDirectory(atPath: nativesDirectory.path)) ?? []
            if nativeContents.isEmpty {
                blockingIssues.append("native libraries 尚未解压：\(nativesDirectory.path)")
                actions.append("准备 Native")
            }
        }

        if !java.isRecommended(for: instance.gameVersion) {
            let recommended = JavaRuntime.recommendedMajorVersion(for: instance.gameVersion)
            warnings.append("当前 Java \(java.majorVersion) 不是推荐版本，建议使用 Java \(recommended)。")
            actions.append("重新扫描 Java 并选择推荐版本")
        }

        if !blockingIssues.isEmpty {
            return LaunchPreflightReport(
                severity: .error,
                summary: blockingIssues.joined(separator: "\n"),
                suggestedActions: Array(NSOrderedSet(array: actions).compactMap { $0 as? String })
            )
        }

        if !warnings.isEmpty {
            return LaunchPreflightReport(
                severity: .warning,
                summary: warnings.joined(separator: "\n"),
                suggestedActions: Array(NSOrderedSet(array: actions).compactMap { $0 as? String })
            )
        }

        return LaunchPreflightReport(
            severity: .info,
            summary: "启动前检查通过。",
            suggestedActions: []
        )
    }

    private func expand(
        _ arguments: [VersionMetadata.LaunchArgument],
        substitutions: [String: String],
        operatingSystem: String
    ) -> [String] {
        arguments.flatMap { argument -> [String] in
            guard argument.applies(to: operatingSystem) else { return [] }
            return argument.value.strings.map { replacePlaceholders(in: $0, substitutions: substitutions) }
        }
    }

    private func expandLegacyArguments(_ arguments: String, substitutions: [String: String]) -> [String] {
        arguments
            .split(separator: " ")
            .map { replacePlaceholders(in: String($0), substitutions: substitutions) }
    }

    private func launchSubstitutions(
        instance: LauncherInstance,
        minecraftDirectory: URL,
        nativesDirectory: URL,
        classpath: String,
        assetIndex: String
    ) -> [String: String] {
        [
            "auth_player_name": instance.profile.offlineUsername,
            "version_name": instance.gameVersion,
            "game_directory": minecraftDirectory.path,
            "assets_root": minecraftDirectory.appendingPathComponent("assets", isDirectory: true).path,
            "assets_index_name": assetIndex,
            "auth_uuid": "00000000000000000000000000000000",
            "auth_access_token": "0",
            "clientid": "",
            "auth_xuid": "",
            "user_type": "legacy",
            "version_type": "release",
            "natives_directory": nativesDirectory.path,
            "launcher_name": "MMCL",
            "launcher_version": "0.1",
            "classpath": classpath,
            "resolution_width": "854",
            "resolution_height": "480"
        ]
    }

    private func replacePlaceholders(in value: String, substitutions: [String: String]) -> String {
        substitutions.reduce(value) { result, item in
            result.replacingOccurrences(of: "${\(item.key)}", with: item.value)
        }
    }

    private func localVersionMetadata(for instance: LauncherInstance) -> VersionMetadata? {
        let metadataURL = instance.rootDirectory
            .appendingPathComponent(".minecraft", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(instance.gameVersion, isDirectory: true)
            .appendingPathComponent("\(instance.gameVersion).json")
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? JSONDecoder.mmcl.decode(VersionMetadata.self, from: data)
    }

    private func classpathEntries(
        metadata: VersionMetadata,
        minecraftDirectory: URL,
        clientJar: URL
    ) -> [URL] {
        let librariesDirectory = minecraftDirectory.appendingPathComponent("libraries", isDirectory: true)
        let libraryJars = metadata.libraries.compactMap { library -> URL? in
            guard let artifact = library.artifact else { return nil }
            return librariesDirectory.appendingPathComponent(artifact.path)
        }
        return libraryJars + [clientJar]
    }

    func launch(instance: LauncherInstance, java: JavaRuntime) throws -> LaunchSession {
        let command = previewCommand(for: instance, java: java)
        guard let executable = command.first else {
            throw LaunchExecutionError.emptyCommand
        }

        let minecraftDirectory = instance.rootDirectory.appendingPathComponent(".minecraft", isDirectory: true)
        let logsDirectory = instance.rootDirectory.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: minecraftDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let logFileURL = logsDirectory.appendingPathComponent("latest.log")
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }

        let logHandle = try FileHandle(forWritingTo: logFileURL)
        try logHandle.truncate(atOffset: 0)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())
        process.currentDirectoryURL = minecraftDirectory
        process.standardOutput = logHandle
        process.standardError = logHandle
        process.terminationHandler = { _ in
            try? logHandle.close()
        }

        try process.run()

        return LaunchSession(
            processIdentifier: process.processIdentifier,
            command: command,
            logFileURL: logFileURL
        )
    }
}

enum LaunchExecutionError: LocalizedError, Equatable {
    case emptyCommand

    var errorDescription: String? {
        switch self {
        case .emptyCommand:
            return "启动命令为空，无法启动 Minecraft。"
        }
    }
}

protocol ModrinthServicing {
    var baseURL: URL { get }
    func search(query: String, facets: [String]?) async throws -> ModrinthSearchResponse
    func fetchProject(id: String) async throws -> ModrinthProject
    func fetchVersions(projectID: String, gameVersion: String?, loader: String?) async throws -> [ModrinthVersion]
    func downloadFile(from urlString: String, to destination: URL) async throws
}

struct ModrinthService: ModrinthServicing {
    let baseURL = URL(string: "https://api.modrinth.com/v2")!

    func search(query: String, facets: [String]? = nil) async throws -> ModrinthSearchResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "query", value: query)]
        if let facets {
            queryItems.append(URLQueryItem(name: "facets", value: "[\(facets.joined(separator: ","))]"))
        }
        queryItems.append(URLQueryItem(name: "limit", value: "20"))
        components.queryItems = queryItems
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder.mmcl.decode(ModrinthSearchResponse.self, from: data)
    }

    func fetchProject(id: String) async throws -> ModrinthProject {
        let url = baseURL.appendingPathComponent("project/\(id)")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder.mmcl.decode(ModrinthProject.self, from: data)
    }

    func fetchVersions(projectID: String, gameVersion: String? = nil, loader: String? = nil) async throws -> [ModrinthVersion] {
        var components = URLComponents(url: baseURL.appendingPathComponent("project/\(projectID)/version"), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem]()
        if let gameVersion {
            queryItems.append(URLQueryItem(name: "game_versions", value: "[\"\(gameVersion)\"]"))
        }
        if let loader {
            queryItems.append(URLQueryItem(name: "loaders", value: "[\"\(loader)\"]"))
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder.mmcl.decode([ModrinthVersion].self, from: data)
    }

    func downloadFile(from urlString: String, to destination: URL) async throws {
        guard let url = URL(string: urlString) else {
            throw ModrinthError.invalidURL(urlString)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }
}

enum ModrinthError: LocalizedError, Equatable {
    case invalidURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "无效的下载地址：\(url)"
        }
    }
}

protocol FabricServicing {
    func fetchLoaderVersions(gameVersion: String) async throws -> [FabricLoaderVersion]
    func fetchProfile(gameVersion: String, loaderVersion: String) async throws -> FabricProfile
    func installFabric(
        gameVersion: String,
        loaderVersion: String?,
        instance: LauncherInstance
    ) async throws -> VersionMetadata
}

struct FabricService: FabricServicing {
    let baseURL = URL(string: "https://meta.fabricmc.net/v2")!

    func fetchLoaderVersions(gameVersion: String) async throws -> [FabricLoaderVersion] {
        let url = baseURL.appendingPathComponent("versions/loader/\(gameVersion)")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder.mmcl.decode([FabricLoaderVersion].self, from: data)
    }

    func fetchProfile(gameVersion: String, loaderVersion: String) async throws -> FabricProfile {
        let url = baseURL.appendingPathComponent("versions/loader/\(gameVersion)/\(loaderVersion)/profile")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder.mmcl.decode(FabricProfile.self, from: data)
    }

    func installFabric(
        gameVersion: String,
        loaderVersion: String? = nil,
        instance: LauncherInstance
    ) async throws -> VersionMetadata {
        // 1. Determine loader version
        let versions = try await fetchLoaderVersions(gameVersion: gameVersion)
        let selectedVersion: String
        if let explicit = loaderVersion {
            selectedVersion = explicit
        } else {
            guard let latest = versions.first(where: { $0.stable }) ?? versions.first else {
                throw FabricInstallError.noLoaderAvailable(gameVersion)
            }
            selectedVersion = latest.version
        }

        // 2. Fetch Fabric profile
        let profile = try await fetchProfile(gameVersion: gameVersion, loaderVersion: selectedVersion)

        // 3. Build a minimal VersionMetadata from the profile
        let baseMetadata = try readBaseMetadata(instance: instance, gameVersion: profile.inheritsFrom)

        let fabricLibraries = baseMetadata.libraries + [
            VersionMetadata.Library(
                name: "net.fabricmc:intermediary:\(profile.inheritsFrom):v2",
                downloads: nil
            )
        ]

        var metadata = baseMetadata
        metadata.id = "\(profile.inheritsFrom)-fabric-\(selectedVersion)"
        metadata.mainClass = profile.mainClass
        metadata.libraries = fabricLibraries

        // 4. Write version JSON
        let versionDir = instance.rootDirectory
            .appendingPathComponent(".minecraft", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(metadata.id, isDirectory: true)
        try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
        let metadataURL = versionDir.appendingPathComponent("\(metadata.id).json")
        try JSONEncoder.mmcl.encode(metadata).write(to: metadataURL, options: .atomic)

        return metadata
    }

    private func readBaseMetadata(instance: LauncherInstance, gameVersion: String) throws -> VersionMetadata {
        let metadataURL = instance.rootDirectory
            .appendingPathComponent(".minecraft", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(gameVersion, isDirectory: true)
            .appendingPathComponent("\(gameVersion).json")
        guard let data = try? Data(contentsOf: metadataURL) else {
            throw FabricInstallError.baseMetadataNotFound(gameVersion)
        }
        return try JSONDecoder.mmcl.decode(VersionMetadata.self, from: data)
    }
}

enum FabricInstallError: LocalizedError, Equatable {
    case noLoaderAvailable(String)
    case baseMetadataNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noLoaderAvailable(let version):
            return "没有可用的 Fabric loader 版本：Minecraft \(version)"
        case .baseMetadataNotFound(let version):
            return "缺少基础版本元数据：\(version)。请先安装原版 \(version)。"
        }
    }
}

protocol DiagnosticServicing {
    func javaMismatch(instance: LauncherInstance, runtime: JavaRuntime) -> DiagnosticReport?
}

struct DiagnosticService: DiagnosticServicing {
    func javaMismatch(instance: LauncherInstance, runtime: JavaRuntime) -> DiagnosticReport? {
        guard !runtime.isRecommended(for: instance.gameVersion) else { return nil }
        let required = JavaRuntime.recommendedMajorVersion(for: instance.gameVersion)
        return DiagnosticReport(
            title: "Java 版本过低",
            severity: .warning,
            summary: "实例 \(instance.name) 推荐使用 Java \(required)，当前选择的是 Java \(runtime.majorVersion)。",
            suggestedActions: ["安装 Java \(required) 或更高版本", "在实例设置中重新选择 Java 运行时"]
        )
    }
}
