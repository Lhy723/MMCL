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
    private struct OptionDefinition {
        let arity: Int
        let allowsUserOverride: Bool
    }

    /// Options in version metadata that consume a separate value token.
    ///
    /// Most JVM options are self-contained (`-Xmx4096m`, `-Dkey=value`,
    /// `-XX:Flag=value`) and can safely be replaced by a user option with the
    /// same key. Module-system options are different: they are commonly
    /// repeated and are represented as two tokens. Removing only the flag
    /// would leave its value behind and corrupt the final JVM command.
    private static let optionDefinitions: [String: OptionDefinition] = [
        // Class path is intentionally replaceable, but its metadata value
        // must be removed together with the option.
        "-cp": OptionDefinition(arity: 2, allowsUserOverride: true),
        "-classpath": OptionDefinition(arity: 2, allowsUserOverride: true),

        // Repeatable module-system options: retain every metadata entry even
        // when a user supplies the same option.
        "-p": OptionDefinition(arity: 2, allowsUserOverride: false),
        "--module-path": OptionDefinition(arity: 2, allowsUserOverride: false),
        "--upgrade-module-path": OptionDefinition(arity: 2, allowsUserOverride: false),
        "--add-modules": OptionDefinition(arity: 2, allowsUserOverride: false),
        "--add-reads": OptionDefinition(arity: 2, allowsUserOverride: false),
        "--add-exports": OptionDefinition(arity: 2, allowsUserOverride: false),
        "--add-opens": OptionDefinition(arity: 2, allowsUserOverride: false),
        "--limit-modules": OptionDefinition(arity: 2, allowsUserOverride: false),
        "--patch-module": OptionDefinition(arity: 2, allowsUserOverride: false),
        "--enable-native-access": OptionDefinition(arity: 2, allowsUserOverride: false),

        // These are normally launch-mode options rather than Minecraft
        // metadata, but keeping their arity explicit prevents the same class
        // of orphan-value bug if a loader emits them.
        "-m": OptionDefinition(arity: 2, allowsUserOverride: false),
        "--module": OptionDefinition(arity: 2, allowsUserOverride: false),
        "-jar": OptionDefinition(arity: 2, allowsUserOverride: false),
        "--source": OptionDefinition(arity: 2, allowsUserOverride: false)
    ]

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
                .compactMap { argument -> String? in
                    guard let definition = optionDefinition(for: argument),
                          definition.allowsUserOverride else {
                        return nil
                    }
                    return definition.key
                }
        )
        guard !userKeys.isEmpty else { return versionArguments }

        var result: [String] = []
        var index = 0
        while index < versionArguments.count {
            let argument = versionArguments[index]
            guard let definition = optionDefinition(for: argument),
                  definition.allowsUserOverride,
                  userKeys.contains(definition.key) else {
                result.append(argument)
                index += 1
                continue
            }

            // Skip the complete option/value pair for known two-token
            // options. The bounds check also handles malformed metadata
            // without skipping a later unrelated argument.
            index += min(definition.arity, versionArguments.count - index)
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
        if argument == "-cp" || argument.hasPrefix("-cp=") ||
            argument == "--class-path" || argument.hasPrefix("--class-path=") {
            return "-cp"
        }

        return String(argument.split(separator: "=", maxSplits: 1).first ?? Substring(argument))
    }

    private func optionDefinition(for argument: String) -> (key: String, arity: Int, allowsUserOverride: Bool)? {
        guard let key = optionKey(for: argument) else { return nil }
        guard let definition = Self.optionDefinitions[key] else {
            return (key: key, arity: 1, allowsUserOverride: true)
        }

        // `--option=value` is already a complete token even when the
        // space-separated spelling of the same option consumes two tokens.
        let arity = definition.arity > 1 && !argument.contains("=") ? definition.arity : 1
        return (key: key, arity: arity, allowsUserOverride: definition.allowsUserOverride)
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
