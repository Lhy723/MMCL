import CryptoKit
import Foundation
import Network

protocol InstanceServicing {
    var rootDirectory: URL { get }
    var instancesDirectory: URL { get }
    func createInstance(
        name: String,
        gameVersion: String,
        loader: GameLoader,
        profile: LaunchProfile
    ) throws -> LauncherInstance
    func copyInstance(_ instance: LauncherInstance, name: String) throws -> LauncherInstance
    func loadAllInstances() throws -> [LauncherInstance]
    func instanceFileURL(for instance: LauncherInstance) -> URL
    func encode(_ instance: LauncherInstance) throws -> Data
    func decode(from data: Data) throws -> LauncherInstance
}

enum InstanceServiceError: LocalizedError, Equatable {
    case directoryAlreadyExists(URL)

    var errorDescription: String? {
        switch self {
        case .directoryAlreadyExists(let directory):
            return "实例目录已存在：\(directory.path)"
        }
    }
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
        let instanceID = UUID()
        let instanceRoot = instancesDirectory.appendingPathComponent(instanceID.uuidString, isDirectory: true)
        let instance = LauncherInstance(
            id: instanceID,
            name: name,
            gameVersion: gameVersion,
            loader: loader,
            rootDirectory: instanceRoot,
            profile: profile,
            status: .notInstalled
        )

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: instancesDirectory, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: instanceRoot.path) else {
            throw InstanceServiceError.directoryAlreadyExists(instanceRoot)
        }

        try fileManager.createDirectory(at: instanceRoot, withIntermediateDirectories: false)
        do {
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
        } catch {
            try? fileManager.removeItem(at: instanceRoot)
            throw error
        }

        return instance
    }

    func copyInstance(_ instance: LauncherInstance, name: String) throws -> LauncherInstance {
        let copyID = UUID()
        let copyRoot = instancesDirectory.appendingPathComponent(copyID.uuidString, isDirectory: true)
        let copy = LauncherInstance(
            id: copyID,
            name: name,
            gameVersion: instance.gameVersion,
            loader: instance.loader,
            rootDirectory: copyRoot,
            profile: instance.profile,
            status: instance.status,
            lastPlayedAt: instance.lastPlayedAt,
            launchVersionID: instance.effectiveLaunchVersionID
        )

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: instancesDirectory, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: copyRoot.path) else {
            throw InstanceServiceError.directoryAlreadyExists(copyRoot)
        }

        do {
            try fileManager.copyItem(at: instance.rootDirectory, to: copyRoot)
            try encode(copy).write(to: instanceFileURL(for: copy), options: .atomic)
            return copy
        } catch {
            try? fileManager.removeItem(at: copyRoot)
            throw error
        }
    }

    func loadAllInstances() throws -> [LauncherInstance] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: instancesDirectory.path) else { return [] }
        let contents = try fileManager.contentsOfDirectory(
            at: instancesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var instances: [LauncherInstance] = []
        for dir in contents {
            let fileURL = dir.appendingPathComponent("instance.json")
            guard fileManager.fileExists(atPath: fileURL.path) else { continue }
            let data = try Data(contentsOf: fileURL)
            var instance = try decode(from: data)
            if instance.launchVersionID != instance.effectiveLaunchVersionID {
                instance.launchVersionID = instance.effectiveLaunchVersionID
                try? encode(instance).write(to: fileURL, options: .atomic)
            }
            instances.append(instance)
        }
        return instances
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

    // Kept for compatibility with legacy callers. New instance directories use UUIDs.
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
    var onCancelled: ((UUID) -> Void)? { get set }

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
        source: DownloadSource,
        taskGroupID: UUID?,
        taskGroupName: String?
    ) -> [DownloadJob]
    func prepareNativeLibraries(metadata: VersionMetadata, instance: LauncherInstance) throws -> [URL]
    func validateLoaderInstallation(metadata: VersionMetadata, instance: LauncherInstance) throws
    func startDownload(_ job: DownloadJob)
    func pauseDownload(id: UUID)
    func resumeDownload(id: UUID)
    func cancelDownload(id: UUID)
    func cancelAllDownloads()
}

final class DownloadService: NSObject, DownloadServicing, URLSessionDownloadDelegate {
    var onProgress: ((UUID, Int64) -> Void)?
    var onComplete: ((UUID, DownloadJob) -> Void)?
    var onError: ((UUID, Error) -> Void)?
    var onCancelled: ((UUID) -> Void)?

