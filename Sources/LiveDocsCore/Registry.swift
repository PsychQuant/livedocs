import Foundation

/// What a package-registry lookup deterministically yields. This is the engine's
/// strongest fallback when no `llms.txt` exists: live probing showed PyPI returns
/// the *exact latest version* plus a `project_urls` map (Changelog / Repository /
/// Documentation), and npm returns homepage + repository — all without scraping a
/// single HTML page. Every field is optional; registries are inconsistent.
public struct RegistryResolution: Sendable, Equatable {
    public var version: String?
    public var homepage: String?
    public var repository: String?
    public var changelog: String?
    public var documentation: String?

    public init(
        version: String? = nil,
        homepage: String? = nil,
        repository: String? = nil,
        changelog: String? = nil,
        documentation: String? = nil
    ) {
        self.version = version
        self.homepage = homepage
        self.repository = repository
        self.changelog = changelog
        self.documentation = documentation
    }
}

public enum RegistryError: Error, Equatable {
    case malformedJSON
}

/// Parse the npm `https://registry.npmjs.org/<pkg>/latest` document.
/// Shape (verified): `{ "version": "...", "homepage": "...",
///                       "repository": { "url": "git+https://github.com/x/y.git" } }`
/// `repository` may also be a bare string, so both forms are handled.
public func parseNpmLatest(_ data: Data) throws -> RegistryResolution {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw RegistryError.malformedJSON
    }
    var repo: String?
    if let r = root["repository"] as? [String: Any] { repo = r["url"] as? String }
    else if let r = root["repository"] as? String { repo = r }

    return RegistryResolution(
        version: root["version"] as? String,
        homepage: root["homepage"] as? String,
        repository: normalizeRepoURL(repo),
        changelog: nil,
        documentation: nil
    )
}

/// Parse the PyPI `https://pypi.org/pypi/<pkg>/json` document.
/// Shape (verified): `{ "info": { "version": "...", "home_page": "...",
///   "project_urls": { "Changelog": "...", "Documentation": "...",
///                     "Repository": "...", "Homepage": "..." } } }`
/// `project_urls` keys are free-form and inconsistently capitalized, so we match
/// them case-insensitively against known intents.
public func parsePyPI(_ data: Data) throws -> RegistryResolution {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let info = root["info"] as? [String: Any]
    else { throw RegistryError.malformedJSON }

    let urls = (info["project_urls"] as? [String: Any]) ?? [:]
    func pick(_ intents: [String]) -> String? {
        for (k, v) in urls {
            let kl = k.lowercased()
            if intents.contains(where: { kl.contains($0) }), let s = v as? String { return s }
        }
        return nil
    }

    let homepage = pick(["homepage"]) ?? (info["home_page"] as? String)
    let repo = pick(["repository", "source", "code", "github"])

    return RegistryResolution(
        version: info["version"] as? String,
        homepage: homepage,
        repository: normalizeRepoURL(repo),
        changelog: pick(["changelog", "changes", "release", "news"]),
        documentation: pick(["documentation", "docs"])
    )
}

/// Normalize the many ways a registry encodes a repo URL into a plain
/// `https://host/owner/repo` form usable for raw fetches and the GitHub API:
///   • `git+https://github.com/x/y.git`        → `https://github.com/x/y`
///   • `git+ssh://git@github.com/x/y.git`      → `https://github.com/x/y`
///   • `git@github.com:x/y.git`                → `https://github.com/x/y`
///   • `github:x/y` (npm shorthand)            → `https://github.com/x/y`
/// Returns nil for empty/unrecognized input.
public func normalizeRepoURL(_ raw: String?) -> String? {
    guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }

    // npm shorthand: "github:owner/repo" / "gitlab:owner/repo"
    if let colon = s.firstIndex(of: ":"), !s.contains("://"), !s.contains("@") {
        let host = String(s[s.startIndex..<colon])
        let rest = String(s[s.index(after: colon)...])
        let hosts = ["github": "github.com", "gitlab": "gitlab.com", "bitbucket": "bitbucket.org"]
        if let h = hosts[host.lowercased()] {
            return "https://\(h)/" + rest.trimmingTrailingGit()
        }
    }

    s = s.replacingOccurrences(of: "git+", with: "")

    // scp-like form: git@github.com:owner/repo.git
    if s.hasPrefix("git@"), let colon = s.firstIndex(of: ":") {
        let host = String(s[s.index(s.startIndex, offsetBy: 4)..<colon])
        let path = String(s[s.index(after: colon)...])
        return "https://\(host)/" + path.trimmingTrailingGit()
    }

    // ssh://git@host/owner/repo(.git)
    if s.hasPrefix("ssh://") {
        s = s.replacingOccurrences(of: "ssh://", with: "https://")
        s = s.replacingOccurrences(of: "git@", with: "")
    }
    if s.hasPrefix("git://") {
        s = s.replacingOccurrences(of: "git://", with: "https://")
    }

    guard s.hasPrefix("http") else { return nil }
    return s.trimmingTrailingGit()
}

private extension String {
    func trimmingTrailingGit() -> String {
        hasSuffix(".git") ? String(dropLast(4)) : self
    }
}
