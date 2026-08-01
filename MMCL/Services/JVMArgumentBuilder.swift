import Foundation

/// Inputs used to build the JVM portion of a Minecraft launch command.
///
/// Version metadata is kept separate from user arguments so the builder can
/// add safe defaults without ever overwriting an explicit option. User
/// arguments are emitted last, which also gives them the final say when a
/// version JSON contains the same JVM option.
struct JVMArgumentBuildContext {
    var javaMajorVersion: Int
    var javaArchitecture: RuntimeArchitecture
    var physicalMemoryBytes: UInt64
    var memoryMegabytes: Int
    var nativeDirectory: URL
    var gameDirectory: URL
    var versionArguments: [String]
    var userArguments: [String]
    var useGeneratedArguments: Bool
    var useOptimizingArguments: Bool
    var isMacOS: Bool
    var launcherName: String

    init(
        javaMajorVersion: Int,
        javaArchitecture: RuntimeArchitecture,
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory,
        memoryMegabytes: Int,
        nativeDirectory: URL,
        gameDirectory: URL,
        versionArguments: [String] = [],
        userArguments: [String] = [],
        useGeneratedArguments: Bool = true,
        useOptimizingArguments: Bool = true,
        isMacOS: Bool = true,
        launcherName: String = "MMCL"
    ) {
        self.javaMajorVersion = javaMajorVersion
        self.javaArchitecture = javaArchitecture
        self.physicalMemoryBytes = physicalMemoryBytes
        self.memoryMegabytes = memoryMegabytes
        self.nativeDirectory = nativeDirectory
        self.gameDirectory = gameDirectory
        self.versionArguments = versionArguments
        self.userArguments = userArguments
        self.useGeneratedArguments = useGeneratedArguments
        self.useOptimizingArguments = useOptimizingArguments
        self.isMacOS = isMacOS
        self.launcherName = launcherName
    }
}

/// Builds JVM arguments using the same broad layering strategy as HMCL:
/// metadata and launcher defaults are conservative, while explicit user
/// arguments are never replaced by generated values.
struct JVMArgumentBuilder {
    func build(_ context: JVMArgumentBuildContext) -> [String] {
        let versionArguments = context.versionArguments
        let userArguments = context.userArguments
        let effectiveVersionArguments = versionArgumentsByApplyingUserOverrides(
            versionArguments,
            userArguments: userArguments
        )
        let existingArguments = expandedArguments(forConflictDetection: versionArguments + userArguments)
        var generatedArguments: [String] = []

        // Memory and native loading are required launch defaults. They remain
        // enabled even when the user disables optional generated JVM tuning.
        appendDefault(
            "-Xmx\(max(512, context.memoryMegabytes))m",
            to: &generatedArguments,
            existing: existingArguments
        )
        appendDefault(
            "-Djava.library.path=\(context.nativeDirectory.path)",
            to: &generatedArguments,
            existing: existingArguments
        )

        guard context.useGeneratedArguments else {
            return effectiveVersionArguments + generatedArguments + userArguments
        }

        appendDefault("-Dfile.encoding=UTF-8", to: &generatedArguments, existing: existingArguments)
        if context.javaMajorVersion >= 19 {
            appendDefault("-Dstdout.encoding=UTF-8", to: &generatedArguments, existing: existingArguments)
            appendDefault("-Dstderr.encoding=UTF-8", to: &generatedArguments, existing: existingArguments)
        } else {
            appendDefault("-Dsun.stdout.encoding=UTF-8", to: &generatedArguments, existing: existingArguments)
            appendDefault("-Dsun.stderr.encoding=UTF-8", to: &generatedArguments, existing: existingArguments)
        }

        appendDefault(
            "-Djava.rmi.server.useCodebaseOnly=true",
            to: &generatedArguments,
            existing: existingArguments
        )
        appendDefault(
            "-Dcom.sun.jndi.rmi.object.trustURLCodebase=false",
            to: &generatedArguments,
            existing: existingArguments
        )
        appendDefault(
            "-Dcom.sun.jndi.cosnaming.object.trustURLCodebase=false",
            to: &generatedArguments,
            existing: existingArguments
        )
        appendDefault("-Dlog4j2.formatMsgNoLookups=true", to: &generatedArguments, existing: existingArguments)

        if !hasProxyConfiguration(in: existingArguments) {
            appendDefault("-Djava.net.useSystemProxies=true", to: &generatedArguments, existing: existingArguments)
        }

        if context.isMacOS {
            appendDefault(
                "-Xdock:name=\(context.launcherName)",
                to: &generatedArguments,
                existing: existingArguments
            )
            appendDefault(
                "-Duser.home=\(context.gameDirectory.deletingLastPathComponent().path)",
                to: &generatedArguments,
                existing: existingArguments
            )
        }

        guard context.useOptimizingArguments else {
            return effectiveVersionArguments + generatedArguments + userArguments
        }

        if context.javaMajorVersion >= 8 {
            appendDefault("-XX:+UnlockExperimentalVMOptions", to: &generatedArguments, existing: existingArguments)
            appendDefault("-XX:+UnlockDiagnosticVMOptions", to: &generatedArguments, existing: existingArguments)

            let garbageCollector = selectedGarbageCollector(in: existingArguments)
            let shouldUseG1 = garbageCollector == nil || garbageCollector == "UseG1GC"
            let g1IsDisabled = garbageCollector == "-UseG1GC"

            if garbageCollector == nil {
                appendDefault("-XX:+UseG1GC", to: &generatedArguments, existing: existingArguments)
            }

            if shouldUseG1, !g1IsDisabled {
                [
                    "-XX:G1MixedGCCountTarget=5",
                    "-XX:G1NewSizePercent=20",
                    "-XX:G1ReservePercent=20",
                    "-XX:MaxGCPauseMillis=50",
                    "-XX:G1HeapRegionSize=32m"
                ].forEach {
                    appendDefault($0, to: &generatedArguments, existing: existingArguments)
                }
            }

            appendDefault("-XX:-OmitStackTraceInFastThrow", to: &generatedArguments, existing: existingArguments)
        }

        if context.javaMajorVersion <= 8 {
            appendDefault("-XX:MaxInlineLevel=15", to: &generatedArguments, existing: existingArguments)
        }

        if context.javaMajorVersion >= 8,
           context.javaArchitecture.is64Bit,
           context.physicalMemoryBytes > 4 * 1024 * 1024 * 1024 {
            [
                "-XX:-DontCompileHugeMethods",
                "-XX:MaxNodeLimit=240000",
                "-XX:NodeLimitFudgeFactor=8000",
                "-XX:TieredCompileTaskTimeout=10000",
                "-XX:ReservedCodeCacheSize=400M"
            ].forEach {
                appendDefault($0, to: &generatedArguments, existing: existingArguments)
            }

            if context.javaMajorVersion >= 9 {
                [
                    "-XX:NonNMethodCodeHeapSize=12M",
                    "-XX:ProfiledCodeHeapSize=194M"
                ].forEach {
                    appendDefault($0, to: &generatedArguments, existing: existingArguments)
                }
            }

            appendDefault("-XX:NmethodSweepActivity=1", to: &generatedArguments, existing: existingArguments)
        }

        if (25...26).contains(context.javaMajorVersion), context.javaArchitecture.is64Bit {
            appendDefault("-XX:+UseCompactObjectHeaders", to: &generatedArguments, existing: existingArguments)
        }

        if context.javaMajorVersion == 16 {
            appendDefault("--illegal-access=permit", to: &generatedArguments, existing: existingArguments)
        } else if (24...25).contains(context.javaMajorVersion) {
            appendDefault(
                "--sun-misc-unsafe-memory-access=allow",
                to: &generatedArguments,
                existing: existingArguments
            )
        }

        return effectiveVersionArguments + generatedArguments + userArguments
    }