    private var session: URLSession!
    private let lock = NSLock()
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
        lock.lock()
        jobsByID[job.id] = runningJob
        lock.unlock()

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
                            try? FileManager.default.removeItem(at: job.destination)
                            var failedJob = job
                            failedJob.status = .failed
                            self.lock.lock()
                            self.jobsByID[job.id] = failedJob
                            self.lock.unlock()
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
                    self.lock.lock()
                    self.jobsByID[job.id] = completedJob
                    self.lock.unlock()
                    self.onComplete?(job.id, completedJob)
                } catch {
                    var failedJob = job
                    failedJob.status = .failed
                    self.lock.lock()
                    self.jobsByID[job.id] = failedJob
                    self.lock.unlock()
                    self.onError?(job.id, error)
                }
            }
            return
        }

        let task: URLSessionDownloadTask
        lock.lock()
        let resumeData = resumeDataMap.removeValue(forKey: job.id)
        lock.unlock()
        if let resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            task = session.downloadTask(with: remoteURL)
        }
        task.taskDescription = job.id.uuidString
        lock.lock()
        activeTasks[job.id] = task
        lock.unlock()
        task.resume()
    }

    func pauseDownload(id: UUID) {
        lock.lock()
        let task = activeTasks[id]
        if task != nil {
            activeTasks.removeValue(forKey: id)
            if var job = jobsByID[id] {
                job.status = .paused
                jobsByID[id] = job
            }
        }
        lock.unlock()
        guard let task else { return }
        task.cancel { [weak self] data in
            if let data, let self {
                self.lock.lock()
                self.resumeDataMap[id] = data
                self.lock.unlock()
            }
        }
    }

    func resumeDownload(id: UUID) {
        lock.lock()
        guard var job = jobsByID[id], job.status == .paused else {
            lock.unlock()
            return
        }
        job.status = .queued
        jobsByID[id] = job
        lock.unlock()
        startDownload(job)
    }

    func cancelDownload(id: UUID) {
        lock.lock()
        let task = activeTasks[id]
        activeTasks.removeValue(forKey: id)
        resumeDataMap.removeValue(forKey: id)
        var shouldNotifyWithoutTask = false
        if var job = jobsByID[id], job.status.isActive {
            job.status = .failed
            jobsByID[id] = job
            shouldNotifyWithoutTask = task == nil
        }
        lock.unlock()
        task?.cancel()
        if shouldNotifyWithoutTask {
            onCancelled?(id)
        }
    }

    func cancelAllDownloads() {
        lock.lock()
        let tasks = Array(activeTasks.values)
        activeTasks.removeAll()
        resumeDataMap.removeAll()
        for (id, _) in jobsByID {
            if var job = jobsByID[id], job.status.isActive {
                job.status = .failed
                jobsByID[id] = job
            }
        }
        lock.unlock()
        for task in tasks {
            task.cancel()
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

        let groupID = UUID()
        let groupName = "安装 Minecraft \(metadata.id)"

        var jobs: [DownloadJob] = [
            DownloadJob(
                title: "Minecraft \(metadata.id) 客户端",
                source: source,
                remoteURL: metadata.downloads.client.url,
                destination: versionDirectory.appendingPathComponent("\(metadata.id).jar"),
                sha1: metadata.downloads.client.sha1,
                totalBytes: metadata.downloads.client.size,
                taskGroupID: groupID,
                taskGroupName: groupName
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
                totalBytes: metadata.assetIndex.size,
                taskGroupID: groupID,
                taskGroupName: groupName
            )
        ]

        let libraryJobs = metadata.libraries.compactMap { library -> DownloadJob? in
            guard let artifact = library.artifact else { return nil }
            guard artifact.url != generatedLoaderArtifactURL,
                  !artifact.url.absoluteString.isEmpty
            else { return nil }
            return DownloadJob(
                title: library.name,
                source: source,
                remoteURL: artifact.url,
                destination: minecraftDirectory
                    .appendingPathComponent("libraries", isDirectory: true)
                    .appendingPathComponent(artifact.path),
                sha1: artifact.sha1.isEmpty ? nil : artifact.sha1,
                totalBytes: artifact.size,
                taskGroupID: groupID,
                taskGroupName: groupName
            )
        }

        jobs.append(contentsOf: libraryJobs)
        let nativeJobs = metadata.libraries.compactMap { library -> DownloadJob? in
            guard let artifact = library.nativeArtifact() else { return nil }
            guard artifact.url != generatedLoaderArtifactURL,
                  !artifact.url.absoluteString.isEmpty
            else { return nil }
            return DownloadJob(
                title: "\(library.name) native",
                source: source,
                remoteURL: artifact.url,
                destination: minecraftDirectory
                    .appendingPathComponent("libraries", isDirectory: true)
                    .appendingPathComponent(artifact.path),
                sha1: artifact.sha1.isEmpty ? nil : artifact.sha1,
                totalBytes: artifact.size,
                taskGroupID: groupID,
                taskGroupName: groupName
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
            .filter { job in
                guard FileManager.default.fileExists(atPath: job.destination.path) else {
                    return true
                }
                guard let expectedSHA1 = job.sha1 else {
                    return false
                }
                guard let data = try? Data(contentsOf: job.destination) else {
                    return true
                }
                let actualSHA1 = Self.sha1Hex(for: data)
                return actualSHA1.caseInsensitiveCompare(expectedSHA1) != .orderedSame
            }
    }

    func makeAssetObjectJobs(
        assetIndex: AssetIndex,
        instance: LauncherInstance,
        source: DownloadSource,
        taskGroupID: UUID? = nil,
        taskGroupName: String? = nil
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
                    totalBytes: object.size,
                    taskGroupID: taskGroupID,
                    taskGroupName: taskGroupName
                )
            }
    }

    func prepareNativeLibraries(metadata: VersionMetadata, instance: LauncherInstance) throws -> [URL] {
        let minecraftDirectory = instance.rootDirectory.appendingPathComponent(".minecraft", isDirectory: true)
        let librariesDirectory = minecraftDirectory.appendingPathComponent("libraries", isDirectory: true)
        let nativesDirectory = minecraftDirectory
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(instance.effectiveLaunchVersionID, isDirectory: true)
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

    func validateLoaderInstallation(metadata: VersionMetadata, instance: LauncherInstance) throws {
        try validateLoaderMetadata(metadata, loader: instance.loader)
        guard instance.loader != .vanilla else { return }
        guard let artifact = metadata.coreLibrary(for: instance.loader)?.artifact else {
            throw LoaderInstallationError.missingCoreLibraryMetadata(instance.loader)
        }
        let coreLibraryURL = instance.rootDirectory
            .appendingPathComponent(".minecraft", isDirectory: true)
            .appendingPathComponent("libraries", isDirectory: true)
            .appendingPathComponent(artifact.path)
        guard FileManager.default.fileExists(atPath: coreLibraryURL.path) else {
            throw LoaderInstallationError.missingCoreLibraryFile(coreLibraryURL)
        }
        try validateGeneratedLoaderArtifacts(
            metadata.libraries,
            minecraftDirectory: instance.rootDirectory.appendingPathComponent(".minecraft", isDirectory: true)
        )
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
              let jobID = UUID(uuidString: uuidString) else { return }

        lock.lock()
        guard var job = jobsByID[jobID] else {
            lock.unlock()
            return
        }
        activeTasks.removeValue(forKey: jobID)
        lock.unlock()

        let parentDirectory = job.destination.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: job.destination.path) {
                try FileManager.default.removeItem(at: job.destination)
            }
            try FileManager.default.moveItem(at: location, to: job.destination)
        } catch {
            job.status = .failed
            lock.lock()
            jobsByID[jobID] = job
            lock.unlock()
            onError?(jobID, error)
            return
        }

        if let expectedSHA1 = job.sha1 {
            if let data = try? Data(contentsOf: job.destination) {
                let actualSHA1 = Self.sha1Hex(for: data)
                if actualSHA1.caseInsensitiveCompare(expectedSHA1) != .orderedSame {
                    try? FileManager.default.removeItem(at: job.destination)
                    job.status = .failed
                    lock.lock()
                    jobsByID[jobID] = job
                    lock.unlock()
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
        lock.lock()
        jobsByID[jobID] = job
        lock.unlock()
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

        lock.lock()
        if var job = jobsByID[jobID] {
            job.completedBytes = totalBytesWritten
            if totalBytesExpectedToWrite > 0 {
                job.totalBytes = totalBytesExpectedToWrite
            }
            jobsByID[jobID] = job
        }
        lock.unlock()
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

        lock.lock()
        activeTasks.removeValue(forKey: jobID)

        if let error {
            if (error as NSError).code == NSURLErrorCancelled {
                let wasPaused = jobsByID[jobID]?.status == .paused
                lock.unlock()
                if !wasPaused {
                    onCancelled?(jobID)
                }
                return
            }
            if var job = jobsByID[jobID] {
                job.status = .failed
                jobsByID[jobID] = job
            }
            lock.unlock()
            onError?(jobID, error)
        } else {
            lock.unlock()
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

protocol SkinServicing {
    func scanSkins(in directory: URL) -> [SkinInfo]
    func applySkin(_ skin: SkinInfo, to account: MinecraftAccount) throws
    func importSkin(from sourceURL: URL, name: String, model: SkinInfo.SkinModel) throws -> SkinInfo
    func skinDirectory(for account: MinecraftAccount) -> URL
}

struct SkinService: SkinServicing {
    let applicationSupportDirectory: URL

    init(applicationSupportDirectory: URL? = nil) {
        self.applicationSupportDirectory = applicationSupportDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
    }

    func skinDirectory(for account: MinecraftAccount) -> URL {
        applicationSupportDirectory
            .appendingPathComponent("MMCL", isDirectory: true)
            .appendingPathComponent("Skins", isDirectory: true)
            .appendingPathComponent(account.uuid, isDirectory: true)
    }

    func scanSkins(in directory: URL) -> [SkinInfo] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "png" }
            .compactMap { url in
                let name = url.deletingPathExtension().lastPathComponent
                let model: SkinInfo.SkinModel = name.lowercased().contains("alex") ? .alex : .steve
                return SkinInfo(name: name, model: model, localFileURL: url)
            }
    }

    func applySkin(_ skin: SkinInfo, to account: MinecraftAccount) throws {
        // Skin application happens at launch via JVM arguments
        // Store the skin info in the account's profile
    }

    func importSkin(from sourceURL: URL, name: String, model: SkinInfo.SkinModel) throws -> SkinInfo {
        let destDir = applicationSupportDirectory
            .appendingPathComponent("MMCL", isDirectory: true)
            .appendingPathComponent("Skins", isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let destURL = destDir.appendingPathComponent("\(name).png")
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        return SkinInfo(name: name, model: model, localFileURL: destURL)
    }
}

protocol PortableJDKInstalling {
    func install(
        majorVersion: Int,
        architecture: String,
        targetDirectory: URL
    ) async throws
}

enum PortableJDKInstallError: LocalizedError, Equatable {
    case invalidHTTPResponse
    case httpStatus(Int)
    case tarLaunchFailed(String)
    case tarFailed(Int32, String)
    case missingJavaExecutable(URL)

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "JDK 下载返回了无效的 HTTP 响应。"
        case .httpStatus(let statusCode):
            return "JDK 下载失败：HTTP \(statusCode)。"
        case .tarLaunchFailed(let detail):
            return "无法启动 tar 解压程序：\(detail)"
        case .tarFailed(let status, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "JDK 解压失败：tar 退出码 \(status)。"
                : "JDK 解压失败：tar 退出码 \(status)：\(detail)"
        case .missingJavaExecutable(let stagingDirectory):
            return "JDK 解压完成但缺少可执行的 bin/java：\(stagingDirectory.path)"
        }
    }
}

struct PortableJDKInstaller: PortableJDKInstalling {
    typealias Downloader = (URL) async throws -> (URL, URLResponse)

    private let downloader: Downloader

    init() {
        downloader = { url in
            try await URLSession.shared.download(from: url)
        }
    }

    init(downloader: @escaping Downloader) {
        self.downloader = downloader
    }

    func install(
        majorVersion: Int,
        architecture: String,
        targetDirectory: URL
    ) async throws {
        let downloadURL = URL(string: "https://api.adoptium.net/v3/binary/latest/\(majorVersion)/ga/mac/\(architecture)/jdk/hotspot/normal/eclipse?project=jdk")!
        let (temporaryURL, response) = try await downloader(downloadURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PortableJDKInstallError.invalidHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PortableJDKInstallError.httpStatus(httpResponse.statusCode)
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        let identifier = UUID().uuidString
        let stagingDirectory = targetDirectory
            .appendingPathComponent(".jdk-install-\(identifier)", isDirectory: true)
        let archiveURL = targetDirectory.appendingPathComponent(".jdk-\(identifier).tar.gz")
        var movedItems: [URL] = []
        var installationSucceeded = false

        defer {
            if !installationSucceeded {
                for item in movedItems.reversed() {
                    try? fileManager.removeItem(at: item)
                }
            }
            try? fileManager.removeItem(at: archiveURL)
            try? fileManager.removeItem(at: stagingDirectory)
        }

        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try fileManager.copyItem(at: temporaryURL, to: archiveURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["xzf", archiveURL.path, "-C", stagingDirectory.path]
        process.standardOutput = FileHandle.nullDevice
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            throw PortableJDKInstallError.tarLaunchFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        let stderr = String(
            decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        guard process.terminationStatus == 0 else {
            throw PortableJDKInstallError.tarFailed(process.terminationStatus, stderr)
        }

        guard let javaExecutable = findJavaExecutable(in: stagingDirectory),
              fileManager.isExecutableFile(atPath: javaExecutable.path)
        else {
            throw PortableJDKInstallError.missingJavaExecutable(stagingDirectory)
        }

        let extractedItems = try fileManager.contentsOfDirectory(
            at: stagingDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for item in extractedItems {
            let destination = targetDirectory.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: item, to: destination)
            movedItems.append(destination)
        }
        installationSucceeded = true
    }

    private func findJavaExecutable(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for case let url as URL in enumerator
        where url.lastPathComponent == "java"
            && url.deletingLastPathComponent().lastPathComponent == "bin" {
            return url
        }
        return nil
    }
}

protocol JavaRuntimeServicing {
    func bundledSearchLocations() -> [URL]
    func recommendedMajorVersion(for gameVersion: String) -> Int
    func parseJavaHomeVerboseOutput(_ output: String) -> [JavaRuntime]
    func discoverInstalledRuntimes() async throws -> [JavaRuntime]
    var portableJDKDirectory: URL { get }
}

struct JavaRuntimeService: JavaRuntimeServicing {
    var javaHomeExecutable: URL = URL(fileURLWithPath: "/usr/libexec/java_home")

    var portableJDKDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MMCL/JDK", isDirectory: true)
    }

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
        var runtimes = await discoverViaJavaHome()
        runtimes.append(contentsOf: discoverSDKMAN())
        runtimes.append(contentsOf: discoverJetBrainsJREs())
        runtimes.append(contentsOf: discoverHomebrewJDKs())
        runtimes.append(contentsOf: discoverPortableJDKs())

        var seen = Set<String>()
        return runtimes.filter { runtime in
            let key = runtime.executableURL.path
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func discoverViaJavaHome() async -> [JavaRuntime] {
        let process = Process()
        process.executableURL = javaHomeExecutable
        process.arguments = ["-V"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        return parseJavaHomeVerboseOutput(output)
    }

    private func discoverSDKMAN() -> [JavaRuntime] {
        let sdkmanDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".sdkman/candidates/java", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sdkmanDir.path) else { return [] }
        return scanJavaDirectories(under: sdkmanDir, source: "SDKMAN!")
    }

    private func discoverJetBrainsJREs() -> [JavaRuntime] {
        let appsDir = URL(fileURLWithPath: "/Applications")
        guard let apps = try? FileManager.default.contentsOfDirectory(
            at: appsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }

        var runtimes: [JavaRuntime] = []
        for app in apps where app.pathExtension == "app" {
            for subpath in ["Contents/jbr/Contents/Home", "Contents/jre/Contents/Home"] {
                let home = app.appendingPathComponent(subpath, isDirectory: true)
                let javaBin = home.appendingPathComponent("bin/java")
                if FileManager.default.fileExists(atPath: javaBin.path) {
                    let name = app.deletingPathExtension().lastPathComponent
                    if let runtime = parseJavaHome(home: home, name: "JetBrains Runtime (\(name))") {
                        runtimes.append(runtime)
                    }
                }
            }
        }
        return runtimes
    }

    private func discoverHomebrewJDKs() -> [JavaRuntime] {
        let prefix = URL(fileURLWithPath: "/opt/homebrew/opt")
        let prefixX86 = URL(fileURLWithPath: "/usr/local/opt")
        var runtimes: [JavaRuntime] = []
        for optDir in [prefix, prefixX86] {
            let javaLink = optDir.appendingPathComponent("java/bin/java")
            if FileManager.default.fileExists(atPath: javaLink.path),
               let runtime = parseJavaHome(
                home: javaLink.deletingLastPathComponent().deletingLastPathComponent(),
                name: "Homebrew java"
               ) {
                runtimes.append(runtime)
            }

            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: optDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for item in contents
            where item.lastPathComponent == "openjdk" || item.lastPathComponent.hasPrefix("openjdk@") {
                let home = item.appendingPathComponent("libexec/openjdk.jdk/Contents/Home", isDirectory: true)
                if FileManager.default.fileExists(atPath: home.appendingPathComponent("bin/java").path) {
                    if let runtime = parseJavaHome(home: home, name: "Homebrew \(item.lastPathComponent)") {
                        runtimes.append(runtime)
                    }
                }
            }
        }
        return runtimes
    }

    private func discoverPortableJDKs() -> [JavaRuntime] {
        let dir = portableJDKDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents.compactMap { item in
            // Adoptium extracts to jdk-X.Y.Z+NN directory
            let home: URL
            if item.lastPathComponent.contains("jdk-") {
                home = item
            } else {
                // Try Contents/Home for .app bundles
                let appHome = item.appendingPathComponent("Contents/Home", isDirectory: true)
                if FileManager.default.fileExists(atPath: appHome.appendingPathComponent("bin/java").path) {
                    home = appHome
                } else {
                    home = item
                }
            }
            let javaBin = home.appendingPathComponent("bin/java")
            guard FileManager.default.fileExists(atPath: javaBin.path) else { return nil }
            return parseJavaHome(home: home, name: "便携版 \(item.lastPathComponent)")
        }
    }

    private func scanJavaDirectories(under directory: URL, source: String) -> [JavaRuntime] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents.compactMap { item in
            let home = item
            let javaBin = home.appendingPathComponent("bin/java")
            guard FileManager.default.fileExists(atPath: javaBin.path) else { return nil }
            return parseJavaHome(home: home, name: "\(source) \(item.lastPathComponent)")
        }
    }

    private func parseJavaHome(home: URL, name: String) -> JavaRuntime? {
        let javaBin = home.appendingPathComponent("bin/java")
        let process = Process()
        process.executableURL = javaBin
        process.arguments = ["-version"]
        let errPipe = Pipe()
        process.standardError = errPipe
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        let pattern = #"openjdk version "([0-9]+(?:\.[0-9]+)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let versionRange = Range(match.range(at: 1), in: output)
        else { return nil }

        let version = String(output[versionRange])
        let majorVersion = Int(version.split(separator: ".").first ?? "") ?? 0

        let arch = RuntimeArchitecture.detect(from: javaBin)

        return JavaRuntime(
            name: name,
            version: version,
            majorVersion: majorVersion,
            architecture: arch,
            executableURL: javaBin
        )
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
    func previewCommand(for instance: LauncherInstance, java: JavaRuntime, account: MinecraftAccount) -> [String]
    func preflight(instance: LauncherInstance, java: JavaRuntime, account: MinecraftAccount) -> LaunchPreflightReport
    func launch(instance: LauncherInstance, java: JavaRuntime, account: MinecraftAccount) throws -> LaunchSession
}

struct LaunchService: LaunchServicing {
    // Keep the original convenience overloads for callers that have not
    // introduced account selection yet. They intentionally use the existing
    // offline behavior; the LaunchServicing protocol itself requires an
    // explicit account.
    func previewCommand(for instance: LauncherInstance, java: JavaRuntime) -> [String] {
        previewCommand(
            for: instance,
            java: java,
            account: MinecraftAccount(username: instance.profile.offlineUsername, type: .offline)
        )
    }

    func preflight(instance: LauncherInstance, java: JavaRuntime) -> LaunchPreflightReport {
        preflight(
            instance: instance,
            java: java,
            account: MinecraftAccount(username: instance.profile.offlineUsername, type: .offline)
        )
    }

    func launch(instance: LauncherInstance, java: JavaRuntime) throws -> LaunchSession {
        try launch(
            instance: instance,
            java: java,
            account: MinecraftAccount(username: instance.profile.offlineUsername, type: .offline)
        )
    }

    func previewCommand(for instance: LauncherInstance, java: JavaRuntime, account: MinecraftAccount) -> [String] {
        redactedCommand(
            buildCommand(for: instance, java: java, account: account),
            account: account
        )
    }

    private func buildCommand(
        for instance: LauncherInstance,
        java: JavaRuntime,
        account: MinecraftAccount
    ) -> [String] {
        let minecraftDirectory = instance.rootDirectory.appendingPathComponent(".minecraft", isDirectory: true)
        let launchVersionID = instance.effectiveLaunchVersionID
        let versionDirectory = minecraftDirectory
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(launchVersionID, isDirectory: true)
        let nativesDirectory = versionDirectory.appendingPathComponent("natives", isDirectory: true)
        let clientJar = versionDirectory.appendingPathComponent("\(launchVersionID).jar")
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
            assetIndex: assetIndex,
            account: account
        )

        let userJVMArguments = effectiveUserJVMArguments(for: instance.profile)

        if let metadata, let arguments = metadata.arguments {
            let versionJVMArguments = expand(arguments.jvm, substitutions: substitutions, operatingSystem: "osx")
            let gameArguments = expand(arguments.game, substitutions: substitutions, operatingSystem: "osx")
            let jvmArguments = buildJVMArguments(
                instance: instance,
                java: java,
                minecraftDirectory: minecraftDirectory,
                nativesDirectory: nativesDirectory,
                versionArguments: versionJVMArguments,
                userArguments: userJVMArguments
            )

            return [java.executableURL.path] + jvmArguments + [mainClass] + gameArguments
        }

        if let metadata, let legacyArguments = metadata.minecraftArguments {
            let jvmArguments = buildJVMArguments(
                instance: instance,
                java: java,
                minecraftDirectory: minecraftDirectory,
                nativesDirectory: nativesDirectory,
                versionArguments: ["-cp", classpath],
                userArguments: userJVMArguments
            )

            return [java.executableURL.path]
                + jvmArguments
                + [mainClass]
                + expandLegacyArguments(legacyArguments, substitutions: substitutions)
        }

        let jvmArguments = buildJVMArguments(
            instance: instance,
            java: java,
            minecraftDirectory: minecraftDirectory,
            nativesDirectory: nativesDirectory,
            versionArguments: ["-cp", classpath],
            userArguments: userJVMArguments
        )
        let fallbackGameArguments = [
            "--username",
            substitutions["auth_player_name"] ?? instance.profile.offlineUsername,
            "--version",
            launchVersionID,
            "--gameDir",
            minecraftDirectory.path,
            "--assetsDir",
            minecraftDirectory.appendingPathComponent("assets", isDirectory: true).path,
            "--assetIndex",
            assetIndex,
            "--accessToken",
            substitutions["auth_access_token"] ?? "0",
            "--uuid",
            substitutions["auth_uuid"] ?? "00000000000000000000000000000000",
            "--xuid",
            substitutions["auth_xuid"] ?? "",
            "--userType",
            substitutions["user_type"] ?? "legacy"
        ]

        return [java.executableURL.path] + jvmArguments + [mainClass] + fallbackGameArguments
    }

    private func buildJVMArguments(
        instance: LauncherInstance,
        java: JavaRuntime,
        minecraftDirectory: URL,
        nativesDirectory: URL,
        versionArguments: [String],
        userArguments: [String]
    ) -> [String] {
        JVMArgumentBuilder().build(
            JVMArgumentBuildContext(
                javaMajorVersion: java.majorVersion,
                javaArchitecture: java.architecture,
                memoryMegabytes: instance.profile.memoryMegabytes,
                nativeDirectory: nativesDirectory,
                gameDirectory: minecraftDirectory,
                versionArguments: versionArguments,
                userArguments: userArguments,
                useGeneratedArguments: instance.profile.useGeneratedJVMArguments,
                useOptimizingArguments: instance.profile.useOptimizingJVMArguments,
                isMacOS: true,
                launcherName: "MMCL"
            )
        )
    }

    private var launcherVersion: String {
        (Bundle(identifier: "melody.MMCL") ?? Bundle.main)
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.2"
    }

    private func effectiveUserJVMArguments(for profile: LaunchProfile) -> [String] {
        // Profiles created before the layered builder stored these two values
        // as if they were user input. Treat that exact pair as the old
        // automatic default so existing instances receive the complete set of
        // generated defaults after upgrading.
        let legacyAutomaticDefaults = ["-XX:+UseG1GC", "-XX:+UnlockExperimentalVMOptions"]
        if profile.useGeneratedJVMArguments, profile.jvmArguments == legacyAutomaticDefaults {
            return []
        }
        return profile.jvmArguments
    }

    func preflight(
        instance: LauncherInstance,
        java: JavaRuntime,
        account: MinecraftAccount
    ) -> LaunchPreflightReport {
        let fileManager = FileManager.default
        let minecraftDirectory = instance.rootDirectory.appendingPathComponent(".minecraft", isDirectory: true)
        let launchVersionID = instance.effectiveLaunchVersionID
        let versionDirectory = minecraftDirectory
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(launchVersionID, isDirectory: true)
        let metadataURL = versionDirectory.appendingPathComponent("\(launchVersionID).json")
        var blockingIssues: [String] = []
        var warnings: [String] = []
        var actions: [String] = []

        if account.type == .microsoft {
            if account.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blockingIssues.append("Microsoft 账号缺少 Minecraft 用户名。")
            }
            if account.uuid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blockingIssues.append("Microsoft 账号缺少 Minecraft UUID。")
            }
            if account.accessToken.isEmpty {
                blockingIssues.append("Microsoft 账号缺少 Minecraft Access Token。")
            }
            if account.xuid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blockingIssues.append("Microsoft 账号缺少 XUID，请重新登录 Microsoft 账号。")
            }
            if !blockingIssues.isEmpty {
                actions.append("重新登录 Microsoft 账号")
            }
        }

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

        do {
            try validateLoaderMetadata(metadata, loader: instance.loader)
        } catch {
            blockingIssues.append(error.localizedDescription)
            actions.append("重新生成加载器安装计划")
        }

        let clientJar = versionDirectory.appendingPathComponent("\(launchVersionID).jar")
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
        assetIndex: String,
        account: MinecraftAccount
    ) -> [String: String] {
        let isMicrosoftAccount = account.type == .microsoft
        return [
            "auth_player_name": isMicrosoftAccount ? account.username : instance.profile.offlineUsername,
            "version_name": instance.effectiveLaunchVersionID,
            "game_directory": minecraftDirectory.path,
            "assets_root": minecraftDirectory.appendingPathComponent("assets", isDirectory: true).path,
            "assets_index_name": assetIndex,
            "library_directory": minecraftDirectory.appendingPathComponent("libraries", isDirectory: true).path,
            "classpath_separator": ":",
            "auth_uuid": isMicrosoftAccount ? account.uuid : "00000000000000000000000000000000",
            "auth_access_token": isMicrosoftAccount ? account.accessToken : "0",
            "clientid": "",
            "auth_xuid": isMicrosoftAccount ? account.xuid : "",
            "user_type": isMicrosoftAccount ? "msa" : "legacy",
            "version_type": "release",
            "natives_directory": nativesDirectory.path,
            "launcher_name": "MMCL",
            "launcher_version": launcherVersion,
            "classpath": classpath,
            "resolution_width": String(instance.profile.resolutionWidth),
            "resolution_height": String(instance.profile.resolutionHeight)
        ]
    }

    private func redactedCommand(_ command: [String], account: MinecraftAccount) -> [String] {
        guard account.type == .microsoft, !account.accessToken.isEmpty else {
            return command
        }

        return command.map { argument in
            argument.replacingOccurrences(of: account.accessToken, with: "<redacted>")
        }
    }

    private func replacePlaceholders(in value: String, substitutions: [String: String]) -> String {
        substitutions.reduce(value) { result, item in
            result.replacingOccurrences(of: "${\(item.key)}", with: item.value)
        }
    }

    private func localVersionMetadata(for instance: LauncherInstance) -> VersionMetadata? {
        let launchVersionID = instance.effectiveLaunchVersionID
        let metadataURL = instance.rootDirectory
            .appendingPathComponent(".minecraft", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(launchVersionID, isDirectory: true)
            .appendingPathComponent("\(launchVersionID).json")
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

    func launch(
        instance: LauncherInstance,
        java: JavaRuntime,
        account: MinecraftAccount
    ) throws -> LaunchSession {
        let command = buildCommand(for: instance, java: java, account: account)
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
            command: redactedCommand(command, account: account),
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
    func search(query: String, facets: [[String]]?, index: String, offset: Int) async throws -> ModrinthSearchResponse
    func fetchProject(id: String) async throws -> ModrinthProject
    func fetchVersions(projectID: String, gameVersion: String?, loader: String?) async throws -> [ModrinthVersion]
    func downloadFile(from urlString: String, to destination: URL) async throws
}

struct ModrinthService: ModrinthServicing {
    let baseURL = URL(string: "https://api.modrinth.com/v2")!
    let userAgent = "MMCL/1.0 (https://github.com/Lhy723/MMCL)"

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://github.com/Lhy723/MMCL", forHTTPHeaderField: "Referer")
        return request
    }

    func search(query: String, facets: [[String]]? = nil, index: String = "relevance", offset: Int = 0) async throws -> ModrinthSearchResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "query", value: query)]
        if let facets {
            let encoded = try JSONEncoder().encode(facets)
            let facetString = String(data: encoded, encoding: .utf8)!
            queryItems.append(URLQueryItem(name: "facets", value: facetString))
        }
        queryItems.append(URLQueryItem(name: "limit", value: "20"))
        queryItems.append(URLQueryItem(name: "index", value: index))
        if offset > 0 {
            queryItems.append(URLQueryItem(name: "offset", value: "\(offset)"))
        }
        components.queryItems = queryItems
        let request = makeRequest(url: components.url!)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ModrinthError.searchFailed("HTTP \(http.statusCode)")
        }
        return try JSONDecoder.mmcl.decode(ModrinthSearchResponse.self, from: data)
    }

    func fetchProject(id: String) async throws -> ModrinthProject {
        let url = baseURL.appendingPathComponent("project/\(id)")
        let request = makeRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)
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
        let request = makeRequest(url: components.url!)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder.mmcl.decode([ModrinthVersion].self, from: data)
    }

    func downloadFile(from urlString: String, to destination: URL) async throws {
        guard let url = URL(string: urlString) else {
            throw ModrinthError.invalidURL(urlString)
        }
        let request = makeRequest(url: url)
        let (data, _) = try await URLSession.shared.data(for: request)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }
}

