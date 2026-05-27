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

protocol DownloadServicing: AnyObject {
    var onProgress: ((UUID, Int64) -> Void)? { get set }
    var onComplete: ((UUID, DownloadJob) -> Void)? { get set }
    var onError: ((UUID, Error) -> Void)? { get set }

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
    func startDownload(_ job: DownloadJob)
    func pauseDownload(id: UUID)
    func resumeDownload(id: UUID)
    func cancelAllDownloads()
}

final class DownloadService: NSObject, DownloadServicing, URLSessionDownloadDelegate {
    var onProgress: ((UUID, Int64) -> Void)?
    var onComplete: ((UUID, DownloadJob) -> Void)?
    var onError: ((UUID, Error) -> Void)?

    private var session: URLSession!
    private var activeTasks: [UUID: URLSessionDownloadTask] = [:]
    private var resumeDataMap: [UUID: Data] = [:]
    private var jobsByID: [UUID: DownloadJob] = [:]

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    // MARK: - Download Control

    func startDownload(_ job: DownloadJob) {
        guard let remoteURL = job.remoteURL else {
            onError?(job.id, DownloadExecutionError.missingRemoteURL(jobTitle: job.title))
            return
        }

        var runningJob = job
        runningJob.status = .running
        jobsByID[job.id] = runningJob

        // Handle file URLs directly (URLSessionDownloadTask doesn't support them)
        if remoteURL.isFileURL {
            DispatchQueue.global().async { [weak self] in
                guard let self else { return }
                let parentDir = job.destination.deletingLastPathComponent()
                do {
                    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: job.destination.path) {
                        try FileManager.default.removeItem(at: job.destination)
                    }
                    try FileManager.default.copyItem(at: remoteURL, to: job.destination)

                    if let expectedSHA1 = job.sha1 {
                        let data = try Data(contentsOf: job.destination)
                        let actualSHA1 = Self.sha1Hex(for: data)
                        if actualSHA1.caseInsensitiveCompare(expectedSHA1) != .orderedSame {
                            var failedJob = job
                            failedJob.status = .failed
                            self.jobsByID[job.id] = failedJob
                            self.onError?(job.id, DownloadExecutionError.sha1Mismatch(
                                jobTitle: job.title,
                                expected: expectedSHA1,
                                actual: actualSHA1
                            ))
                            return
                        }
                    }

                    var completedJob = job
                    completedJob.completedBytes = job.totalBytes
                    completedJob.status = .completed
                    self.jobsByID[job.id] = completedJob
                    self.onComplete?(job.id, completedJob)
                } catch {
                    var failedJob = job
                    failedJob.status = .failed
                    self.jobsByID[job.id] = failedJob
                    self.onError?(job.id, error)
                }
            }
            return
        }

        let task: URLSessionDownloadTask
        if let resumeData = resumeDataMap[job.id] {
            task = session.downloadTask(withResumeData: resumeData)
            resumeDataMap.removeValue(forKey: job.id)
        } else {
            task = session.downloadTask(with: remoteURL)
        }
        task.taskDescription = job.id.uuidString
        activeTasks[job.id] = task
        task.resume()
    }

    func pauseDownload(id: UUID) {
        guard let task = activeTasks[id] else { return }
        task.cancel { [weak self] data in
            if let data {
                self?.resumeDataMap[id] = data
            }
        }
        activeTasks.removeValue(forKey: id)
        if var job = jobsByID[id] {
            job.status = .paused
            jobsByID[id] = job
        }
    }

    func resumeDownload(id: UUID) {
        guard var job = jobsByID[id], job.status == .paused else { return }
        job.status = .queued
        jobsByID[id] = job
        startDownload(job)
    }

    func cancelAllDownloads() {
        for (_, task) in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
        resumeDataMap.removeAll()
        for (id, _) in jobsByID {
            if var job = jobsByID[id], job.status.isActive {
                job.status = .failed
                jobsByID[id] = job
            }
        }
    }

    // MARK: - Job Factory Methods

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

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let uuidString = downloadTask.taskDescription,
              let jobID = UUID(uuidString: uuidString),
              var job = jobsByID[jobID] else { return }

        activeTasks.removeValue(forKey: jobID)

        let parentDirectory = job.destination.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: job.destination.path) {
                try FileManager.default.removeItem(at: job.destination)
            }
            try FileManager.default.moveItem(at: location, to: job.destination)
        } catch {
            job.status = .failed
            jobsByID[jobID] = job
            onError?(jobID, error)
            return
        }

        if let expectedSHA1 = job.sha1 {
            if let data = try? Data(contentsOf: job.destination) {
                let actualSHA1 = Self.sha1Hex(for: data)
                if actualSHA1.caseInsensitiveCompare(expectedSHA1) != .orderedSame {
                    job.status = .failed
                    jobsByID[jobID] = job
                    onError?(jobID, DownloadExecutionError.sha1Mismatch(
                        jobTitle: job.title,
                        expected: expectedSHA1,
                        actual: actualSHA1
                    ))
                    return
                }
            }
        }

        job.completedBytes = job.totalBytes
        job.status = .completed
        jobsByID[jobID] = job
        onComplete?(jobID, job)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let uuidString = downloadTask.taskDescription,
              let jobID = UUID(uuidString: uuidString) else { return }

        if var job = jobsByID[jobID] {
            job.completedBytes = totalBytesWritten
            if totalBytesExpectedToWrite > 0 {
                job.totalBytes = totalBytesExpectedToWrite
            }
            jobsByID[jobID] = job
        }
        onProgress?(jobID, totalBytesWritten)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let uuidString = downloadTask.taskDescription,
              let jobID = UUID(uuidString: uuidString) else { return }

        activeTasks.removeValue(forKey: jobID)

        if let error {
            if (error as NSError).code == NSURLErrorCancelled {
                return
            }
            if var job = jobsByID[jobID] {
                job.status = .failed
                jobsByID[jobID] = job
            }
            onError?(jobID, error)
        }
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
            "resolution_width": String(instance.profile.resolutionWidth),
            "resolution_height": String(instance.profile.resolutionHeight)
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

