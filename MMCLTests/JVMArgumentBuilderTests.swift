import XCTest
@testable import MMCL

final class JVMArgumentBuilderTests: XCTestCase {
    private let builder = JVMArgumentBuilder()

    func testGeneratedArgumentsAddHMCLStyleDefaultsForJava21() {
        let arguments = builder.build(
            JVMArgumentBuildContext(
                javaMajorVersion: 21,
                javaArchitecture: .arm64,
                physicalMemoryBytes: 16 * 1024 * 1024 * 1024,
                memoryMegabytes: 4096,
                nativeDirectory: URL(fileURLWithPath: "/tmp/mmcl/natives"),
                gameDirectory: URL(fileURLWithPath: "/tmp/mmcl/.minecraft")
            )
        )

        XCTAssertTrue(arguments.contains("-Xmx4096m"))
        XCTAssertTrue(arguments.contains("-Djava.library.path=/tmp/mmcl/natives"))
        XCTAssertTrue(arguments.contains("-Dfile.encoding=UTF-8"))
        XCTAssertTrue(arguments.contains("-Dstdout.encoding=UTF-8"))
        XCTAssertTrue(arguments.contains("-Dstderr.encoding=UTF-8"))
        XCTAssertTrue(arguments.contains("-Dlog4j2.formatMsgNoLookups=true"))
        XCTAssertTrue(arguments.contains("-XX:+UseG1GC"))
        XCTAssertTrue(arguments.contains("-XX:G1MixedGCCountTarget=5"))
        XCTAssertTrue(arguments.contains("-XX:ReservedCodeCacheSize=400M"))
        XCTAssertTrue(arguments.contains("-XX:NonNMethodCodeHeapSize=12M"))
        XCTAssertTrue(arguments.contains("-Xdock:name=MMCL"))
        XCTAssertTrue(arguments.contains("-Duser.home=/tmp/mmcl"))
    }

    func testExplicitUserArgumentsWinAndSelectAnotherGarbageCollector() {
        let arguments = builder.build(
            JVMArgumentBuildContext(
                javaMajorVersion: 21,
                javaArchitecture: .arm64,
                physicalMemoryBytes: 16 * 1024 * 1024 * 1024,
                memoryMegabytes: 4096,
                nativeDirectory: URL(fileURLWithPath: "/tmp/mmcl/natives"),
                gameDirectory: URL(fileURLWithPath: "/tmp/mmcl/.minecraft"),
                versionArguments: ["-Xmx2048m", "-Dfile.encoding=Shift_JIS"],
                userArguments: ["-Xmx8192m", "-XX:+UseZGC", "-Dfile.encoding=GBK"]
            )
        )

        XCTAssertEqual(arguments.filter { $0.hasPrefix("-Xmx") }, ["-Xmx8192m"])
        XCTAssertFalse(arguments.contains("-Xmx4096m"))
        XCTAssertTrue(arguments.contains("-XX:+UseZGC"))
        XCTAssertFalse(arguments.contains("-XX:+UseG1GC"))
        XCTAssertFalse(arguments.contains("-XX:G1MixedGCCountTarget=5"))
        XCTAssertFalse(arguments.contains("-Dfile.encoding=UTF-8"))
        XCTAssertEqual(arguments.last, "-Dfile.encoding=GBK")
    }

    func testArgumentFileParticipatesInDefaultConflictDetection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let argumentFile = root.appendingPathComponent("jvm.options")
        try "-Xmx8192m\n-XX:+UseZGC\n".write(to: argumentFile, atomically: true, encoding: .utf8)

        let arguments = builder.build(
            JVMArgumentBuildContext(
                javaMajorVersion: 21,
                javaArchitecture: .arm64,
                memoryMegabytes: 4096,
                nativeDirectory: root.appendingPathComponent("natives"),
                gameDirectory: root.appendingPathComponent(".minecraft"),
                userArguments: ["@\(argumentFile.path)"]
            )
        )

        XCTAssertTrue(arguments.contains("@\(argumentFile.path)"))
        XCTAssertFalse(arguments.contains("-Xmx4096m"))
        XCTAssertFalse(arguments.contains("-XX:+UseG1GC"))
    }

    func testJavaVersionGatesModernEncodingAndCompatibilityOptions() {
        let java8 = builder.build(
            JVMArgumentBuildContext(
                javaMajorVersion: 8,
                javaArchitecture: .x86_64,
                memoryMegabytes: 2048,
                nativeDirectory: URL(fileURLWithPath: "/tmp/natives"),
                gameDirectory: URL(fileURLWithPath: "/tmp/.minecraft")
            )
        )
        XCTAssertTrue(java8.contains("-Dsun.stdout.encoding=UTF-8"))
        XCTAssertFalse(java8.contains("-Dstdout.encoding=UTF-8"))
        XCTAssertTrue(java8.contains("-XX:MaxInlineLevel=15"))

        let java16 = builder.build(
            JVMArgumentBuildContext(
                javaMajorVersion: 16,
                javaArchitecture: .arm64,
                memoryMegabytes: 2048,
                nativeDirectory: URL(fileURLWithPath: "/tmp/natives"),
                gameDirectory: URL(fileURLWithPath: "/tmp/.minecraft")
            )
        )
        XCTAssertTrue(java16.contains("--illegal-access=permit"))

        let java25 = builder.build(
            JVMArgumentBuildContext(
                javaMajorVersion: 25,
                javaArchitecture: .arm64,
                memoryMegabytes: 2048,
                nativeDirectory: URL(fileURLWithPath: "/tmp/natives"),
                gameDirectory: URL(fileURLWithPath: "/tmp/.minecraft")
            )
        )
        XCTAssertTrue(java25.contains("--sun-misc-unsafe-memory-access=allow"))
        XCTAssertTrue(java25.contains("-XX:+UseCompactObjectHeaders"))
    }

    func testGeneratedAndOptimizingArgumentsCanBeDisabledIndependently() {
        let arguments = builder.build(
            JVMArgumentBuildContext(
                javaMajorVersion: 21,
                javaArchitecture: .arm64,
                memoryMegabytes: 4096,
                nativeDirectory: URL(fileURLWithPath: "/tmp/natives"),
                gameDirectory: URL(fileURLWithPath: "/tmp/.minecraft"),
                useGeneratedArguments: true,
                useOptimizingArguments: false
            )
        )

        XCTAssertTrue(arguments.contains("-Xmx4096m"))
        XCTAssertTrue(arguments.contains("-Dfile.encoding=UTF-8"))
        XCTAssertFalse(arguments.contains("-XX:+UseG1GC"))
        XCTAssertFalse(arguments.contains("-XX:MaxGCPauseMillis=50"))

        let noGeneratedArguments = builder.build(
            JVMArgumentBuildContext(
                javaMajorVersion: 21,
                javaArchitecture: .arm64,
                memoryMegabytes: 4096,
                nativeDirectory: URL(fileURLWithPath: "/tmp/natives"),
                gameDirectory: URL(fileURLWithPath: "/tmp/.minecraft"),
                useGeneratedArguments: false,
                useOptimizingArguments: true
            )
        )
        XCTAssertTrue(noGeneratedArguments.contains("-Xmx4096m"))
        XCTAssertTrue(noGeneratedArguments.contains("-Djava.library.path=/tmp/natives"))
        XCTAssertFalse(noGeneratedArguments.contains("-Dfile.encoding=UTF-8"))
        XCTAssertFalse(noGeneratedArguments.contains("-XX:+UseG1GC"))
    }
}