enum ModrinthError: LocalizedError, Equatable {
    case invalidURL(String)
    case searchFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "无效的下载地址：\(url)"
        case .searchFailed(let detail):
            return "Modrinth 搜索失败：\(detail)"
        }
    }
}

private let generatedLoaderArtifactURL = URL(string: "mmcl-generated://artifact")!

private struct InstallerVersionArtifact: Decodable {
    var path: String
    var url: URL
    var sha1: String
    var size: Int64

    private enum CodingKeys: String, CodingKey {
        case path
        case url
        case sha1
        case size
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        let urlString = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        url = URL(string: urlString) ?? generatedLoaderArtifactURL
        sha1 = try container.decodeIfPresent(String.self, forKey: .sha1) ?? ""
        size = try container.decodeIfPresent(Int64.self, forKey: .size) ?? 0
    }
}

private struct InstallerVersionLibrary: Decodable {
    struct Downloads: Decodable {
        var artifact: InstallerVersionArtifact?
        var classifiers: [String: InstallerVersionArtifact]?
    }

    var name: String
    var natives: [String: String]?
    var downloads: Downloads?

    var metadata: VersionMetadata.Library {
        VersionMetadata.Library(
            name: name,
            natives: natives,
            downloads: downloads.map {
                VersionMetadata.Library.Downloads(
                    artifact: $0.artifact.map {
                        VersionMetadata.Library.Artifact(
                            path: $0.path,
                            url: $0.url,
                            sha1: $0.sha1,
                            size: $0.size
                        )
                    },
                    classifiers: $0.classifiers?.mapValues {
                        VersionMetadata.Library.Artifact(
                            path: $0.path,
                            url: $0.url,
                            sha1: $0.sha1,
                            size: $0.size
                        )
                    }
                )
            }
        )
    }
}

