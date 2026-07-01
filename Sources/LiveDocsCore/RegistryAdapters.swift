import Foundation

// Parsers for the registries beyond npm/PyPI (which live in Registry.swift).
// Each is pure (Data -> RegistryResolution) so it's unit-tested with a fixture,
// and reuses normalizeRepoURL for every repo field. Field paths were verified by
// live curl on 2026-07-01 (see the workflow research), not taken from memory.

/// crates.io — `https://crates.io/api/v1/crates/<name>`. root["crate"].
/// Prefer max_stable_version; no changelog field exists.
/// NOTE: crates.io returns 403 for an empty/curl-default User-Agent; the engine's
/// URLSession client sends a descriptive UA, which satisfies it.
public func parseCratesIo(_ data: Data) throws -> RegistryResolution {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let crate = root["crate"] as? [String: Any]
    else { throw RegistryError.malformedJSON }
    let version = (crate["max_stable_version"] as? String)
        ?? (crate["newest_version"] as? String)
        ?? (crate["default_version"] as? String)
    return RegistryResolution(
        version: version,
        homepage: crate["homepage"] as? String,
        repository: normalizeRepoURL(crate["repository"] as? String),
        changelog: nil,
        documentation: crate["documentation"] as? String
    )
}

/// RubyGems — `https://rubygems.org/api/v1/gems/<name>.json`. Top-level fields;
/// the richest of the extra registries (version + repo + homepage + docs + changelog).
public func parseRubyGems(_ data: Data) throws -> RegistryResolution {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          (root["version"] != nil || root["name"] != nil)
    else { throw RegistryError.malformedJSON }
    return RegistryResolution(
        version: root["version"] as? String,
        homepage: root["homepage_uri"] as? String,
        repository: normalizeRepoURL(root["source_code_uri"] as? String),
        changelog: root["changelog_uri"] as? String,
        documentation: root["documentation_uri"] as? String
    )
}

/// Go modules — `https://proxy.golang.org/<escaped-module>/@latest`.
/// `.Version` is the latest tag; `.Origin.URL` is the VCS repo but is ABSENT for
/// some pseudo-versions/older cached modules (then repository is nil — the caller
/// may still have the module path itself as a github.com URL).
public func parseGoProxy(_ data: Data) throws -> RegistryResolution {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let version = root["Version"] as? String
    else { throw RegistryError.malformedJSON }
    let origin = root["Origin"] as? [String: Any]
    return RegistryResolution(
        version: version,
        repository: normalizeRepoURL(origin?["URL"] as? String)
    )
}

/// JSR (Deno) meta — `https://jsr.io/@<scope>/<name>/meta.json`. Only `.latest`
/// here; the GitHub repo needs a second call (api.jsr.io) handled in the engine.
public func parseJSRMeta(_ data: Data) throws -> RegistryResolution {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let latest = root["latest"] as? String
    else { throw RegistryError.malformedJSON }
    return RegistryResolution(version: latest)
}

/// JSR package metadata — `https://api.jsr.io/scopes/<scope>/packages/<name>`.
/// Supplies `.githubRepository.owner/name` (→ repo URL) and `.latestVersion`.
public func parseJSRPackage(_ data: Data) throws -> RegistryResolution {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw RegistryError.malformedJSON }
    var repo: String?
    if let gh = root["githubRepository"] as? [String: Any],
       let owner = gh["owner"] as? String, let name = gh["name"] as? String {
        repo = "https://github.com/\(owner)/\(name)"
    }
    guard repo != nil || root["latestVersion"] != nil else { throw RegistryError.malformedJSON }
    return RegistryResolution(version: root["latestVersion"] as? String, repository: repo)
}

/// Packagist (PHP) — `https://repo.packagist.org/p2/<vendor>/<package>.json`.
/// `.packages[key][0]` is the newest entry in the non-dev (stable) channel — almost
/// always a stable release, though it can be a tagged RC/beta. dev/branch builds
/// live in a separate `~dev.json`, so they never appear here.
public func parsePackagist(_ data: Data) throws -> RegistryResolution {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let packages = root["packages"] as? [String: Any],
          let firstList = packages.values.first as? [[String: Any]],
          let latest = firstList.first
    else { throw RegistryError.malformedJSON }
    let source = (latest["source"] as? [String: Any])?["url"] as? String
    // Packagist has no docs field; support.source is just the repo browse URL
    // (redundant with repository), so leave documentation nil rather than mislabel it.
    return RegistryResolution(
        version: latest["version"] as? String,
        homepage: latest["homepage"] as? String,
        repository: normalizeRepoURL(source),
        changelog: nil,
        documentation: nil
    )
}

/// CRAN (R) — `https://crandb.r-pkg.org/<pkg>` (the metacran JSON DB).
/// `.Version` is latest; `.URL` is a comma/whitespace-separated list mixing the
/// docs homepage and (often) the forge repo; `.BugReports` is usually the repo's
/// `/issues` URL, which is the most reliable way to recover the repo.
public func parseCRAN(_ data: Data) throws -> RegistryResolution {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let version = root["Version"] as? String
    else { throw RegistryError.malformedJSON }

    let urls = ((root["URL"] as? String) ?? "")
        .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" })
        .map(String.init)
    let forgeHosts = ["github.com", "gitlab.com", "bitbucket.org"]
    func isForge(_ u: String) -> Bool { forgeHosts.contains { u.contains($0) } }

    var repo = normalizeRepoURL(urls.first(where: isForge))
    if repo == nil, let bug = root["BugReports"] as? String, bug.contains("/issues") {
        repo = normalizeRepoURL(bug.replacingOccurrences(of: "/issues", with: ""))
    }
    let homepage = urls.first(where: { !isForge($0) })   // the docs site (e.g. dplyr.tidyverse.org)

    return RegistryResolution(
        version: version,
        homepage: homepage,
        repository: repo,
        changelog: nil,
        documentation: nil
    )
}

/// Maven Central — `search.maven.org/solrsearch/select?q=g:<g>+AND+a:<a>&rows=1&wt=json`.
/// Version-only: repo/SCM lives only in the POM XML (often the parent POM), which
/// is out of scope here. `.response.docs[0].latestVersion`.
public func parseMavenSearch(_ data: Data) throws -> RegistryResolution {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let response = root["response"] as? [String: Any],
          let docs = response["docs"] as? [[String: Any]],
          let doc = docs.first,
          let version = (doc["latestVersion"] as? String) ?? (doc["v"] as? String)
    else { throw RegistryError.malformedJSON }
    return RegistryResolution(version: version)
}
