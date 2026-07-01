import Foundation

public enum Ecosystem: String, Sendable, CaseIterable {
    case npm, pypi, crates, go, rubygems, jsr, packagist, maven, cran

    /// Auto-detect order when the caller doesn't name an ecosystem. Deliberately
    /// only npm+PyPI: probing all eight for an unknown name risks a false-positive
    /// match (a name that exists in the wrong registry returns the WRONG library),
    /// which is worse than "not found". The others require an explicit ecosystem —
    /// the router skill knows it.
    static let autoOrder: [Ecosystem] = [.npm, .pypi]

    /// Whether a specific version can be pinned deterministically for this
    /// ecosystem. npm/PyPI have first-class per-version endpoints; the rest are
    /// latest-only here (honest: we don't fake a pin we can't honor).
    var supportsVersionPin: Bool { self == .npm || self == .pypi }
}

/// What the caller (the router skill, via the MCP tool) asks the engine to
/// resolve. The fuzzy "which library is this" decision is made upstream by the
/// LLM; by the time it reaches here the inputs are concrete and the work is
/// deterministic.
public struct DiscoveryRequest: Sendable {
    public var library: String?
    public var ecosystem: Ecosystem?
    public var docsURL: String?
    /// Pin to a specific version (e.g. "18.3.1"). Honored by the registry+repo
    /// legs for npm/PyPI; the llms.txt leg is structurally latest-only and is
    /// labeled as such when a pin is requested.
    public var version: String?

    public init(library: String? = nil, ecosystem: Ecosystem? = nil, docsURL: String? = nil, version: String? = nil) {
        self.library = library
        self.ecosystem = ecosystem
        self.docsURL = docsURL
        self.version = version
    }
}

/// Orchestrates the discovery chain over an injected `HTTPClient`. Holds no
/// mutable state, so it's a value type usable from anywhere. The chain is
/// primary-source-first: llms.txt → registry-resolved docs → repo. context7/web
/// are intentionally *not* here — they live one layer up as the labeled fallback
/// the MCP server reaches for only when this returns nothing.
public struct DiscoveryEngine: Sendable {
    private let http: HTTPClient

    public init(http: HTTPClient) { self.http = http }

    /// Resolve a ranked list of primary sources. Never throws: a dead network
    /// path drops that source rather than failing the whole resolve, so the
    /// caller always gets the best of whatever was reachable.
    public func resolveSources(_ req: DiscoveryRequest) async -> [DiscoverySource] {
        var sources: [DiscoverySource] = []
        var docsHosts: [String] = []
        var version: String?

        if let docs = req.docsURL, !docs.isEmpty { docsHosts.append(docs) }

        // Registry leg: deterministic, and the strongest "latest version" signal.
        if let lib = req.library, !lib.isEmpty,
           let res = await resolveRegistry(library: lib, ecosystem: req.ecosystem, version: req.version) {
            version = res.version
            if let docs = res.documentation { docsHosts.append(docs) }
            if let home = res.homepage { docsHosts.append(home) }
            if let changelog = res.changelog {
                sources.append(DiscoverySource(
                    kind: .registryDocs, url: changelog, fidelity: .medium, freshness: .live,
                    title: "Changelog (\(version ?? "latest"))", version: version))
            }
            if let repo = res.repository {
                sources.append(DiscoverySource(
                    kind: .repoReadme, url: repo, fidelity: .high, freshness: .live,
                    title: "Repository", version: version))
            }
        }

        // llms.txt leg: probe candidates across every docs host we found, stop at
        // the first real hit per host, then try to upgrade it to llms-full.txt.
        for host in dedupe(docsHosts) {
            if let hit = await probeLlms(host: host) {
                sources.append(hit)
                if hit.kind == .llmsIndex,
                   let fullURL = llmsFullSibling(of: hit.url),
                   let full = await probeExact(url: fullURL) {
                    sources.append(full)
                }
                break   // one good llms source is enough; don't spam every host
            }
        }

        // No leg's URL is guaranteed version-specific: llms.txt has no per-version
        // hosting convention, and the registry-derived repo/changelog URLs point at
        // the default branch / a generic changelog. When the caller pinned a
        // version, label every such source so an agent doesn't mistake latest
        // content for the pinned version's (the `version` field still carries the
        // pin as context).
        if let pin = req.version {
            sources = sources.map { s in
                switch s.kind {
                case .llmsIndex, .llmsFull:
                    return DiscoverySource(kind: s.kind, url: s.url, fidelity: s.fidelity, freshness: s.freshness,
                                           title: "latest docs — NOT pinned to \(pin)", version: s.version)
                case .repoReadme, .registryDocs:
                    let base = s.title ?? (s.kind == .repoReadme ? "Repository" : "Changelog")
                    return DiscoverySource(kind: s.kind, url: s.url, fidelity: s.fidelity, freshness: s.freshness,
                                           title: "\(base) — default branch, content NOT pinned to \(pin)", version: s.version)
                default:
                    return s
                }
            }
        }

        return sources.rankedBestFirst()
    }