struct InstallerVersionProfile: Decodable {
    var id: String?
    var inheritsFrom: String?
    var mainClass: String?
    var libraries: [VersionMetadata.Library]?
    var arguments: VersionMetadata.ArgumentSet?
    var minecraftArguments: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case inheritsFrom
        case mainClass
        case libraries
        case arguments
        case minecraftArguments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        inheritsFrom = try container.decodeIfPresent(String.self, forKey: .inheritsFrom)
        mainClass = try container.decodeIfPresent(String.self, forKey: .mainClass)
        libraries = try container.decodeIfPresent([InstallerVersionLibrary].self, forKey: .libraries)?.map { $0.metadata }
        arguments = try container.decodeIfPresent(VersionMetadata.ArgumentSet.self, forKey: .arguments)
        minecraftArguments = try container.decodeIfPresent(String.self, forKey: .minecraftArguments)
    }
}

enum LoaderInstallationError: LocalizedError, Equatable {
    case invalidMainClass
    case missingCoreLibraryMetadata(GameLoader)
    case missingCoreLibraryFile(URL)
    case missingGeneratedLibraryFile(URL)
    case invalidInstallerProfile(String)
    case installerExecutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidMainClass:
            return "加载器 metadata 缺少有效的 mainClass。"
        case .missingCoreLibraryMetadata(let loader):
            return "加载器 metadata 缺少 \(loader.rawValue) 核心 JAR 信息。"
        case .missingCoreLibraryFile(let url):
            return "缺少加载器核心 JAR：\(url.path)"
        case .missingGeneratedLibraryFile(let url):
            return "缺少 processor 生成的加载器 JAR：\(url.path)"
        case .invalidInstallerProfile(let detail):
            return "加载器 installer metadata 无效：\(detail)"
        case .installerExecutionFailed(let detail):
            return "加载器 installer 执行失败：" + detail
        }
    }
}

