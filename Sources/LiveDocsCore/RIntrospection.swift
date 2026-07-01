import Foundation

/// Result of probing a LOCALLY INSTALLED R package. This is the "local" half of a
/// has-local query (per issue #1): the installed version is authoritative for how
/// the user's actual R behaves, independent of what's latest on CRAN.
public enum RInstalledResult: Equatable, Sendable {
    /// Installed; carries the version and the `.libPaths()` entry it resolved from
    /// (so the caller can show WHICH environment answered — the cwd-scoped project
    /// library, not a misleading global assumption).
    case installed(version: String, libPath: String)
    /// Not installed in the resolved context — reported honestly rather than
    /// fabricating a global version.
    case notInstalled
    /// The probe produced output we can't interpret (R error, empty, etc.).
    case malformed
}

/// R package names are stricter than the generic registry allowlist: they must
/// start with a letter and contain only letters, digits, and dots (CRAN policy).
/// We validate before the name ever reaches R — defense in depth even though it's
/// passed as an argv entry (not interpolated into `-e` code).
public func isSafeRPackageName(_ name: String) -> Bool {
    guard !name.isEmpty, name.count <= 100,
          let first = name.unicodeScalars.first,
          CharacterSet.letters.contains(first)
    else { return false }
    let allowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.")
    return name.unicodeScalars.allSatisfy { allowed.contains($0) }
}

/// The READ-ONLY R snippet run to probe an installed package. It only reads —
/// `requireNamespace` loads (never installs), `packageVersion`/`.libPaths` read.
/// The package name is taken from `commandArgs`, NOT interpolated into this code,
/// so it cannot inject R.
public let rInstalledProbeSnippet =
    "p <- commandArgs(trailingOnly=TRUE)[1]; " +
    "if (requireNamespace(p, quietly=TRUE)) { " +
    "cat(\"OK\", as.character(packageVersion(p)), .libPaths()[1], sep=\"\\t\") " +
    "} else { cat(\"MISSING\") }"

/// The argv to hand to `Rscript` for a safe package, or nil if the name is
/// rejected. Pure, so the guard + invocation shape are unit-testable without R.
public func rInstalledProbeArgs(package: String) -> [String]? {
    guard isSafeRPackageName(package) else { return nil }
    return ["-e", rInstalledProbeSnippet, package]
}

/// Parse the probe's stdout into a result. `OK\t<version>\t<libpath>` → installed;
/// `MISSING` → not installed; anything else → malformed.
public func parseRPackageVersion(_ raw: String) -> RInstalledResult {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if t == "MISSING" { return .notInstalled }
    let parts = t.components(separatedBy: "\t")
    guard parts.count >= 3, parts[0] == "OK", !parts[1].isEmpty, !parts[2].isEmpty else {
        return .malformed
    }
    return .installed(version: parts[1], libPath: parts[2])
}
