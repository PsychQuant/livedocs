import Foundation

/// Single source of truth for the package version and derived identity strings.
///
/// Before this existed the version was hand-copied into `Server(version:)`, the
/// HTTP `User-Agent`, `mcpb/manifest.json`, `plugin.json`, and `marketplace.json`
/// — and they drifted (the MCP server still said 0.5.0 a release after the bump).
/// Everything that needs the version now reads it from here; the release script
/// cross-checks this constant against the git tag.
public enum LiveDocsVersion {
    /// The current package version. Keep in lockstep with the latest git tag and
    /// the plugin/marketplace/mcpb manifests (release.sh enforces the tag match).
    public static let current = "0.7.0"

    /// Canonical repository slug — used to build the User-Agent and any self-links.
    public static let repositorySlug = "PsychQuant/livedocs"

    /// The HTTP `User-Agent` sent on every request. A real UA avoids 403s from
    /// hosts that reject empty/robot agents; the version comes from `current`
    /// so it can never go stale independently.
    public static var userAgent: String {
        "LiveDocs/\(current) (+https://github.com/\(repositorySlug))"
    }
}