private func validateLoaderMetadata(_ metadata: VersionMetadata, loader: GameLoader) throws {
    guard !metadata.mainClass.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw LoaderInstallationError.invalidMainClass
    }
    guard loader == .vanilla || metadata.coreLibrary(for: loader) != nil else {
        throw LoaderInstallationError.missingCoreLibraryMetadata(loader)
    }
}

private func validateGeneratedLoaderArtifacts(
    _ libraries: [VersionMetadata.Library],
    minecraftDirectory: URL
) throws {
    for library in libraries {
        guard let artifact = library.artifact,
              artifact.url == generatedLoaderArtifactURL
        else { continue }
        let artifactURL = minecraftDirectory
            .appendingPathComponent("libraries", isDirectory: true)
            .appendingPathComponent(artifact.path)
        guard FileManager.default.fileExists(atPath: artifactURL.path) else {
            throw LoaderInstallationError.missingGeneratedLibraryFile(artifactURL)
        }
    }
}

private enum LoaderMetadataBuilder {
    static func argumentSet(game: [String]?, jvm: [String]?) -> VersionMetadata.ArgumentSet? {
        guard game != nil || jvm != nil else { return nil }
        return VersionMetadata.ArgumentSet(
            game: game?.map { VersionMetadata.LaunchArgument(value: .string($0)) } ?? [],
            jvm: jvm?.map { VersionMetadata.LaunchArgument(value: .string($0)) } ?? []
        )
    }

    static func mergeArguments(
        base: VersionMetadata.ArgumentSet?,
        overlay: VersionMetadata.ArgumentSet?
    ) -> VersionMetadata.ArgumentSet? {
        guard base != nil || overlay != nil else { return nil }
        return VersionMetadata.ArgumentSet(
            game: (base?.game ?? []) + (overlay?.game ?? []),
            jvm: (base?.jvm ?? []) + (overlay?.jvm ?? [])
        )
    }

    static func mergeLibraries(
        base: [VersionMetadata.Library],
        overlay: [VersionMetadata.Library]
    ) -> [VersionMetadata.Library] {
        var result = base
        for library in overlay {
            if let index = result.firstIndex(where: { $0.name == library.name }) {
                result[index] = library
            } else {
                result.append(library)
            }
        }
        return result
    }