protocol QuiltServicing {
    func fetchLoaderVersions(gameVersion: String) async throws -> [QuiltLoaderVersion]
    func fetchProfile(gameVersion: String, loaderVersion: String) async throws -> QuiltProfile
    func installQuilt(gameVersion: String, loaderVersion: String?, instance: LauncherInstance) async throws -> VersionMetadata
}

struct QuiltService: QuiltServicing {
    let baseURL = URL(string: "https://meta.quiltmc.org/v3")!

    func fetchLoaderVersions(gameVersion: String) async throws -> [QuiltLoaderVersion] {
        let url = baseURL.appendingPathComponent("versions/loader/\(gameVersion)")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder.mmcl.decode([QuiltLoaderVersion].self, from: data)
    }

    func fetchProfile(gameVersion: String, loaderVersion: String) async throws -> QuiltProfile {
        let url = baseURL.appendingPathComponent("versions/loader/\(gameVersion)/\(loaderVersion)/profile")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder.mmcl.decode(QuiltProfile.self, from: data)
    }

    func installQuilt(gameVersion: String, loaderVersion: String? = nil, instance: LauncherInstance) async throws -> VersionMetadata {
        let versions = try await fetchLoaderVersions(gameVersion: gameVersion)
        let selectedVersion: String
        if let explicit = loaderVersion {
            selectedVersion = explicit
        } else {
            guard let latest = versions.first(where: { $0.stable }) ?? versions.first else {
                throw QuiltInstallError.noLoaderAvailable(gameVersion)
            }
            selectedVersion = latest.version
        }

        let profile = try await fetchProfile(gameVersion: gameVersion, loaderVersion: selectedVersion)
        let baseMetadata = try readBaseMetadata(instance: instance, gameVersion: profile.inheritsFrom)

        var metadata = baseMetadata
        metadata.id = "\(profile.inheritsFrom)-quilt-\(selectedVersion)"
        metadata.mainClass = profile.mainClass

        let versionDir = instance.rootDirectory
            .appendingPathComponent(".minecraft", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(metadata.id, isDirectory: true)
        try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
        try JSONEncoder.mmcl.encode(metadata).write(to: versionDir.appendingPathComponent("\(metadata.id).json"), options: .atomic)

        return metadata
    }

    private func readBaseMetadata(instance: LauncherInstance, gameVersion: String) throws -> VersionMetadata {
        let metadataURL = instance.rootDirectory
            .appendingPathComponent(".minecraft", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(gameVersion, isDirectory: true)
            .appendingPathComponent("\(gameVersion).json")
        guard let data = try? Data(contentsOf: metadataURL) else {
            throw QuiltInstallError.baseMetadataNotFound(gameVersion)
        }
        return try JSONDecoder.mmcl.decode(VersionMetadata.self, from: data)
    }
}

enum QuiltInstallError: LocalizedError, Equatable {
    case noLoaderAvailable(String)
    case baseMetadataNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noLoaderAvailable(let v): return "没有可用的 Quilt loader 版本：Minecraft \(v)"
        case .baseMetadataNotFound(let v): return "缺少基础版本元数据：\(v)。请先安装原版 \(v)。"
        }
    }
}

