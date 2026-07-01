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
        guard let rscript = ProcessRunner.resolveExecutable("Rscript") else { return nil }   // R toolchain absent

        let r = ProcessRunner.run(executable: rscript, arguments: args, timeout: timeout)
        guard r.launched else { return .malformed }
        // A killed/hung probe or a non-zero exit isn't a trustworthy reading.
        if r.timedOut { return .malformed }
        return parseRPackageVersion(r.stdout)
    }
}