    static func convert(
        _ libraries: [LoaderLibrary],
        defaultRepository: URL
    ) throws -> [VersionMetadata.Library] {
        try libraries.map { library in
            guard let artifact = library.artifact(defaultRepository: defaultRepository) else {
                throw LoaderInstallationError.invalidInstallerProfile("无法解析 Maven 坐标：\(library.name)")
            }
            return VersionMetadata.Library(
                name: library.name,
                downloads: VersionMetadata.Library.Downloads(artifact: artifact, classifiers: nil)
            )
        }
    }

    static func build(
        base: VersionMetadata,
        id: String,
        mainClass: String,
        loader: GameLoader,
        libraries: [VersionMetadata.Library],
        arguments: VersionMetadata.ArgumentSet?,
        minecraftArguments: String? = nil
    ) throws -> VersionMetadata {
        var metadata = base
        metadata.id = id
        metadata.mainClass = mainClass
        metadata.libraries = mergeLibraries(base: base.libraries, overlay: libraries)
        metadata.arguments = mergeArguments(base: base.arguments, overlay: arguments)
        if let minecraftArguments {
            metadata.minecraftArguments = minecraftArguments
        }
        try validateLoaderMetadata(metadata, loader: loader)
        return metadata
    }
}

private func loadLoaderData(from url: URL) async throws -> Data {
    if url.isFileURL {
        return try Data(contentsOf: url)
    }
    let (data, response) = try await URLSession.shared.data(from: url)
    if let response = response as? HTTPURLResponse,
       !(200..<300).contains(response.statusCode) {
        throw LoaderInstallationError.invalidInstallerProfile("HTTP \(response.statusCode)：\(url.absoluteString)")
    }
    return data
}

private enum LoaderInstallerArchive {
    static func prepareClientProfile(
        from installerURL: URL,
        minecraftDirectory: URL,
        javaExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/java")
    ) async throws -> InstallerVersionProfile {
        let installerFile = try await downloadToTemporaryFile(from: installerURL)
        defer { try? FileManager.default.removeItem(at: installerFile) }
        let profile = try decodeVersionProfile(from: installerFile)
        let hasGeneratedArtifacts = profile.libraries?.contains(where: {
            guard let artifact = $0.artifact else { return false }
            return artifact.url == generatedLoaderArtifactURL || artifact.url.absoluteString.isEmpty
        }) == true
        if hasGeneratedArtifacts {
            try runClientInstaller(
                at: installerFile,
                minecraftDirectory: minecraftDirectory,
                javaExecutableURL: javaExecutableURL
            )
            try validateGeneratedLoaderArtifacts(
                profile.libraries ?? [],
                minecraftDirectory: minecraftDirectory
            )
        }
        return profile
    }

