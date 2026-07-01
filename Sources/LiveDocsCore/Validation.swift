import Foundation

// Boundary validation for the two user-controlled strings that get interpolated
// into registry/repo URLs: the package name and the version. Without this a name
// like "../../evil" or a version with "?x=" could redirect the fetch or inject
// query params. We validate at the boundary (before URL construction) and reject
// rather than escape — a legitimate package/version never needs these characters.

private let packageNameAllowed = CharacterSet(charactersIn:
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@._-/:+")
private let versionAllowed = CharacterSet(charactersIn:
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-+")

/// A package name is safe to interpolate if it's non-empty, bounded, contains no
/// path-traversal (`..`), no leading slash, and only characters that appear in
/// real identifiers across every ecosystem we hit: npm scopes (`@scope/name`),
/// Go module paths (`github.com/org/mod`, dots + slashes), and Maven coordinates
/// (`group:artifact`). Whitespace, control chars, and URL-structural metacharacters
/// (`?`, `#`, `&`, `%`, …) are absent from the allowlist, so they're rejected.
public func isSafePackageName(_ name: String) -> Bool {
    guard !name.isEmpty, name.count <= 214,
          !name.contains(".."), !name.hasPrefix("/")
    else { return false }
    return name.unicodeScalars.allSatisfy { packageNameAllowed.contains($0) }
}

/// A version is safe if it's a bounded semver-ish token: starts alphanumeric,
/// then only `. _ - +` plus alphanumerics (covers `18.3.1`, `v1.12.0`,
/// `1.0.0-rc.1`, `33.4.8-jre`). No slashes/spaces/metacharacters.
public func isSafeVersion(_ version: String) -> Bool {
    guard !version.isEmpty, version.count <= 128,
          let first = version.unicodeScalars.first,
          CharacterSet.alphanumerics.contains(first)
    else { return false }
    return version.unicodeScalars.allSatisfy { versionAllowed.contains($0) }
}
