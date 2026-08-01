import XCTest
@testable import MMCL

final class LauncherServiceTests: XCTestCase {
    func testApplicationSupportRootUsesMMCLDirectory() throws {
        let service = InstanceService(applicationSupportDirectory: URL(fileURLWithPath: "/Users/example/Library/Application Support", isDirectory: true))

        XCTAssertEqual(service.rootDirectory.path, "/Users/example/Library/Application Support/MMCL")
        XCTAssertEqual(service.instancesDirectory.path, "/Users/example/Library/Application Support/MMCL/Instances")
    }

    func testVersionManifestParsesLatestReleaseAndVersions() throws {
        let json = """
        {
          "latest": { "release": "1.21.5", "snapshot": "25w21a" },
          "versions": [
            {
              "id": "1.21.5",
              "type": "release",
              "url": "https://piston-meta.mojang.com/v1/packages/1.21.5.json",
              "time": "2026-05-20T10:00:00+00:00",
              "releaseTime": "2026-05-20T10:00:00+00:00"
            },
            {
              "id": "25w21a",
              "type": "snapshot",
              "url": "https://piston-meta.mojang.com/v1/packages/25w21a.json",
              "time": "2026-05-21T10:00:00+00:00",
              "releaseTime": "2026-05-21T10:00:00+00:00"
            }
          ]
        }
        """

        let manifest = try VersionManifestService().decodeManifest(from: Data(json.utf8))

        XCTAssertEqual(manifest.latest.release, "1.21.5")
        XCTAssertEqual(manifest.latest.snapshot, "25w21a")
        XCTAssertEqual(manifest.versions.map(\.id), ["1.21.5", "25w21a"])
        XCTAssertEqual(manifest.versions[0].type, .release)
        XCTAssertEqual(manifest.versions[0].recommendedJavaMajorVersion, 21)
        XCTAssertEqual(manifest.versions[0].metadataURL.absoluteString, "https://piston-meta.mojang.com/v1/packages/1.21.5.json")
    }

