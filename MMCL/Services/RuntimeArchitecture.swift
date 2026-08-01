import Foundation

extension RuntimeArchitecture {
    /// Architecture of the current launcher process as reported by uname.
    /// This is intentionally runtime based instead of `#if arch(...)`, which
    /// can describe the build slice rather than the process actually running
    /// under Rosetta.
    static var currentSystem: RuntimeArchitecture {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/uname")
        process.arguments = ["-m"]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return .unknown }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return .unknown }

        let output = String(
            decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        return architecture(from: output)
    }

    /// Inspects the actual Java executable instead of assuming it has the
    /// same architecture as MMCL. This matters when both native and Rosetta
    /// JDKs are installed on Apple Silicon.
    static func detect(from executableURL: URL) -> RuntimeArchitecture {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/file")
        process.arguments = ["-b", executableURL.resolvingSymlinksInPath().path]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return .unknown }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return .unknown }

        let output = String(
            decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        let normalized = output.lowercased()
        let hasArm64 = normalized.contains("arm64") || normalized.contains("aarch64")
        let hasX86_64 = normalized.contains("x86_64") || normalized.contains("x86-64")
        if hasArm64 && hasX86_64 { return .universal }
        if hasArm64 { return .arm64 }
        if hasX86_64 { return .x86_64 }
        return architecture(from: normalized)
    }

    private static func architecture(from value: String) -> RuntimeArchitecture {
        let normalized = value.lowercased()
        if normalized.contains("arm64") || normalized.contains("aarch64") {
            return .arm64
        }
        if normalized.contains("x86_64") || normalized.contains("x86-64") || normalized.contains("amd64") {
            return .x86_64
        }
        return .unknown
    }
}