    /// Fetch a source's raw bytes as text (the high-fidelity path). Throws on a
    /// transport error so the caller can fall back.
    public func fetchRaw(url: String) async throws -> String {
        try await http.get(url).bodyText
    }

    /// The deterministic "what is the latest version right now" answer, plus the
    /// changelog/repo URLs the registry hands over. Public because it's a useful
    /// tool on its own, not just an internal leg of `resolveSources`.
    public func latestVersion(library: String, ecosystem: Ecosystem?, version: String? = nil) async -> RegistryResolution? {
        await resolveRegistry(library: library, ecosystem: ecosystem, version: version)
    }

    /// Probe an HTTP(S) base for an OpenAPI/Swagger JSON spec — the highest-fidelity
    /// "what can I call" source, because the schema is the contract itself.
    public func introspectOpenAPI(baseURL: String) async -> OpenAPISummary? {
        for candidate in openAPICandidates(for: baseURL) {
            guard let resp = try? await http.get(candidate), resp.status == 200 else { continue }
            if let summary = try? parseOpenAPI(resp.body) { return summary }
        }
        return nil
    }

    /// Run a shape-only introspection query against a GraphQL endpoint.
    public func introspectGraphQL(endpoint: String) async -> GraphQLSummary? {
        guard let resp = try? await http.post(endpoint, jsonBody: graphQLIntrospectionQuery),
              resp.status == 200 else { return nil }
        return try? parseGraphQLIntrospection(resp.body)
    }

    // MARK: - Legs

    private func resolveRegistry(library: String, ecosystem: Ecosystem?, version: String? = nil) async -> RegistryResolution? {
        // Boundary validation: these strings get interpolated into URLs.
        guard isSafePackageName(library) else { return nil }
        if let v = version, !isSafeVersion(v) { return nil }

        let order = ecosystem.map { [$0] } ?? Ecosystem.autoOrder
        for eco in order {
            if let res = await fetchRegistry(eco: eco, library: library, version: version) { return res }
        }
        return nil
    }

    /// One ecosystem's fetch+parse. A version pin is honored only where it's a
    /// first-class endpoint (npm/PyPI); elsewhere it's ignored and latest is used.
    private func fetchRegistry(eco: Ecosystem, library: String, version: String?) async -> RegistryResolution? {
        let pin = eco.supportsVersionPin ? version : nil
        switch eco {
        case .npm:
            let url = pin.map { "https://registry.npmjs.org/\(library)/\($0)" }
                ?? "https://registry.npmjs.org/\(library)/latest"
            return await getParse(url, parseNpmLatest)
        case .pypi:
            let url = pin.map { "https://pypi.org/pypi/\(library)/\($0)/json" }
                ?? "https://pypi.org/pypi/\(library)/json"
            return await getParse(url, parsePyPI)
        case .crates:
            return await getParse("https://crates.io/api/v1/crates/\(library)", parseCratesIo)
        case .rubygems:
            return await getParse("https://rubygems.org/api/v1/gems/\(library).json", parseRubyGems)
        case .go:
            var res = await getParse("https://proxy.golang.org/\(goEscape(library))/@latest", parseGoProxy)
            // The proxy omits Origin for some pseudo-versions/older modules. For a
            // module HOSTED on a known forge, the module path itself is the repo —
            // don't throw that away.
            if res != nil, res?.repository == nil, let repo = goRepoFromModulePath(library) {
                res?.repository = repo
            }
            return res
        case .packagist:
            return await getParse("https://repo.packagist.org/p2/\(library).json", parsePackagist)
        case .jsr:
            return await fetchJSR(library: library)
        case .maven:
            return await fetchMaven(coordinate: library)
        case .cran:
            return await getParse("https://crandb.r-pkg.org/\(library)", parseCRAN)
        }
    }