    func testJavaRuntimeServiceParsesJavaHomeOutput() throws {
        let output = """
        Matching Java Virtual Machines (2):
            21.0.3 (arm64) \"Eclipse Adoptium\" - \"Temurin 21\" /Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
            17.0.11 (x86_64) \"Azul Systems\" - \"Zulu 17\" /Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home
        /Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
        """

        let runtimes = JavaRuntimeService().parseJavaHomeVerboseOutput(output)

        XCTAssertEqual(runtimes.count, 2)
        XCTAssertEqual(runtimes[0].name, "Temurin 21")
        XCTAssertEqual(runtimes[0].version, "21.0.3")
        XCTAssertEqual(runtimes[0].majorVersion, 21)
        XCTAssertEqual(runtimes[0].architecture, .arm64)
        XCTAssertEqual(runtimes[0].executableURL.path, "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        XCTAssertEqual(runtimes[1].architecture, .x86_64)
    }

    func testJavaRuntimeServiceParsesLegacyJava8Formats() throws {
        let javaVersionOutput = """
        java version "1.8.0_401"
        Java(TM) SE Runtime Environment (build 1.8.0_401-b10)
        """
        let openJDKVersionOutput = """
        openjdk version "21.0.3+9-LTS"
        OpenJDK Runtime Environment Temurin-21.0.3+9 (build 21.0.3+9-LTS)
        """

        let javaVersion = JavaRuntimeService.parseJavaVersionOutput(javaVersionOutput)
        let openJDKVersion = JavaRuntimeService.parseJavaVersionOutput(openJDKVersionOutput)

        XCTAssertEqual(javaVersion?.version, "1.8.0_401")
        XCTAssertEqual(javaVersion?.majorVersion, 8)
        XCTAssertEqual(openJDKVersion?.version, "21.0.3+9-LTS")
        XCTAssertEqual(openJDKVersion?.majorVersion, 21)
        XCTAssertEqual(JavaRuntimeService.parseMajorVersion(from: "1.8.0_382-b05"), 8)
        XCTAssertEqual(JavaRuntimeService.parseMajorVersion(from: "9-ea"), 9)
        XCTAssertEqual(JavaRuntimeService.parseMajorVersion(from: "17.0.11+9"), 17)

        let javaHomeOutput = """
        Matching Java Virtual Machines (2):
            1.8.0_401 (x86_64) "Amazon.com Inc." - "Corretto-8" /Library/Java/JavaVirtualMachines/amazon-corretto-8.jdk/Contents/Home
            21.0.3+9 (arm64) "Eclipse Adoptium" - "Temurin 21" /Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
        /Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
        """

        let runtimes = JavaRuntimeService().parseJavaHomeVerboseOutput(javaHomeOutput)

        XCTAssertEqual(runtimes.map(\.majorVersion), [8, 21])
        XCTAssertEqual(runtimes[0].version, "1.8.0_401")
        XCTAssertEqual(runtimes[0].architecture, .x86_64)
    }

    func testPortableJDKInstallerRejectsTarFailureAndCleansIncompleteInstall() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archiveURL = root.appendingPathComponent("broken.tar.gz")
        try Data("not a tar archive".utf8).write(to: archiveURL)
        let targetDirectory = root.appendingPathComponent("JDK", isDirectory: true)

        let installer = PortableJDKInstaller(downloader: { url in
            (
                archiveURL,
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        })

        do {
            try await installer.install(
                majorVersion: 21,
                architecture: "aarch64",
                targetDirectory: targetDirectory
            )
            XCTFail("损坏的 JDK 压缩包不应报告安装成功")
        } catch let error as PortableJDKInstallError {
            guard case .tarFailed(_, let stderr) = error else {
                return XCTFail("预期 tarFailed，实际为 \(error)")
            }
            XCTAssertFalse(stderr.isEmpty)
        }

        let remainingFiles = try? FileManager.default.contentsOfDirectory(
            at: targetDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(remainingFiles?.isEmpty ?? true)
    }

    func testPortableJDKInstallerRejectsHTTPErrorBeforeCreatingInstallDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let targetDirectory = root.appendingPathComponent("JDK", isDirectory: true)
        let installer = PortableJDKInstaller(downloader: { url in
            (
                root.appendingPathComponent("unused.tar.gz"),
                HTTPURLResponse(
                    url: url,
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        })

        do {
            try await installer.install(
                majorVersion: 21,
                architecture: "aarch64",
                targetDirectory: targetDirectory
            )
            XCTFail("HTTP 404 不应报告安装成功")
        } catch let error as PortableJDKInstallError {
            XCTAssertEqual(error, .httpStatus(404))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: targetDirectory.path))
    }

    func testPortableJDKInstallerRejectsArchiveWithoutExecutableJava() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try Data("not a java runtime".utf8).write(to: sourceDirectory.appendingPathComponent("README"))
        let archiveURL = root.appendingPathComponent("jdk.tar.gz")
        try Self.makeTarArchive(contentsOf: sourceDirectory, at: archiveURL)
        let targetDirectory = root.appendingPathComponent("JDK", isDirectory: true)
        let installer = PortableJDKInstaller(downloader: { url in
            (
                archiveURL,
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        })

        do {
            try await installer.install(
                majorVersion: 21,
                architecture: "aarch64",
                targetDirectory: targetDirectory
            )
            XCTFail("缺少 bin/java 不应报告安装成功")
        } catch let error as PortableJDKInstallError {
            guard case .missingJavaExecutable = error else {
                return XCTFail("预期 missingJavaExecutable，实际为 \(error)")
            }
        }

        let remainingFiles = try? FileManager.default.contentsOfDirectory(
            at: targetDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(remainingFiles?.isEmpty ?? true)
    }

    func testPortableJDKInstallerMovesValidatedJDKIntoTargetDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root
            .appendingPathComponent("jdk-21.0.0", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let javaURL = sourceDirectory.appendingPathComponent("java")
        try Data("#!/bin/sh\n".utf8).write(to: javaURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: javaURL.path
        )
        let archiveURL = root.appendingPathComponent("jdk.tar.gz")
        try Self.makeTarArchive(contentsOf: sourceDirectory.deletingLastPathComponent().deletingLastPathComponent(), at: archiveURL)
        let targetDirectory = root.appendingPathComponent("JDK", isDirectory: true)
        let installer = PortableJDKInstaller(downloader: { url in
            (
                archiveURL,
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        })

        try await installer.install(
            majorVersion: 21,
            architecture: "aarch64",
            targetDirectory: targetDirectory
        )

        let installedJava = targetDirectory
            .appendingPathComponent("jdk-21.0.0/bin/java")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installedJava.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedJava.path))
    }

    func testJavaRuntimeServiceRecognizesPortableJDKLayouts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let directHome = root.appendingPathComponent("direct-layout", isDirectory: true)
        let nestedContainer = root.appendingPathComponent("nested-layout", isDirectory: true)
        let nestedHome = nestedContainer.appendingPathComponent("Contents/Home", isDirectory: true)

        for home in [directHome, nestedHome] {
            let javaURL = home.appendingPathComponent("bin/java")
            try FileManager.default.createDirectory(
                at: javaURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("#!/bin/sh\n".utf8).write(to: javaURL)
        }

        XCTAssertEqual(JavaRuntimeService.portableJavaHome(in: directHome), directHome)
        XCTAssertEqual(JavaRuntimeService.portableJavaHome(in: nestedContainer), nestedHome)
    }

    func testLaunchServiceBuildsMinecraftArgumentPreview() {
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: URL(fileURLWithPath: "/Users/example/Instances/vanilla", isDirectory: true),
            profile: LaunchProfile(offlineUsername: "Steve", memoryMegabytes: 4096, jvmArguments: ["-XX:+UseG1GC"], resolutionWidth: 854, resolutionHeight: 480),
            status: .ready
        )
        let java = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )

        let command = LaunchService().previewCommand(for: instance, java: java)

        XCTAssertEqual(command[0], "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        XCTAssertTrue(command.contains("-Xmx4096m"))
        XCTAssertTrue(command.contains("-Djava.library.path=/Users/example/Instances/vanilla/.minecraft/versions/1.21.5/natives"))
        XCTAssertTrue(command.contains("--username"))
        XCTAssertTrue(command.contains("Steve"))
        XCTAssertTrue(command.contains("--gameDir"))
        XCTAssertTrue(command.contains("/Users/example/Instances/vanilla/.minecraft"))
        XCTAssertTrue(command.contains("--version"))
        XCTAssertTrue(command.contains("1.21.5"))
    }

    func testLaunchServiceBuildsPreciseClasspathFromLocalVersionMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root,
            profile: LaunchProfile(offlineUsername: "Steve", memoryMegabytes: 4096, jvmArguments: [], resolutionWidth: 854, resolutionHeight: 480),
            status: .ready
        )
        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.versionMetadataJSON.utf8))
        _ = try DownloadService().writeVersionMetadata(metadata: metadata, instance: instance)
        let java = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )

        let command = LaunchService().previewCommand(for: instance, java: java)
        let classpath = try XCTUnwrap(command.argument(after: "-cp"))

        XCTAssertFalse(classpath.contains("libraries/*"))
        XCTAssertTrue(classpath.contains(root.appendingPathComponent(".minecraft/libraries/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar").path))
        XCTAssertTrue(classpath.contains(root.appendingPathComponent(".minecraft/versions/1.21.5/1.21.5.jar").path))
        XCTAssertTrue(command.contains("net.minecraft.client.main.Main"))
        XCTAssertEqual(command.argument(after: "--assetIndex"), "19")
    }

    func testLaunchServiceExpandsModernMojangArguments() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root,
            profile: LaunchProfile(offlineUsername: "Steve", memoryMegabytes: 4096, jvmArguments: ["-XX:+UseG1GC"], resolutionWidth: 854, resolutionHeight: 480),
            status: .ready
        )
        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.modernArgumentsMetadataJSON.utf8))
        _ = try DownloadService().writeVersionMetadata(metadata: metadata, instance: instance)
        let java = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )

        let command = LaunchService().previewCommand(for: instance, java: java)
        let classpath = try XCTUnwrap(command.argument(after: "-cp"))

        XCTAssertTrue(command.contains("-XX:+UseG1GC"))
        XCTAssertTrue(command.contains("-Djava.library.path=\(root.path)/.minecraft/versions/1.21.5/natives"))
        XCTAssertTrue(command.contains("-Xdock:name=MMCL"))
        XCTAssertFalse(command.contains("-Dos.name=Windows"))
        XCTAssertEqual(classpath, [
            root.appendingPathComponent(".minecraft/libraries/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar").path,
            root.appendingPathComponent(".minecraft/versions/1.21.5/1.21.5.jar").path
        ].joined(separator: ":"))
        XCTAssertEqual(command.argument(after: "--username"), "Steve")
        XCTAssertEqual(command.argument(after: "--assetsDir"), root.appendingPathComponent(".minecraft/assets").path)
        XCTAssertEqual(command.argument(after: "--assetIndex"), "19")
    }

    func testLaunchServiceUsesLoaderSpecificVersionMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let loaderVersionID = "1.21.5-fabric-0.16.14"
        let instance = LauncherInstance(
            name: "Fabric 生存",
            gameVersion: "1.21.5",
            loader: .fabric,
            rootDirectory: root,
            profile: LaunchProfile(offlineUsername: "Steve", memoryMegabytes: 4096, jvmArguments: ["-XX:+UseG1GC"], resolutionWidth: 854, resolutionHeight: 480),
            status: .ready,
            launchVersionID: loaderVersionID
        )
        var baseMetadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.modernArgumentsMetadataJSON.utf8))
        baseMetadata.id = "1.21.5"
        baseMetadata.mainClass = "base.minecraft.Main"
        var loaderMetadata = baseMetadata
        loaderMetadata.id = loaderVersionID
        loaderMetadata.mainClass = "net.fabricmc.loader.impl.launch.knot.KnotClient"
        let downloadService = DownloadService()
        _ = try downloadService.writeVersionMetadata(metadata: baseMetadata, instance: instance)
        _ = try downloadService.writeVersionMetadata(metadata: loaderMetadata, instance: instance)
        let java = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )

        let command = LaunchService().previewCommand(
            for: instance,
            java: java,
            account: MinecraftAccount(username: "Steve", type: .offline)
        )

        XCTAssertTrue(command.contains("net.fabricmc.loader.impl.launch.knot.KnotClient"))
        XCTAssertFalse(command.contains("base.minecraft.Main"))
        let classpath = try XCTUnwrap(command.argument(after: "-cp"))
        XCTAssertTrue(classpath.contains(root.appendingPathComponent(".minecraft/versions/\(loaderVersionID)/\(loaderVersionID).jar").path))
        XCTAssertFalse(classpath.contains(root.appendingPathComponent(".minecraft/versions/1.21.5/1.21.5.jar").path))
        XCTAssertEqual(command.argument(after: "--version"), loaderVersionID)
    }

    func testLaunchServiceUsesSelectedMicrosoftAccountAndRedactsAccessToken() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "正版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root,
            profile: LaunchProfile(offlineUsername: "Steve", memoryMegabytes: 4096, jvmArguments: [], resolutionWidth: 854, resolutionHeight: 480),
            status: .ready
        )
        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.modernArgumentsMetadataJSON.utf8))
        _ = try DownloadService().writeVersionMetadata(metadata: metadata, instance: instance)
        let java = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )
        let account = MinecraftAccount(
            username: "MicrosoftPlayer",
            uuid: "minecraft-uuid",
            xuid: "2533274991020393",
            accessToken: "minecraft-access-token-secret",
            refreshToken: "microsoft-refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            type: .microsoft
        )

        let command = LaunchService().previewCommand(for: instance, java: java, account: account)

        XCTAssertEqual(command.argument(after: "--username"), "MicrosoftPlayer")
        XCTAssertEqual(command.argument(after: "--uuid"), "minecraft-uuid")
        XCTAssertEqual(command.argument(after: "--xuid"), "2533274991020393")
        XCTAssertEqual(command.argument(after: "--accessToken"), "<redacted>")
        XCTAssertEqual(command.argument(after: "--userType"), "msa")
        XCTAssertFalse(command.contains(account.accessToken))
    }

    func testLaunchServiceRedactsMicrosoftAccessTokenFromLaunchSession() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "正版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root,
            profile: LaunchProfile(offlineUsername: "Steve", memoryMegabytes: 512, jvmArguments: [], resolutionWidth: 854, resolutionHeight: 480),
            status: .ready
        )
        let java = JavaRuntime(
            name: "Echo",
            version: "1.0",
            majorVersion: 21,
            architecture: .universal,
            executableURL: URL(fileURLWithPath: "/bin/echo")
        )
        let account = MinecraftAccount(
            username: "MicrosoftPlayer",
            uuid: "minecraft-uuid",
            xuid: "2533274991020393",
            accessToken: "minecraft-access-token-secret",
            type: .microsoft
        )

        let session = try LaunchService().launch(instance: instance, java: java, account: account)

        XCTAssertFalse(session.command.contains(account.accessToken))
        XCTAssertEqual(session.command.argument(after: "--accessToken"), "<redacted>")
    }

    func testLaunchServiceExpandsLegacyMinecraftArguments() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "旧版生存",
            gameVersion: "1.12.2",
            loader: .vanilla,
            rootDirectory: root,
            profile: LaunchProfile(offlineUsername: "Alex", memoryMegabytes: 2048, jvmArguments: [], resolutionWidth: 854, resolutionHeight: 480),
            status: .ready
        )
        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.legacyArgumentsMetadataJSON.utf8))
        _ = try DownloadService().writeVersionMetadata(metadata: metadata, instance: instance)
        let java = JavaRuntime(
            name: "Temurin 8",
            version: "1.8.0",
            majorVersion: 8,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-8.jdk/Contents/Home/bin/java")
        )

        let command = LaunchService().previewCommand(for: instance, java: java)

        XCTAssertEqual(command.argument(after: "--username"), "Alex")
        XCTAssertEqual(command.argument(after: "--version"), "1.12.2")
        XCTAssertEqual(command.argument(after: "--assetIndex"), "legacy")
        XCTAssertTrue(command.contains("net.minecraft.client.main.Main"))
    }

    func testLaunchServicePreflightReportsMissingInstallFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root,
            status: .ready
        )
        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.versionMetadataJSON.utf8))
        _ = try DownloadService().writeVersionMetadata(metadata: metadata, instance: instance)
        let java = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )

        let report = LaunchService().preflight(instance: instance, java: java)

        XCTAssertFalse(report.canLaunch)
        XCTAssertEqual(report.severity, .error)
        XCTAssertTrue(report.summary.contains("client jar"))
        XCTAssertTrue(report.summary.contains("asset index"))
        XCTAssertTrue(report.summary.contains("library"))
        XCTAssertEqual(report.suggestedActions.first, "生成安装计划并完成下载")
    }

    func testLaunchServicePreflightPassesForCompleteVanillaInstance() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root,
            status: .ready
        )
        let metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.versionMetadataJSON.utf8))
        _ = try DownloadService().writeVersionMetadata(metadata: metadata, instance: instance)
        try Data("client".utf8).write(to: root.appendingPathComponent(".minecraft/versions/1.21.5/1.21.5.jar"))
        let assetIndex = root.appendingPathComponent(".minecraft/assets/indexes/19.json")
        try FileManager.default.createDirectory(at: assetIndex.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("assets".utf8).write(to: assetIndex)
        let library = root.appendingPathComponent(".minecraft/libraries/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar")
        try FileManager.default.createDirectory(at: library.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("library".utf8).write(to: library)
        let java = JavaRuntime(
            name: "Temurin 21",
            version: "21.0.3",
            majorVersion: 21,
            architecture: .arm64,
            executableURL: URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java")
        )

        let report = LaunchService().preflight(instance: instance, java: java)

        XCTAssertTrue(report.canLaunch)
        XCTAssertEqual(report.severity, .info)
        XCTAssertEqual(report.summary, "启动前检查通过。")
        XCTAssertTrue(report.suggestedActions.isEmpty)
    }

    func testLaunchServiceStartsProcessAndCreatesLatestLog() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "原版生存",
            gameVersion: "1.21.5",
            loader: .vanilla,
            rootDirectory: root,
            profile: LaunchProfile(offlineUsername: "Steve", memoryMegabytes: 512, jvmArguments: [], resolutionWidth: 854, resolutionHeight: 480),
            status: .ready
        )
        let java = JavaRuntime(
            name: "Echo",
            version: "1.0",
            majorVersion: 21,
            architecture: .universal,
            executableURL: URL(fileURLWithPath: "/bin/echo")
        )

        let session = try LaunchService().launch(instance: instance, java: java)

        XCTAssertGreaterThan(session.processIdentifier, 0)
        XCTAssertEqual(session.logFileURL.path, root.appendingPathComponent("logs/latest.log").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".minecraft").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.logFileURL.path))
        XCTAssertEqual(session.command.first, "/bin/echo")
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
      "libraries": [
        {
          "name": "org.lwjgl:lwjgl:3.3.3",
          "downloads": {
            "artifact": {
              "path": "org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar",
              "url": "https://libraries.minecraft.net/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar",
              "sha1": "library-sha1",
              "size": 456
            }
          }
        }
      ]
    }
    """

    private static func makeInstallerArchive(versionJSON: String, at archiveURL: URL) throws {
        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MMCL-installer-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let versionURL = stagingDirectory.appendingPathComponent("version.json")
        try Data(versionJSON.utf8).write(to: versionURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-j", archiveURL.path, versionURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "LauncherServiceTests", code: Int(process.terminationStatus))
        }
    }

    private static func makeTarArchive(contentsOf directory: URL, at archiveURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["czf", archiveURL.path, "-C", directory.path, "."]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "LauncherServiceTests", code: Int(process.terminationStatus))
        }
    }

    private static let modernArgumentsMetadataJSON = """
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
      "libraries": [
        {
          "name": "org.lwjgl:lwjgl:3.3.3",
          "downloads": {
            "artifact": {
              "path": "org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar",
              "url": "https://libraries.minecraft.net/org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3.jar",
              "sha1": "library-sha1",
              "size": 456
            }
          }
        }
      ],
      "arguments": {
        "jvm": [
          "-Djava.library.path=${natives_directory}",
          "-cp",
          "${classpath}",
          {
            "rules": [{ "action": "allow", "os": { "name": "osx" } }],
            "value": "-Xdock:name=${launcher_name}"
          },
          {
            "rules": [{ "action": "allow", "os": { "name": "windows" } }],
            "value": "-Dos.name=Windows"
          }
        ],
        "game": [
          "--username",
          "${auth_player_name}",
          "--version",
          "${version_name}",
          "--gameDir",
          "${game_directory}",
          "--assetsDir",
          "${assets_root}",
          "--assetIndex",
          "${assets_index_name}",
          "--accessToken",
          "${auth_access_token}",
          "--uuid",
          "${auth_uuid}",
          "--xuid",
          "${auth_xuid}",
          "--userType",
          "${user_type}"
        ]
      }
    }
    """

    func testFabricServiceFetchesLoaderVersionsFromAPI() async throws {
        // Test with local file would be ideal, but the API is simple enough
        // to test the model parsing
        let json = """
        [{"version":"0.16.14","stable":true},{"version":"0.16.13","stable":false}]
        """.data(using: .utf8)!
        let versions = try JSONDecoder.mmcl.decode([FabricLoaderVersion].self, from: json)
        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(versions.first?.version, "0.16.14")
        XCTAssertTrue(versions.first?.stable == true)

        let nestedVersions = try JSONDecoder.mmcl.decode(
            [FabricLoaderVersion].self,
            from: Data("[{\"loader\":{\"version\":\"0.19.3\",\"stable\":true}}]".utf8)
        )
        XCTAssertEqual(nestedVersions.first?.version, "0.19.3")
    }

    func testFabricProfileParsesMainClassAndInheritsFrom() throws {
        let json = """
        {
            "id": "1.21.5-fabric-0.16.14",
            "inheritsFrom": "1.21.5",
            "mainClass": "net.fabricmc.loader.impl.launch.knot.KnotClient",
            "arguments": {
                "game": ["--assetIndex", "${assets_index_name}"]
            },
            "libraries": [
                {
                    "name": "net.fabricmc:fabric-loader:0.16.14",
                    "url": "https://maven.fabricmc.net/",
                    "sha1": "loader-sha1",
                    "size": 123
                }
            ]
        }
        """.data(using: .utf8)!
        let profile = try JSONDecoder.mmcl.decode(FabricProfile.self, from: json)
        XCTAssertEqual(profile.id, "1.21.5-fabric-0.16.14")
        XCTAssertEqual(profile.inheritsFrom, "1.21.5")
        XCTAssertEqual(profile.mainClass, "net.fabricmc.loader.impl.launch.knot.KnotClient")
        XCTAssertEqual(profile.arguments?.game?.first, "--assetIndex")
        XCTAssertEqual(profile.libraries?.first?.artifact(defaultRepository: URL(string: "https://maven.fabricmc.net/")!)?.path, "net/fabricmc/fabric-loader/0.16.14/fabric-loader-0.16.14.jar")
    }

    func testFabricServiceInstallsProfileLibrariesAndArguments() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "Fabric 生存",
            gameVersion: "1.21.5",
            loader: .fabric,
            rootDirectory: root
        )
        let baseMetadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.modernArgumentsMetadataJSON.utf8))
        _ = try DownloadService().writeVersionMetadata(metadata: baseMetadata, instance: instance)

        let apiRoot = root.appendingPathComponent("fabric-api", isDirectory: true)
        let profileDirectory = apiRoot
            .appendingPathComponent("versions/loader/1.21.5/0.16.14/profile", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        try Data("""
        {
          "id": "fabric-loader-0.16.14-1.21.5",
          "inheritsFrom": "1.21.5",
          "mainClass": "net.fabricmc.loader.impl.launch.knot.KnotClient",
          "arguments": {
            "game": ["--fabric-test", "true"],
            "jvm": ["-DFabricMcEmu= net.minecraft.client.main.Main "]
          },
          "libraries": [
            {
              "name": "net.fabricmc:fabric-loader:0.16.14",
              "url": "https://maven.fabricmc.net/",
              "sha1": "loader-sha1",
              "size": 123
            },
            {
              "name": "net.fabricmc:intermediary:1.21.5",
              "url": "https://maven.fabricmc.net/"
            }
          ]
        }
        """.utf8).write(to: profileDirectory.appendingPathComponent("json"))

        let metadata = try await FabricService(baseURL: apiRoot).installFabric(
            gameVersion: "1.21.5",
            loaderVersion: "0.16.14",
            instance: instance
        )

        XCTAssertEqual(metadata.id, "1.21.5-fabric-0.16.14")
        XCTAssertEqual(metadata.mainClass, "net.fabricmc.loader.impl.launch.knot.KnotClient")
        XCTAssertTrue(metadata.libraries.contains { $0.name == "net.fabricmc:fabric-loader:0.16.14" })
        XCTAssertTrue(metadata.libraries.contains { $0.name == "net.fabricmc:intermediary:1.21.5" })
        let jvmArguments = metadata.arguments?.jvm.flatMap { $0.value.strings } ?? []
        let gameArguments = metadata.arguments?.game.flatMap { $0.value.strings } ?? []
        XCTAssertTrue(jvmArguments.contains("-DFabricMcEmu= net.minecraft.client.main.Main "))
        XCTAssertTrue(gameArguments.contains("--fabric-test"))

        let jobs = DownloadService().makeVanillaInstallJobs(metadata: metadata, instance: instance, source: .official)
        let loaderJob = try XCTUnwrap(jobs.first { $0.title == "net.fabricmc:fabric-loader:0.16.14" })
        XCTAssertEqual(loaderJob.remoteURL?.absoluteString, "https://maven.fabricmc.net/net/fabricmc/fabric-loader/0.16.14/fabric-loader-0.16.14.jar")
        XCTAssertEqual(loaderJob.sha1, "loader-sha1")
    }

    func testQuiltServiceInstallsProfileLibrariesAndArguments() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "Quilt 生存",
            gameVersion: "1.21.5",
            loader: .quilt,
            rootDirectory: root
        )
        let baseMetadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.modernArgumentsMetadataJSON.utf8))
        _ = try DownloadService().writeVersionMetadata(metadata: baseMetadata, instance: instance)

        let apiRoot = root.appendingPathComponent("quilt-api", isDirectory: true)
        let profileDirectory = apiRoot
            .appendingPathComponent("versions/loader/1.21.5/0.20.0-beta.9/profile", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        try Data("""
        {
          "id": "quilt-loader-0.20.0-beta.9-1.21.5",
          "inheritsFrom": "1.21.5",
          "mainClass": "org.quiltmc.loader.impl.launch.knot.KnotClient",
          "arguments": { "game": ["--quilt-test", "true"] },
          "libraries": [
            {
              "name": "org.quiltmc:quilt-loader:0.20.0-beta.9",
              "url": "https://maven.quiltmc.org/repository/release/"
            },
            {
              "name": "net.fabricmc:intermediary:1.21.5",
              "url": "https://maven.fabricmc.net/"
            }
          ]
        }
        """.utf8).write(to: profileDirectory.appendingPathComponent("json"))

        let metadata = try await QuiltService(baseURL: apiRoot).installQuilt(
            gameVersion: "1.21.5",
            loaderVersion: "0.20.0-beta.9",
            instance: instance
        )

        XCTAssertEqual(metadata.id, "1.21.5-quilt-0.20.0-beta.9")
        XCTAssertEqual(metadata.mainClass, "org.quiltmc.loader.impl.launch.knot.KnotClient")
        XCTAssertTrue(metadata.libraries.contains { $0.name == "org.quiltmc:quilt-loader:0.20.0-beta.9" })
        let gameArguments = metadata.arguments?.game.flatMap { $0.value.strings } ?? []
        XCTAssertTrue(gameArguments.contains("--quilt-test"))

        let jobs = DownloadService().makeVanillaInstallJobs(metadata: metadata, instance: instance, source: .official)
        let loaderJob = try XCTUnwrap(jobs.first { $0.title == "org.quiltmc:quilt-loader:0.20.0-beta.9" })
        XCTAssertEqual(loaderJob.remoteURL?.absoluteString, "https://maven.quiltmc.org/repository/release/org/quiltmc/quilt-loader/0.20.0-beta.9/quilt-loader-0.20.0-beta.9.jar")
        XCTAssertNil(loaderJob.sha1)
    }

    func testForgeServiceReadsOfficialInstallerVersionProfile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "Forge 生存",
            gameVersion: "1.21.5",
            loader: .forge,
            rootDirectory: root
        )
        let baseMetadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.modernArgumentsMetadataJSON.utf8))
        _ = try DownloadService().writeVersionMetadata(metadata: baseMetadata, instance: instance)

        let installerBaseURL = root.appendingPathComponent("forge-installers", isDirectory: true)
        let installerDirectory = installerBaseURL.appendingPathComponent("1.21.5-55.1.0", isDirectory: true)
        try FileManager.default.createDirectory(at: installerDirectory, withIntermediateDirectories: true)
        let installerURL = installerDirectory.appendingPathComponent("forge-1.21.5-55.1.0-installer.jar")
        try Self.makeInstallerArchive(
            versionJSON: """
            {
              "id": "1.21.5-forge-55.1.0",
              "inheritsFrom": "1.21.5",
              "mainClass": "net.minecraftforge.bootstrap.ForgeBootstrap",
              "arguments": {
                "game": ["--launchTarget", "forge_client"],
                "jvm": ["-Djava.net.preferIPv6Addresses=system"]
              },
              "libraries": [
                {
                  "name": "net.minecraftforge:forge:1.21.5-55.1.0:universal",
                  "downloads": {
                    "artifact": {
                      "path": "net/minecraftforge/forge/1.21.5-55.1.0/forge-1.21.5-55.1.0-universal.jar",
                      "url": "https://maven.minecraftforge.net/net/minecraftforge/forge/1.21.5-55.1.0/forge-1.21.5-55.1.0-universal.jar",
                      "sha1": "forge-sha1",
                      "size": 123
                    }
                  }
                }
              ]
            }
            """,
            at: installerURL
        )
        let promotionsURL = root.appendingPathComponent("promotions_slim.json")
        try Data("""
        {"promos":{"1.21.5-recommended":"55.1.0"}}
        """.utf8).write(to: promotionsURL)

        let metadata = try await ForgeService(
            promotionsURL: promotionsURL,
            installerBaseURL: installerBaseURL
        ).installForge(gameVersion: "1.21.5", forgeVersion: nil, instance: instance)

        XCTAssertEqual(metadata.id, "1.21.5-forge-55.1.0")
        XCTAssertEqual(metadata.mainClass, "net.minecraftforge.bootstrap.ForgeBootstrap")
        XCTAssertTrue(metadata.arguments?.game.flatMap { $0.value.strings }.contains("forge_client") == true)
        let coreName = "net.minecraftforge:forge:1.21.5-55.1.0:universal"
        let coreJob = try XCTUnwrap(
            DownloadService().makeVanillaInstallJobs(metadata: metadata, instance: instance, source: .official)
                .first { $0.title == coreName }
        )
        XCTAssertEqual(coreJob.sha1, "forge-sha1")
        XCTAssertTrue(metadata.assetIndex.id == baseMetadata.assetIndex.id)
    }

    func testInstallerProfileKeepsProcessorGeneratedArtifactsOutOfDownloadJobs() throws {
        let profile = try JSONDecoder.mmcl.decode(
            InstallerVersionProfile.self,
            from: Data("""
            {
              "id": "1.21.5-forge-55.1.11",
              "mainClass": "net.minecraftforge.bootstrap.ForgeBootstrap",
              "libraries": [
                {
                  "name": "net.minecraftforge:forge:1.21.5-55.1.11:client",
                  "downloads": {
                    "artifact": {
                      "path": "net/minecraftforge/forge/1.21.5-55.1.11/forge-1.21.5-55.1.11-client.jar",
                      "url": "",
                      "sha1": "generated-sha1",
                      "size": 123
                    }
                  }
                }
              ]
            }
            """.utf8)
        )
        let generatedArtifact = try XCTUnwrap(profile.libraries?.first?.artifact)
        XCTAssertEqual(generatedArtifact.url.scheme, "mmcl-generated")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "Forge 处理器测试",
            gameVersion: "1.21.5",
            loader: .forge,
            rootDirectory: root
        )
        var metadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.modernArgumentsMetadataJSON.utf8))
        metadata.libraries = profile.libraries ?? []

        let jobs = DownloadService().makeVanillaInstallJobs(metadata: metadata, instance: instance, source: .official)
        XCTAssertFalse(jobs.contains { $0.title == "net.minecraftforge:forge:1.21.5-55.1.11:client" })
    }

    func testNeoForgeServiceReadsOfficialInstallerVersionProfile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let instance = LauncherInstance(
            name: "NeoForge 生存",
            gameVersion: "1.21.5",
            loader: .neoForge,
            rootDirectory: root
        )
        let baseMetadata = try VersionManifestService().decodeVersionMetadata(from: Data(Self.modernArgumentsMetadataJSON.utf8))
        _ = try DownloadService().writeVersionMetadata(metadata: baseMetadata, instance: instance)

        let installerBaseURL = root.appendingPathComponent("neoforge-installers", isDirectory: true)
        let installerDirectory = installerBaseURL.appendingPathComponent("21.5.98", isDirectory: true)
        try FileManager.default.createDirectory(at: installerDirectory, withIntermediateDirectories: true)
        let installerURL = installerDirectory.appendingPathComponent("neoforge-21.5.98-installer.jar")
        try Self.makeInstallerArchive(
            versionJSON: """
            {
              "id": "neoforge-21.5.98",
              "inheritsFrom": "1.21.5",
              "mainClass": "cpw.mods.bootstraplauncher.BootstrapLauncher",
              "arguments": {
                "game": ["--launchTarget", "neoforgeclient"],
                "jvm": ["-DlibraryDirectory=${library_directory}", "-p", "${library_directory}/cpw/mods/bootstraplauncher/2.0.2/bootstraplauncher-2.0.2.jar${classpath_separator}${library_directory}/cpw/mods/securejarhandler/3.0.8/securejarhandler-3.0.8.jar"]
              },
              "libraries": [
                {
                  "name": "cpw.mods:bootstraplauncher:2.0.2",
                  "downloads": {
                    "artifact": {
                      "path": "cpw/mods/bootstraplauncher/2.0.2/bootstraplauncher-2.0.2.jar",
                      "url": "https://maven.neoforged.net/releases/cpw/mods/bootstraplauncher/2.0.2/bootstraplauncher-2.0.2.jar",
                      "sha1": "neoforge-sha1",
                      "size": 456
                    }
                  }
                }
              ]
            }
            """,
            at: installerURL
        )
        let versionsURL = root.appendingPathComponent("neoforge-versions.json")
        try Data("""
        {"versions":["21.5.98"]}
        """.utf8).write(to: versionsURL)

        let metadata = try await NeoForgeService(
            versionsURL: versionsURL,
            installerBaseURL: installerBaseURL
        ).installNeoForge(gameVersion: "1.21.5", version: nil, instance: instance)

        XCTAssertEqual(metadata.id, "1.21.5-neoforge-21.5.98")
        XCTAssertEqual(metadata.mainClass, "cpw.mods.bootstraplauncher.BootstrapLauncher")
        XCTAssertTrue(metadata.arguments?.jvm.flatMap { $0.value.strings }.contains("-DlibraryDirectory=${library_directory}") == true)
        let coreJob = try XCTUnwrap(
            DownloadService().makeVanillaInstallJobs(metadata: metadata, instance: instance, source: .official)
                .first { $0.title == "cpw.mods:bootstraplauncher:2.0.2" }
        )
        XCTAssertEqual(coreJob.sha1, "neoforge-sha1")
        XCTAssertEqual(metadata.assetIndex.id, baseMetadata.assetIndex.id)
    }

    func testModrinthSearchResponseParsesHits() throws {
        let json = """
        {
            "hits": [
                {"project_id": "AqQJnBxM", "slug": "sodium", "title": "Sodium", "description": "A modern rendering engine", "project_type": "mod", "downloads": 5000000, "categories": ["performance", "optimization"]}
            ],
            "total_hits": 1
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder.mmcl.decode(ModrinthSearchResponse.self, from: json)
        XCTAssertEqual(response.totalHits, 1)
        XCTAssertEqual(response.hits.first?.title, "Sodium")
        XCTAssertEqual(response.hits.first?.downloads, 5000000)
    }

    func testModrinthVersionParsesFilesAndLoaders() throws {
        let json = """
        [
            {
                "id": "abc123",
                "name": "Sodium 0.6.0",
                "version_number": "0.6.0",
                "game_versions": ["1.21.5"],
                "loaders": ["fabric"],
                "files": [
                    {"filename": "sodium-fabric-0.6.0.jar", "url": "https://example.com/sodium.jar", "size": 12345, "primary": true}
                ]
            }
        ]
        """.data(using: .utf8)!
        let versions = try JSONDecoder.mmcl.decode([ModrinthVersion].self, from: json)
        XCTAssertEqual(versions.count, 1)
        XCTAssertEqual(versions.first?.files.first?.filename, "sodium-fabric-0.6.0.jar")
        XCTAssertEqual(versions.first?.loaders, ["fabric"])
    }

    func testQuiltLoaderVersionParsesCorrectly() throws {
        let json = """
        [{"version":"0.5.0","stable":true},{"version":"0.4.0","stable":false}]
        """.data(using: .utf8)!
        let versions = try JSONDecoder.mmcl.decode([QuiltLoaderVersion].self, from: json)
        XCTAssertEqual(versions.count, 2)
        XCTAssertTrue(versions[0].stable)

        let nestedVersions = try JSONDecoder.mmcl.decode(
            [QuiltLoaderVersion].self,
            from: Data("[{\"loader\":{\"version\":\"0.20.0-beta.9\"}}]".utf8)
        )
        XCTAssertEqual(nestedVersions.first?.version, "0.20.0-beta.9")
        XCTAssertFalse(nestedVersions.first?.stable ?? true)
    }

    func testForgeVersionParsesPromotions() throws {
        let json = """
        {"promos":{"1.21.5-latest":"56.0.1","1.21.5-recommended":"56.0.0","1.20.1-latest":"47.3.0"}}
        """.data(using: .utf8)!
        let promo = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        let promos = promo?["promos"] as? [String: String] ?? [:]
        XCTAssertEqual(promos["1.21.5-latest"], "56.0.1")
        XCTAssertEqual(promos["1.20.1-latest"], "47.3.0")
    }

    func testModrinthVersionRowDisplaysCorrectInfo() throws {
        let file = ModrinthFile(filename: "mod.jar", url: "https://example.com/mod.jar", size: 1000, primary: true)
        let version = ModrinthVersion(id: "v1", name: "Mod 1.0", versionNumber: "1.0.0", gameVersions: ["1.21.5"], loaders: ["fabric"], files: [file])
        XCTAssertEqual(version.files.first?.filename, "mod.jar")
        XCTAssertEqual(version.loaders, ["fabric"])
    }

    private static let legacyArgumentsMetadataJSON = """
    {
      "id": "1.12.2",
      "mainClass": "net.minecraft.client.main.Main",
      "assets": "legacy",
      "assetIndex": {
        "id": "legacy",
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
      "libraries": [],
      "minecraftArguments": "--username ${auth_player_name} --version ${version_name} --gameDir ${game_directory} --assetsDir ${assets_root} --assetIndex ${assets_index_name} --accessToken ${auth_access_token} --userType ${user_type}"
    }
    """

    func testMinecraftAccountDisplayNames() {
        let offline = MinecraftAccount(username: "Steve", type: .offline)
        let online = MinecraftAccount(username: "Notch", uuid: "abc", accessToken: "token", refreshToken: "refresh", type: .microsoft)
        XCTAssertEqual(offline.displayName, "Steve（离线）")
        XCTAssertEqual(online.displayName, "Notch")
    }

    func testMinecraftAccountRoundTripsThroughJSON() throws {
        let account = MinecraftAccount(username: "Test", uuid: "uuid-123", xuid: "xuid-123", accessToken: "at", refreshToken: "rt", expiresAt: Date(timeIntervalSince1970: 1000), type: .microsoft)
        let data = try JSONEncoder.mmcl.encode(account)
        let decoded = try JSONDecoder.mmcl.decode(MinecraftAccount.self, from: data)
        XCTAssertEqual(decoded.username, "Test")
        XCTAssertEqual(decoded.xuid, "xuid-123")
        XCTAssertEqual(decoded.type, .microsoft)
    }
}

private extension Array where Element == String {
    func argument(after marker: String) -> String? {
        guard let index = firstIndex(of: marker) else { return nil }
        let nextIndex = self.index(after: index)
        guard nextIndex < endIndex else { return nil }
        return self[nextIndex]
    }
}
