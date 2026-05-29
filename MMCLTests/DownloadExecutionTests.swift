import XCTest
@testable import MMCL

final class DownloadExecutionTests: XCTestCase {
    func testDownloadServiceCopiesFileURLAndVerifiesSHA1() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.dat")
        let destination = root.appendingPathComponent("nested/output.dat")
        try Data("hello minecraft".utf8).write(to: source)

        let job = DownloadJob(
            title: "测试文件",
            source: .official,
            remoteURL: source,
            destination: destination,
            sha1: "0205c49d7dadcddde7b919c2b0763dd43d1679f0",
            totalBytes: 15
        )

        let service = DownloadService()
        let completedJob: DownloadJob = await withCheckedContinuation { continuation in
            service.onComplete = { _, job in
                continuation.resume(returning: job)
            }
            service.onError = { _, error in
                continuation.resume(returning: DownloadJob(
                    title: job.title, source: job.source, remoteURL: job.remoteURL,
                    destination: job.destination, sha1: job.sha1, totalBytes: job.totalBytes,
                    status: .failed
                ))
            }
            service.startDownload(job)
        }

        XCTAssertEqual(completedJob.status, DownloadStatus.completed)
        XCTAssertEqual(completedJob.completedBytes, 15)
        XCTAssertEqual(try Data(contentsOf: destination), Data("hello minecraft".utf8))
    }

    func testDownloadServiceMarksFailedWhenSHA1DoesNotMatch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.dat")
        let destination = root.appendingPathComponent("output.dat")
        try Data("bad hash".utf8).write(to: source)

        let job = DownloadJob(
            title: "错误校验",
            source: .official,
            remoteURL: source,
            destination: destination,
            sha1: "0000000000000000000000000000000000000000",
            totalBytes: 8
        )

        let service = DownloadService()
        let resultJob: DownloadJob = await withCheckedContinuation { continuation in
            service.onComplete = { _, job in
                continuation.resume(returning: job)
            }
            service.onError = { _, _ in
                let failedJob = DownloadJob(
                    title: job.title, source: job.source, remoteURL: job.remoteURL,
                    destination: job.destination, sha1: job.sha1, totalBytes: job.totalBytes,
                    status: .failed
                )
                continuation.resume(returning: failedJob)
            }
            service.startDownload(job)
        }

        XCTAssertEqual(resultJob.status, DownloadStatus.failed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    @MainActor
    func testStoreExecutesQueuedDownloadsAndAddsFailureDiagnostic() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.dat")
        try Data("ok".utf8).write(to: source)

        let jobs = [
            DownloadJob(
                title: "成功任务",
                source: .official,
                remoteURL: source,
                destination: root.appendingPathComponent("success.dat"),
                sha1: "7a85f4764bbd6daf1c3545efbbf0f279a6dc0beb",
                totalBytes: 2
            ),
            DownloadJob(
                title: "失败任务",
                source: .official,
                remoteURL: source,
                destination: root.appendingPathComponent("failure.dat"),
                sha1: "0000000000000000000000000000000000000000",
                totalBytes: 2
            )
        ]
        let store = LauncherStore(
            instances: [],
            downloadJobs: jobs,
            featuredProjects: [],
            diagnostics: [],
            javaRuntimes: [],
            availableVersions: []
        )

        await store.executeQueuedDownloads()

        // Wait for async callbacks to propagate
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(store.downloadJobs[0].status, DownloadStatus.completed)
        XCTAssertEqual(store.downloadJobs[1].status, DownloadStatus.failed)
        XCTAssertEqual(store.diagnostics.first?.title, "下载失败")
        XCTAssertTrue(store.diagnostics.first?.summary.contains("失败任务") == true)
    }

    @MainActor
    func testDownloadServiceCancelAndRestart() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.dat")
        try Data("cancel test".utf8).write(to: source)

        let job = DownloadJob(
            title: "取消测试",
            source: .official,
            remoteURL: source,
            destination: root.appendingPathComponent("output.dat"),
            totalBytes: 11
        )

        let service = DownloadService()

        // Start then cancel
        service.startDownload(job)
        try await Task.sleep(nanoseconds: 50_000_000)
        service.cancelAllDownloads()

        // Wait for cancellation to propagate
        try await Task.sleep(nanoseconds: 100_000_000)

        // Restart and verify completion
        let completedJob: DownloadJob = await withCheckedContinuation { continuation in
            service.onComplete = { _, job in
                continuation.resume(returning: job)
            }
            service.onError = { _, _ in
                continuation.resume(returning: DownloadJob(
                    title: job.title, source: job.source, remoteURL: job.remoteURL,
                    destination: job.destination, sha1: job.sha1, totalBytes: job.totalBytes,
                    status: .failed
                ))
            }
            service.startDownload(job)
        }

        XCTAssertEqual(completedJob.status, DownloadStatus.completed)
        XCTAssertEqual(completedJob.completedBytes, 11)
    }
}