    private static func decodeVersionProfile(from installerFile: URL) throws -> InstallerVersionProfile {
        let versionData: Data
        do {
            versionData = try extract(entry: "version.json", from: installerFile)
        } catch {
            let profileData = try extract(entry: "install_profile.json", from: installerFile)
            let profileObject = try JSONSerialization.jsonObject(with: profileData) as? [String: Any]
            guard let jsonPath = profileObject?["json"] as? String else {
                throw LoaderInstallationError.invalidInstallerProfile("找不到 version.json 或 install_profile.json 的 json 路径")
            }
            versionData = try extract(entry: jsonPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")), from: installerFile)
        }

        do {
            return try JSONDecoder.mmcl.decode(InstallerVersionProfile.self, from: versionData)
        } catch {
            throw LoaderInstallationError.invalidInstallerProfile(error.localizedDescription)
        }
    }

    private static func runClientInstaller(
        at installerFile: URL,
        minecraftDirectory: URL,
        javaExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/java")
    ) throws {
        try FileManager.default.createDirectory(at: minecraftDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = javaExecutableURL
        process.arguments = ["-jar", installerFile.path, "--installClient", minecraftDirectory.path]
        process.currentDirectoryURL = minecraftDirectory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw LoaderInstallationError.installerExecutionFailed(error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            throw LoaderInstallationError.installerExecutionFailed("退出码 " + String(process.terminationStatus))
        }
    }

    private static func downloadToTemporaryFile(from installerURL: URL) async throws -> URL {
        let installerData = try await loadLoaderData(from: installerURL)
        let installerFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("MMCL-\(UUID().uuidString).jar")
        try installerData.write(to: installerFile, options: .atomic)
        return installerFile
    }

    private static func extract(entry: String, from archive: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, entry]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LoaderInstallationError.invalidInstallerProfile("installer 缺少 " + entry)
        }
        return data
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
    let baseURL: URL
    let mavenBaseURL: URL

    init(
        baseURL: URL = URL(string: "https://meta.fabricmc.net/v2")!,
        mavenBaseURL: URL = URL(string: "https://maven.fabricmc.net/")!
    ) {
        self.baseURL = baseURL
        self.mavenBaseURL = mavenBaseURL
    }

    func fetchLoaderVersions(gameVersion: String) async throws -> [FabricLoaderVersion] {
        let url = baseURL.appendingPathComponent("versions/loader/\(gameVersion)")
        let data = try await loadLoaderData(from: url)
        return try JSONDecoder.mmcl.decode([FabricLoaderVersion].self, from: data)
    }

    func fetchProfile(gameVersion: String, loaderVersion: String) async throws -> FabricProfile {
        let url = baseURL.appendingPathComponent("versions/loader/\(gameVersion)/\(loaderVersion)/profile/json")
        let data = try await loadLoaderData(from: url)
        return try JSONDecoder.mmcl.decode(FabricProfile.self, from: data)
    }

    func installFabric(
        gameVersion: String,
        loaderVersion: String? = nil,
        instance: LauncherInstance
    ) async throws -> VersionMetadata {
        let selectedVersion: String
        if let explicit = loaderVersion {
            selectedVersion = explicit
        } else {
            // 1. Determine the latest loader version only when needed.
            let versions = try await fetchLoaderVersions(gameVersion: gameVersion)
            guard let latest = versions.first(where: { $0.stable }) ?? versions.first else {
                throw FabricInstallError.noLoaderAvailable(gameVersion)
            }
            selectedVersion = latest.version
        }

        // 2. Fetch Fabric profile
        let profile = try await fetchProfile(gameVersion: gameVersion, loaderVersion: selectedVersion)

        // 3. Merge the complete profile into the base Minecraft metadata.
        let baseMetadata = try readBaseMetadata(instance: instance, gameVersion: profile.inheritsFrom)
        let profileLibraries = try LoaderMetadataBuilder.convert(
            profile.libraries ?? [],
            defaultRepository: mavenBaseURL
        )
        let metadata = try LoaderMetadataBuilder.build(
            base: baseMetadata,
            id: "\(profile.inheritsFrom)-fabric-\(selectedVersion)",
            mainClass: profile.mainClass,
            loader: .fabric,
            libraries: profileLibraries,
            arguments: LoaderMetadataBuilder.argumentSet(
                game: profile.arguments?.game,
                jvm: profile.arguments?.jvm
            )
        )

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
    let baseURL: URL
    let mavenBaseURL: URL

    init(
        baseURL: URL = URL(string: "https://meta.quiltmc.org/v3")!,
        mavenBaseURL: URL = URL(string: "https://maven.quiltmc.org/repository/release/")!
    ) {
        self.baseURL = baseURL
        self.mavenBaseURL = mavenBaseURL
    }

    func fetchLoaderVersions(gameVersion: String) async throws -> [QuiltLoaderVersion] {
        let url = baseURL.appendingPathComponent("versions/loader/\(gameVersion)")
        let data = try await loadLoaderData(from: url)
        return try JSONDecoder.mmcl.decode([QuiltLoaderVersion].self, from: data)
    }

    func fetchProfile(gameVersion: String, loaderVersion: String) async throws -> QuiltProfile {
        let url = baseURL.appendingPathComponent("versions/loader/\(gameVersion)/\(loaderVersion)/profile/json")
        let data = try await loadLoaderData(from: url)
        return try JSONDecoder.mmcl.decode(QuiltProfile.self, from: data)
    }

    func installQuilt(gameVersion: String, loaderVersion: String? = nil, instance: LauncherInstance) async throws -> VersionMetadata {
        let selectedVersion: String
        if let explicit = loaderVersion {
            selectedVersion = explicit
        } else {
            let versions = try await fetchLoaderVersions(gameVersion: gameVersion)
            guard let latest = versions.first(where: { $0.stable }) ?? versions.first else {
                throw QuiltInstallError.noLoaderAvailable(gameVersion)
            }
            selectedVersion = latest.version
        }

        let profile = try await fetchProfile(gameVersion: gameVersion, loaderVersion: selectedVersion)
        let baseMetadata = try readBaseMetadata(instance: instance, gameVersion: profile.inheritsFrom)

        let profileLibraries = try LoaderMetadataBuilder.convert(
            profile.libraries ?? [],
            defaultRepository: mavenBaseURL
        )
        let metadata = try LoaderMetadataBuilder.build(
            base: baseMetadata,
            id: "\(profile.inheritsFrom)-quilt-\(selectedVersion)",
            mainClass: profile.mainClass,
            loader: .quilt,
            libraries: profileLibraries,
            arguments: LoaderMetadataBuilder.argumentSet(
                game: profile.arguments?.game,
                jvm: profile.arguments?.jvm
            )
        )

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
    let promotionsURL: URL
    let installerBaseURL: URL

    init(
        promotionsURL: URL = URL(string: "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json")!,
        installerBaseURL: URL = URL(string: "https://maven.minecraftforge.net/net/minecraftforge/forge")!
    ) {
        self.promotionsURL = promotionsURL
        self.installerBaseURL = installerBaseURL
    }

    func fetchVersions(gameVersion: String) async throws -> [ForgeVersion] {
        let data = try await loadLoaderData(from: promotionsURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let promo = json?["promos"] as? [String: String] ?? [:]
        let keys = ["\(gameVersion)-recommended", "\(gameVersion)-latest"]
        var seen = Set<String>()
        return keys.compactMap { key in
            guard let value = promo[key], seen.insert(value).inserted else { return nil }
            let installerURL = installerBaseURL
                .appendingPathComponent("\(gameVersion)-\(value)", isDirectory: true)
                .appendingPathComponent("forge-\(gameVersion)-\(value)-installer.jar")
            return ForgeVersion(version: value, installerURL: installerURL.absoluteString)
        }
    }

    func installForge(gameVersion: String, forgeVersion: String? = nil, instance: LauncherInstance) async throws -> VersionMetadata {
        let selected: ForgeVersion
        if let forgeVersion {
            let installerURL = installerBaseURL
                .appendingPathComponent("\(gameVersion)-\(forgeVersion)", isDirectory: true)
                .appendingPathComponent("forge-\(gameVersion)-\(forgeVersion)-installer.jar")
            selected = ForgeVersion(version: forgeVersion, installerURL: installerURL.absoluteString)
        } else {
            let versions = try await fetchVersions(gameVersion: gameVersion)
            guard let latest = versions.first else {
                throw ForgeInstallError.noVersionAvailable(gameVersion)
            }
            selected = latest
        }

        let baseMetadata = try readBaseMetadata(instance: instance, gameVersion: gameVersion)
        guard let installerURL = URL(string: selected.installerURL) else {
            throw LoaderInstallationError.invalidInstallerProfile("无效的 Forge installer 地址：\(selected.installerURL)")
        }
        let profile = try await LoaderInstallerArchive.prepareClientProfile(
            from: installerURL,
            minecraftDirectory: instance.rootDirectory.appendingPathComponent(".minecraft", isDirectory: true)
        )
        guard let mainClass = profile.mainClass else {
            throw LoaderInstallationError.invalidMainClass
        }
        let metadata = try LoaderMetadataBuilder.build(
            base: baseMetadata,
            id: "\(gameVersion)-forge-\(selected.version)",
            mainClass: mainClass,
            loader: .forge,
            libraries: profile.libraries ?? [],
            arguments: profile.arguments,
            minecraftArguments: profile.minecraftArguments
        )

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
    let versionsURL: URL
    let installerBaseURL: URL

    init(
        versionsURL: URL = URL(string: "https://maven.neoforged.net/api/maven/versions/releases/net/neoforged/neoforge")!,
        installerBaseURL: URL = URL(string: "https://maven.neoforged.net/releases/net/neoforged/neoforge")!
    ) {
        self.versionsURL = versionsURL
        self.installerBaseURL = installerBaseURL
    }

    func fetchVersions(gameVersion: String) async throws -> [NeoForgeVersion] {
        let data = try await loadLoaderData(from: versionsURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let versions = json?["versions"] as? [String] ?? []
        let normalizedGameVersion: String? = {
            let components = gameVersion.split(separator: ".")
            guard components.count >= 3, components.first == "1" else { return nil }
            return components.dropFirst().map(String.init).joined(separator: ".")
        }()
        let prefixes = [gameVersion, normalizedGameVersion]
            .compactMap { $0 }
            .map { "\($0)." }
        return versions.compactMap { value in
            guard let prefix = prefixes.first(where: { value.hasPrefix($0) }) else { return nil }
            return NeoForgeVersion(
                version: value,
                neoForgeVersion: String(value.dropFirst(prefix.count))
            )
        }
    }

    func installNeoForge(gameVersion: String, version: String? = nil, instance: LauncherInstance) async throws -> VersionMetadata {
        let selected: NeoForgeVersion
        if let version {
            let prefix = neoForgeGameVersionPrefix(for: gameVersion)
            let fullVersion: String
            if version.hasPrefix(prefix + ".") {
                fullVersion = version
            } else {
                fullVersion = "\(prefix).\(version)"
            }
            selected = NeoForgeVersion(
                version: fullVersion,
                neoForgeVersion: String(fullVersion.dropFirst(prefix.count + 1))
            )
        } else {
            let versions = try await fetchVersions(gameVersion: gameVersion)
            guard let latest = versions.last else {
                throw NeoForgeInstallError.noVersionAvailable(gameVersion)
            }
            selected = latest
        }

        let baseMetadata = try readBaseMetadata(instance: instance, gameVersion: gameVersion)
        let installerURL = installerBaseURL
            .appendingPathComponent(selected.version, isDirectory: true)
            .appendingPathComponent("neoforge-\(selected.version)-installer.jar")
        let profile = try await LoaderInstallerArchive.prepareClientProfile(
            from: installerURL,
            minecraftDirectory: instance.rootDirectory.appendingPathComponent(".minecraft", isDirectory: true)
        )
        guard let mainClass = profile.mainClass else {
            throw LoaderInstallationError.invalidMainClass
        }
        let metadata = try LoaderMetadataBuilder.build(
            base: baseMetadata,
            id: "\(gameVersion)-neoforge-\(selected.version)",
            mainClass: mainClass,
            loader: .neoForge,
            libraries: profile.libraries ?? [],
            arguments: profile.arguments,
            minecraftArguments: profile.minecraftArguments
        )

        let versionDir = instance.rootDirectory
            .appendingPathComponent(".minecraft", isDirectory: true)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(metadata.id, isDirectory: true)
        try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
        try JSONEncoder.mmcl.encode(metadata).write(to: versionDir.appendingPathComponent("\(metadata.id).json"), options: .atomic)

        return metadata
    }

    private func neoForgeGameVersionPrefix(for gameVersion: String) -> String {
        let components = gameVersion.split(separator: ".")
        guard components.count >= 3, components.first == "1" else { return gameVersion }
        return components.dropFirst().map(String.init).joined(separator: ".")
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
    func exchangeForMinecraftToken(xstsToken: String, userHash: String) async throws -> MinecraftTokenResponse
    func fetchMinecraftProfile(accessToken: String) async throws -> MinecraftProfileResponse
    func refreshMicrosoftToken(refreshToken: String) async throws -> MicrosoftTokenResponse
}

extension AuthServicing {
    func exchangeForMinecraftToken(
        xstsToken: String,
        userHash: String
    ) async throws -> MinecraftTokenResponse {
        // Keep existing test doubles and integrations source-compatible while
        // allowing the real service to send the complete XBL3.0 identity.
        try await exchangeForMinecraftToken(xstsToken: xstsToken)
    }
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
                "RpsTicket": "d=\(accessToken)"
            ],
            "RelyingParty": "http://auth.xboxlive.com",
            "TokenType": "JWT"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "x-xbl-contract-version")
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
                "UserTokens": [xblToken],
                // Request the user hash and XUID-related claims used by
                // Minecraft's modern launch arguments (auth_xuid).
                "OptionalDisplayClaims": ["xid", "mgt", "mgs", "umg"]
            ],
            "RelyingParty": "rp://api.minecraftservices.com/",
            "TokenType": "JWT"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "x-xbl-contract-version")
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        if let token = json["Token"] as? String {
            return XBLXSTSResponse(
                token: token,
                expiresInSeconds: 3600,
                xuid: xuid(from: json),
                userHash: userHash(from: json)
            )
        }
        let error = json["XErr"] as? Int ?? 0
        throw AuthError.xstsAuthFailed(error)
    }

    private func xuid(from response: [String: Any]) -> String {
        guard let displayClaims = response["DisplayClaims"] as? [String: Any],
              let users = displayClaims["xui"] as? [[String: Any]],
              let firstUser = users.first
        else {
            return ""
        }

        if let xuid = firstUser["xid"] as? String {
            return xuid
        }
        if let xuid = firstUser["xid"] as? NSNumber {
            return xuid.stringValue
        }
        return ""
    }

    private func userHash(from response: [String: Any]) -> String {
        guard let displayClaims = response["DisplayClaims"] as? [String: Any],
              let users = displayClaims["xui"] as? [[String: Any]],
              let userHash = users.first?["uhs"] as? String
        else {
            return ""
        }
        return userHash
    }

    func exchangeForMinecraftToken(xstsToken: String) async throws -> MinecraftTokenResponse {
        try await exchangeForMinecraftToken(xstsToken: xstsToken, userHash: "")
    }

    func exchangeForMinecraftToken(
        xstsToken: String,
        userHash: String
    ) async throws -> MinecraftTokenResponse {
        let url = URL(string: "https://api.minecraftservices.com/authentication/login_with_xbox")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let identityToken: String
        if userHash.isEmpty {
            identityToken = "XBL3.0 x=\(xstsToken)"
        } else {
            identityToken = "XBL3.0 x=\(userHash);\(xstsToken)"
        }
        let body = ["identityToken": identityToken]
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

// MARK: - Profile Export/Import

protocol ProfileExportServicing {
    func exportProfile(
        instances: [LauncherInstance],
        accounts: [MinecraftAccount],
        settings: ProfileExportSettings
    ) throws -> Data
    func importProfile(from data: Data) throws -> ProfileExportData
    func saveExport(_ data: Data, to url: URL) throws
    func loadExport(from url: URL) throws -> Data
}

struct ProfileExportService: ProfileExportServicing {
    func exportProfile(
        instances: [LauncherInstance],
        accounts: [MinecraftAccount],
        settings: ProfileExportSettings
    ) throws -> Data {
        let export = ProfileExportData(
            instances: instances,
            accounts: accounts,
            settings: settings
        )
        return try JSONEncoder.mmcl.encode(export)
    }

    func importProfile(from data: Data) throws -> ProfileExportData {
        try JSONDecoder.mmcl.decode(ProfileExportData.self, from: data)
    }

    func saveExport(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func loadExport(from url: URL) throws -> Data {
        try Data(contentsOf: url)
    }
}

// MARK: - Server List

protocol ServerListServicing {
    func loadServers(from url: URL) -> [ServerInfo]
    func saveServers(_ servers: [ServerInfo], to url: URL) throws
    func pingServer(address: String, port: Int) async -> ServerInfo.ServerPingResult?
    func serverListFileURL(for instance: LauncherInstance) -> URL
}

private struct ServerPingCompletionGate: @unchecked Sendable {
    private let semaphore: DispatchSemaphore

    init() {
        semaphore = DispatchSemaphore(value: 1)
    }

    nonisolated func run(_ action: @Sendable () -> Void) {
        guard semaphore.wait(timeout: .now()) == .success else { return }
        action()
    }
}

struct ServerListService: ServerListServicing {
    let applicationSupportDirectory: URL

    init(applicationSupportDirectory: URL? = nil) {
        self.applicationSupportDirectory = applicationSupportDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
    }

    func serverListFileURL(for instance: LauncherInstance) -> URL {
        instance.rootDirectory
            .appendingPathComponent(".minecraft", isDirectory: true)
            .appendingPathComponent("servers.json")
    }

    func loadServers(from url: URL) -> [ServerInfo] {
        guard let data = try? Data(contentsOf: url),
              let servers = try? JSONDecoder.mmcl.decode([ServerInfo].self, from: data) else {
            return []
        }
        return servers
    }

    func saveServers(_ servers: [ServerInfo], to url: URL) throws {
        let data = try JSONEncoder.mmcl.encode(servers)
        let parentDir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func pingServer(address: String, port: Int) async -> ServerInfo.ServerPingResult? {
        let host = NWEndpoint.Host(address)
        let portObj = NWEndpoint.Port(rawValue: UInt16(port))!
        let connection = NWConnection(host: host, port: portObj, using: .tcp)

        return await withCheckedContinuation { continuation in
            let startTime = Date()
            let completionGate = ServerPingCompletionGate()
            let finish: @Sendable (ServerInfo.ServerPingResult?) -> Void = { result in
                completionGate.run {
                    connection.cancel()
                    continuation.resume(returning: result)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
                    // Simple ping - send a basic Minecraft server list ping
                    var packet = Data()
                    // Packet ID: 0x00 (Handshake)
                    packet.append(0x01) // length
                    packet.append(0x00) // packet id
                    // Protocol version
                    packet.append(contentsOf: [0xFF, 0x05]) // varint 762 (1.19.4)
                    // Server address
                    let addrData = address.utf8
                    packet.append(UInt8(addrData.count))
                    packet.append(contentsOf: addrData)
                    // Server port
                    packet.append(UInt8(port >> 8))
                    packet.append(UInt8(port & 0xFF))
                    // Next state: 1 (status)
                    packet.append(0x01)

                    connection.send(content: packet, completion: .contentProcessed { _ in
                        // For a real implementation, we'd parse the response
                        // For now, return a basic result indicating the server is reachable
                        let result = ServerInfo.ServerPingResult(
                            motd: "服务器可达",
                            playerCount: 0,
                            maxPlayers: 0,
                            versionName: "未知",
                            pingMs: elapsed
                        )
                        finish(result)
                    })
                case .failed:
                    finish(nil)
                case .cancelled:
                    finish(nil)
                default:
                    break
                }
            }

            connection.start(queue: .global())

            // Timeout after 5 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                finish(nil)
            }
        }
    }
}

protocol CurseForgeServicing {
    func search(query: String, classId: Int?, gameVersion: String?, apiKey: String) async throws -> [CurseForgeSearchResult]
}

struct CurseForgeService: CurseForgeServicing {
    let baseURL = URL(string: "https://api.curseforge.com")!
    let userAgent = "MMCL/1.0 (https://github.com/Lhy723/MMCL)"

    func search(query: String, classId: Int? = nil, gameVersion: String? = nil, apiKey: String) async throws -> [CurseForgeSearchResult] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/v1/mods/search"), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "gameId", value: "432"),
            URLQueryItem(name: "searchFilter", value: query),
            URLQueryItem(name: "pageSize", value: "20")
        ]
        if let classId {
            queryItems.append(URLQueryItem(name: "classId", value: "\(classId)"))
        }
        if let gv = gameVersion {
            queryItems.append(URLQueryItem(name: "gameVersion", value: gv))
        }
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        if let http = urlResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CurseForgeError.searchFailed("HTTP \(http.statusCode)")
        }
        let response = try JSONDecoder().decode(CurseForgeSearchResponse.self, from: data)
        return response.data
    }
}

enum CurseForgeError: LocalizedError, Equatable {
    case searchFailed(String)

    var errorDescription: String? {
        switch self {
        case .searchFailed(let detail):
            return "CurseForge 搜索失败：\(detail)"
        }
    }
}

enum AuthError: LocalizedError, Equatable {
    case userDeclined
    case codeExpired
    case tokenExchangeFailed(String)
    case xstsAuthFailed(Int)
    case noMinecraftProfile
    case refreshTokenUnavailable

    var errorDescription: String? {
        switch self {
        case .userDeclined: return "登录已被拒绝。"
        case .codeExpired: return "设备代码已过期，请重试。"
        case .tokenExchangeFailed(let desc): return "令牌交换失败：\(desc)"
        case .xstsAuthFailed(let code): return "XSTS 认证失败（错误码 \(code)）。"
        case .noMinecraftProfile: return "此账号没有 Minecraft Profile。请确认已购买游戏。"
        case .refreshTokenUnavailable: return "Microsoft 账号令牌已过期，且没有可用的 Refresh Token。请重新登录。"
        }
    }
}
