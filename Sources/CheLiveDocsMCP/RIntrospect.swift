import Foundation
import LiveDocsCore

/// Runs the READ-ONLY installed-R-package probe via `Rscript`. This is the local
/// half of a has-local query — it reports the version installed in the current
/// context, never installs or upgrades anything.
///
/// Security posture (mirrors CLIIntrospect): the package name is validated by
/// `isSafeRPackageName` and passed as an argv entry (via `commandArgs`), never
/// interpolated into the `-e` snippet, so it cannot inject R. A watchdog kills a
/// hung probe. stdin is /dev/null so R can't block waiting for input.
enum RIntrospect {

    /// Probe an installed R package. Returns nil when the R toolchain itself is
    /// unavailable (so the caller can distinguish "R not installed" from "package
    /// not installed"); otherwise the parsed result.
    static func installed(package: String, timeout: TimeInterval = 12) -> RInstalledResult? {
        guard let args = rInstalledProbeArgs(package: package) else { return .malformed }
        guard let rscript = resolveRscript() else { return nil }   // R toolchain absent

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: rscript)
        proc.arguments = args
        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.standardInput = FileHandle.nullDevice
        do { try proc.run() } catch { return .malformed }

        let killer = DispatchWorkItem { if proc.isRunning { proc.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        proc.waitUntilExit()
        killer.cancel()

        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return parseRPackageVersion(stdout)
    }

    private static func resolveRscript() -> String? {
        let fm = FileManager.default
        for p in ["/usr/local/bin/Rscript", "/opt/homebrew/bin/Rscript", "/usr/bin/Rscript"]
        where fm.isExecutableFile(atPath: p) { return p }
        // Fall back to PATH resolution via `which` (no shell).
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["Rscript"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let path = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