protocol ForgeServicing {
    func fetchVersions(gameVersion: String) async throws -> [ForgeVersion]
    func installForge(gameVersion: String, forgeVersion: String?, instance: LauncherInstance) async throws -> VersionMetadata
}

struct ForgeService: ForgeServicing {
    let baseURL = URL(string: "https://files.minecraftforge.net/net/minecraftforge/forge")!

    func fetchVersions(gameVersion: String) async throws -> [ForgeVersion] {
        let url = URL(string: "https://files.minecraftforge.net/net/minecraftforge/forge/\(gameVersion)/promotions_slim.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let promo = json?["promos"] as? [String: String] ?? [:]
        return promo.compactMap { key, value in
            guard key.hasSuffix("-latest") || key.hasSuffix("-recommended") else { return nil }
            let mcVersion = key.replacingOccurrences(of: "-latest", with: "").replacingOccurrences(of: "-recommended", with: "")
            guard mcVersion == gameVersion else { return nil }
            return ForgeVersion(
                version: value,
                installerURL: "https://files.minecraftforge.net/net/minecraftforge/forge/\(gameVersion)-\(value)/forge-\(gameVersion)-\(value)-installer.jar"
            )
        }
    }

    func installForge(gameVersion: String, forgeVersion: String? = nil, instance: LauncherInstance) async throws -> VersionMetadata {
        let versions = try await fetchVersions(gameVersion: gameVersion)
        guard let selected = versions.first else {
            throw ForgeInstallError.noVersionAvailable(gameVersion)
        }

        let baseMetadata = try readBaseMetadata(instance: instance, gameVersion: gameVersion)
        var metadata = baseMetadata
        metadata.id = "\(gameVersion)-forge-\(selected.version)"

        let versionDir = instance.rootDirectory
            .appendingPathComponent(".minecraft", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(metadata.id, isDirectory: true)
        try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
        try JSONEncoder.mmcl.encode(metadata).write(to: versionDir.appendingPathComponent("\(metadata.id).json"), options: .atomic)

        return metadata
    }

    private func readBaseMetadata(instance: LauncherInstance, gameVersion: String) throws -> VersionMetadata {
        let metadataURL = instance.rootDirectory
            .appendingPathComponent(".minecraft", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(gameVersion, isDirectory: true)
            .appendingPathComponent("\(gameVersion).json")
        guard let data = try? Data(contentsOf: metadataURL) else {
            throw ForgeInstallError.baseMetadataNotFound(gameVersion)
        }
        return try JSONDecoder.mmcl.decode(VersionMetadata.self, from: data)
    }
}

enum ForgeInstallError: LocalizedError, Equatable {
    case noVersionAvailable(String)
    case baseMetadataNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noVersionAvailable(let v): return "没有可用的 Forge 版本：Minecraft \(v)"
        case .baseMetadataNotFound(let v): return "缺少基础版本元数据：\(v)。请先安装原版 \(v)。"
        }
    }
}

protocol NeoForgeServicing {
    func fetchVersions(gameVersion: String) async throws -> [NeoForgeVersion]
    func installNeoForge(gameVersion: String, version: String?, instance: LauncherInstance) async throws -> VersionMetadata
}

struct NeoForgeService: NeoForgeServicing {
    let baseURL = URL(string: "https://maven.neoforged.net/releases/net/neoforged/neoforge")!