    private func getParse(_ url: String, _ parse: (Data) throws -> RegistryResolution) async -> RegistryResolution? {
        guard let resp = try? await http.get(url), resp.status == 200 else { return nil }
        return try? parse(resp.body)
    }

    /// Go proxy requires uppercase letters in a module path be escaped as `!<lower>`.
    private func goEscape(_ module: String) -> String {
        var out = ""
        for ch in module {
            if ch.isUppercase { out += "!" + ch.lowercased() } else { out.append(ch) }
        }
        return out
    }

    /// For a Go module hosted on a known forge, the first three path segments ARE
    /// the repo (`github.com/gin-gonic/gin`, or `github.com/o/r/v2` → `.../o/r`).
    private func goRepoFromModulePath(_ module: String) -> String? {
        for host in ["github.com/", "gitlab.com/", "bitbucket.org/"] where module.hasPrefix(host) {
            let comps = module.split(separator: "/")
            if comps.count >= 3 { return "https://\(comps[0])/\(comps[1])/\(comps[2])" }
        }
        return nil
    }

    /// JSR needs two calls: meta.json for the latest version, api.jsr.io for the
    /// GitHub repo. Homepage/docs are derivable from the scope+name.
    private func fetchJSR(library: String) async -> RegistryResolution? {
        let trimmed = library.hasPrefix("@") ? String(library.dropFirst()) : library
        let parts = trimmed.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let scope = String(parts[0]), name = String(parts[1])
        let meta = await getParse("https://jsr.io/@\(scope)/\(name)/meta.json", parseJSRMeta)
        let pkg = await getParse("https://api.jsr.io/scopes/\(scope)/packages/\(name)", parseJSRPackage)
        guard meta != nil || pkg != nil else { return nil }
        return RegistryResolution(
            version: meta?.version ?? pkg?.version,
            homepage: "https://jsr.io/@\(scope)/\(name)",
            repository: pkg?.repository,
            changelog: nil,
            documentation: "https://jsr.io/@\(scope)/\(name)/doc"
        )
    }

    /// Maven coordinate is `group:artifact`. Version-only (repo/SCM lives in POM XML).
    private func fetchMaven(coordinate: String) async -> RegistryResolution? {
        let parts = coordinate.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let g = String(parts[0]), a = String(parts[1])
        // g/a go into a Solr `q=g:..+AND+a:..` expression. isSafePackageName allows
        // `+` and `:` (needed by other ecosystems); forbid them here so a crafted
        // coordinate can't inject extra Solr clauses. Real Maven coords are a strict
        // subset (letters/digits/./_/-).
        let mavenAllowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !g.isEmpty, !a.isEmpty,
              g.unicodeScalars.allSatisfy({ mavenAllowed.contains($0) }),
              a.unicodeScalars.allSatisfy({ mavenAllowed.contains($0) })
        else { return nil }
        let url = "https://search.maven.org/solrsearch/select?q=g:\(g)+AND+a:\(a)&rows=1&wt=json"
        return await getParse(url, parseMavenSearch)
    }

    /// Probe the ordered llms.txt candidates for a host; return the first real hit.
    private func probeLlms(host: String) async -> DiscoverySource? {
        for candidate in llmsTxtCandidates(for: host) {
            if let hit = await probeExact(url: candidate) { return hit }
        }
        return nil
    }

    /// Probe one exact URL and classify it. Returns a source only on a real hit.
    private func probeExact(url: String) async -> DiscoverySource? {
        guard let resp = try? await http.get(url) else { return nil }
        guard classifyLlmsProbe(status: resp.status, contentType: resp.contentType, byteSize: resp.body.count) == .hit
        else { return nil }
        let kind = url.hasSuffix("/llms-full.txt")
            ? SourceKind.llmsFull
            : llmsFlavor(byteSize: resp.body.count)
        let fidelity: Fidelity = (kind == .llmsFull) ? .high : .medium
        return DiscoverySource(kind: kind, url: url, fidelity: fidelity, freshness: .live)
    }

    private func dedupe(_ xs: [String]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for x in xs where !x.isEmpty && seen.insert(x).inserted { out.append(x) }
        return out
    }
}