    private func versionArgumentsByApplyingUserOverrides(
        _ versionArguments: [String],
        userArguments: [String]
    ) -> [String] {
        let userKeys = Set(
            expandedArguments(forConflictDetection: userArguments)
                .compactMap { optionKey(for: $0) }
        )
        guard !userKeys.isEmpty else { return versionArguments }

        var result: [String] = []
        var index = 0
        while index < versionArguments.count {
            let argument = versionArguments[index]
            guard let key = optionKey(for: argument), userKeys.contains(key) else {
                result.append(argument)
                index += 1
                continue
            }

            // -cp/--class-path consumes the following classpath token.
            index += key == "-cp" ? 2 : 1
        }
        return result
    }

    private func appendDefault(_ argument: String, to generated: inout [String], existing: [String]) {
        let allArguments = existing + generated
        guard !hasConflictingOption(argument, in: allArguments) else { return }
        generated.append(argument)
    }

    private func hasConflictingOption(_ argument: String, in arguments: [String]) -> Bool {
        guard let key = optionKey(for: argument) else { return false }
        return arguments.contains { optionKey(for: $0) == key }
    }

    private func optionKey(for argument: String) -> String? {
        guard argument.hasPrefix("-") else { return nil }

        if argument.hasPrefix("-D"), let equalsIndex = argument.firstIndex(of: "=") {
            return String(argument[..<equalsIndex])
        }

        if argument.hasPrefix("-XX:") {
            let body = argument.dropFirst(4)
            let normalized = body.first == "+" || body.first == "-" ? body.dropFirst() : body[...]
            let key = normalized.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true).first
            return key.map { "-XX:\($0)" }
        }

        if argument.hasPrefix("-Xmx") { return "-Xmx" }
        if argument.hasPrefix("-Xms") { return "-Xms" }
        if argument.hasPrefix("-Xmn") { return "-Xmn" }
        if argument.hasPrefix("-Xss") { return "-Xss" }
        if argument == "-cp" || argument == "--class-path" { return "-cp" }

        return String(argument.split(separator: "=", maxSplits: 1).first ?? Substring(argument))
    }

    private func selectedGarbageCollector(in arguments: [String]) -> String? {
        let collectors = arguments.compactMap { argument -> String? in
            guard argument.hasPrefix("-XX:+Use") || argument.hasPrefix("-XX:-Use") else { return nil }
            let body = argument.dropFirst(5)
            guard body.hasSuffix("GC") else { return nil }
            return String(argument.hasPrefix("-XX:-") ? "-" : "") + String(body)
        }
        return collectors.last
    }

    private func hasProxyConfiguration(in arguments: [String]) -> Bool {
        arguments.contains { argument in
            [
                "-Dhttp.proxyHost=",
                "-Dhttps.proxyHost=",
                "-DsocksProxyHost=",
                "-Djava.net.useSystemProxies="
            ].contains { argument.hasPrefix($0) }
        }
    }

    private func expandedArguments(forConflictDetection arguments: [String], depth: Int = 0) -> [String] {
        guard depth < 3 else { return arguments }

        return arguments.flatMap { argument in
            guard argument.hasPrefix("@"), argument.count > 1 else { return [argument] }
            let path = String(argument.dropFirst())
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
                return [argument]
            }
            let tokens = contents
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
            return expandedArguments(forConflictDetection: tokens, depth: depth + 1)
        }
    }
}

private extension RuntimeArchitecture {
    var is64Bit: Bool {
        switch self {
        case .arm64, .x86_64, .universal: return true
        case .unknown: return false
        }
    }
}