    func fetchVersions(gameVersion: String) async throws -> [NeoForgeVersion] {
        let url = URL(string: "https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let versions = json?["versions"] as? [String] ?? []
        return versions
            .filter { $0.hasPrefix(gameVersion + ".") }
            .map { NeoForgeVersion(version: $0, neoForgeVersion: $0.replacingOccurrences(of: "\(gameVersion).", with: "")) }
    }

    func installNeoForge(gameVersion: String, version: String? = nil, instance: LauncherInstance) async throws -> VersionMetadata {
        let versions = try await fetchVersions(gameVersion: gameVersion)
        guard let selected = versions.first else {
            throw NeoForgeInstallError.noVersionAvailable(gameVersion)
        }

        let baseMetadata = try readBaseMetadata(instance: instance, gameVersion: gameVersion)
        var metadata = baseMetadata
        metadata.id = "\(gameVersion)-neoforge-\(selected.version)"

        let versionDir = instance.rootDirectory
            .appendingPathComponent(".minecraft", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(metadata.id, isDirectory: true)
        try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
        try JSONEncoder.mmcl.encode(metadata).write(to: versionDir.appendingPathComponent("\(metadata.id).json"), options: .atomic)

        return metadata
    }

    private func readBaseMetadata(instance: LauncherInstance, gameVersion: String) throws -> VersionMetadata {
        let metadataURL = instance.rootDirectory
            .appendingPathComponent(".minecraft", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(gameVersion, isDirectory: true)
            .appendingPathComponent("\(gameVersion).json")
        guard let data = try? Data(contentsOf: metadataURL) else {
            throw NeoForgeInstallError.baseMetadataNotFound(gameVersion)
        }
        return try JSONDecoder.mmcl.decode(VersionMetadata.self, from: data)
    }
}

enum NeoForgeInstallError: LocalizedError, Equatable {
    case noVersionAvailable(String)
    case baseMetadataNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noVersionAvailable(let v): return "没有可用的 NeoForge 版本：Minecraft \(v)"
        case .baseMetadataNotFound(let v): return "缺少基础版本元数据：\(v)。请先安装原版 \(v)。"
        }
    }
}

protocol DiagnosticServicing {
    func javaMismatch(instance: LauncherInstance, runtime: JavaRuntime) -> DiagnosticReport?
    func analyzeLatestCrash(instance: LauncherInstance) -> DiagnosticReport?
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

    func analyzeLatestCrash(instance: LauncherInstance) -> DiagnosticReport? {
        let logURL = instance.rootDirectory.appendingPathComponent("logs/latest.log")
        guard let data = try? Data(contentsOf: logURL),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines)
        var crashLines: [String] = []
        var inCrash = false

        for line in lines {
            if line.contains("---- Minecraft Crash Report ----") || line.contains("java.lang.") && line.contains("Exception") {
                inCrash = true
            }
            if inCrash {
                crashLines.append(line)
                if crashLines.count > 50 { break }
            }
        }

        guard !crashLines.isEmpty else { return nil }

        let crashContent = crashLines.joined(separator: "\n")
        let summary: String
        if crashContent.contains("OutOfMemoryError") {
            summary = "内存不足。建议增加分配内存。"
        } else if crashContent.contains("ClassNotFound") || crashContent.contains("NoClassDefFoundError") {
            summary = "缺少依赖类。可能是 mod 版本不兼容或 loader 安装不完整。"
        } else if crashContent.contains("NoSuchMethod") {
            summary = "方法不存在。可能是 mod 与游戏版本不兼容。"
        } else {
            summary = "游戏崩溃，前 50 行日志已捕获。"
        }

        return DiagnosticReport(
            title: "游戏崩溃",
            severity: .error,
            summary: summary,
            suggestedActions: ["检查 mod 兼容性", "尝试移除最近安装的 mod", "查看完整崩溃日志"]
        )
    }
}

protocol AuthServicing {
    func startDeviceCodeFlow() async throws -> DeviceCodeResponse
    func pollForToken(deviceCode: String, interval: Int) async throws -> MicrosoftTokenResponse
    func exchangeForXBLToken(accessToken: String) async throws -> XboxTokenResponse
    func exchangeForXSTSToken(xblToken: String) async throws -> XBLXSTSResponse
    func exchangeForMinecraftToken(xstsToken: String) async throws -> MinecraftTokenResponse
    func fetchMinecraftProfile(accessToken: String) async throws -> MinecraftProfileResponse
    func refreshMicrosoftToken(refreshToken: String) async throws -> MicrosoftTokenResponse
}

struct AuthService: AuthServicing {
    let clientID = "16d660be-3984-44b0-a834-44be4a89d609"

    func startDeviceCodeFlow() async throws -> DeviceCodeResponse {
        let url = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "client_id=\(clientID)&scope=XboxLive.signin offline_access".data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }

    func pollForToken(deviceCode: String, interval: Int = 5) async throws -> MicrosoftTokenResponse {
        let url = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "client_id=\(clientID)&grant_type=urn:ietf:params:oauth:grant-type:device_code&device_code=\(deviceCode)".data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        while true {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as! HTTPURLResponse

            if httpResponse.statusCode == 200 {
                return try JSONDecoder().decode(MicrosoftTokenResponse.self, from: data)
            }

            let json = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            let error = json?["error"] ?? ""

            if error == "authorization_pending" {
                try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                continue
            } else if error == "authorization_declined" {
                throw AuthError.userDeclined
            } else if error == "expired_token" {
                throw AuthError.codeExpired
            } else {
                throw AuthError.tokenExchangeFailed(json?["error_description"] ?? error)
            }
        }
    }

    func exchangeForXBLToken(accessToken: String) async throws -> XboxTokenResponse {
        let url = URL(string: "https://user.auth.xboxlive.com/user/authenticate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body: [String: Any] = [
            "Properties": [
                "AuthMethod": "RPS",
                "SiteName": "user.auth.xboxlive.com",
                "RpsTicket": accessToken
            ],
            "RelyingParty": "http://auth.xboxlive.com",
            "TokenType": "JWT"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let token = json["Token"] as! String
        let expiresIn = (json["IssueAfter"] as? Int) ?? 3600
        return XboxTokenResponse(token: token, expiresInSeconds: expiresIn)
    }

    func exchangeForXSTSToken(xblToken: String) async throws -> XBLXSTSResponse {
        let url = URL(string: "https://xsts.auth.xboxlive.com/xsts/authorize")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body: [String: Any] = [
            "Properties": [
                "SandboxId": "RETAIL",
                "UserTokens": [xblToken]
            ],
            "RelyingParty": "rp://api.minecraftservices.com/",
            "TokenType": "JWT"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        if let token = json["Token"] as? String {
            return XBLXSTSResponse(token: token, expiresInSeconds: 3600)
        }
        let error = json["XErr"] as? Int ?? 0
        throw AuthError.xstsAuthFailed(error)
    }

    func exchangeForMinecraftToken(xstsToken: String) async throws -> MinecraftTokenResponse {
        let url = URL(string: "https://api.minecraftservices.com/authentication/login_with_xbox")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body = ["identityToken": "XBL3.0 x=\(xstsToken)"]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(MinecraftTokenResponse.self, from: data)
    }

    func fetchMinecraftProfile(accessToken: String) async throws -> MinecraftProfileResponse {
        let url = URL(string: "https://api.minecraftservices.com/minecraft/profile")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse
        guard httpResponse.statusCode == 200 else {
            throw AuthError.noMinecraftProfile
        }
        return try JSONDecoder().decode(MinecraftProfileResponse.self, from: data)
    }

    func refreshMicrosoftToken(refreshToken: String) async throws -> MicrosoftTokenResponse {
        let url = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = "client_id=\(clientID)&grant_type=refresh_token&refresh_token=\(refreshToken)&scope=XboxLive.signin offline_access".data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(MicrosoftTokenResponse.self, from: data)
    }
}

protocol CurseForgeServicing {
    func search(query: String, gameVersion: String?) async throws -> [CurseForgeSearchResult]
}

struct CurseForgeService: CurseForgeServicing {
    let baseURL = URL(string: "https://api.curseforge.com")!
    let apiKey = "$2a$10$bL4bIL5pUWqfcO7KQtnMReakwtfHbNKh6v1uTpKlzhwoueEJQnPnm"

    func search(query: String, gameVersion: String? = nil) async throws -> [CurseForgeSearchResult] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/v1/mods/search"), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "gameId", value: "432"),
            URLQueryItem(name: "searchFilter", value: query),
            URLQueryItem(name: "pageSize", value: "20")
        ]
        if let gv = gameVersion {
            queryItems.append(URLQueryItem(name: "gameVersion", value: gv))
        }
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "x-api-key")
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(CurseForgeSearchResponse.self, from: data)
        return response.data
    }
}

enum AuthError: LocalizedError, Equatable {
    case userDeclined
    case codeExpired
    case tokenExchangeFailed(String)
    case xstsAuthFailed(Int)
    case noMinecraftProfile

    var errorDescription: String? {
        switch self {
        case .userDeclined: return "登录已被拒绝。"
        case .codeExpired: return "设备代码已过期，请重试。"
        case .tokenExchangeFailed(let desc): return "令牌交换失败：\(desc)"
        case .xstsAuthFailed(let code): return "XSTS 认证失败（错误码 \(code)）。"
        case .noMinecraftProfile: return "此账号没有 Minecraft Profile。请确认已购买游戏。"
        }
    }
}
