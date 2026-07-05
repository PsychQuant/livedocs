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
    /// ecosystem. npm/PyPI/crates/Go/RubyGems have first-class per-version
    /// endpoints (issue #36); jsr/packagist/maven/cran stay latest-only here
    /// (their per-version endpoints are more indirect) — honest: we don't fake a
    /// pin we can't confirm.
    public var supportsVersionPin: Bool {
        switch self {
        case .npm, .pypi, .crates, .go, .rubygems: return true
        case .jsr, .packagist, .maven, .cran: return false
        }
    }
}

/// What the caller (the router skill, via the MCP tool) asks the engine to
/// resolve. The fuzzy "which library is this" decision is made upstream by the
/// LLM; by the time it reaches here the inputs are concrete and the work is
/// deterministic.
public struct DiscoveryRequest: Sendable {
    public var library: String?
    public var ecosystem: Ecosystem?
    public var docsURL: String?
    /// Pin to a specific version (e.g. "18.3.1"). Honored by the registry leg for
    /// npm/PyPI/crates/Go/RubyGems (confirmed at a per-version endpoint;
    /// `RegistryResolution.pinHonored` records the outcome); jsr/packagist/maven/
    /// cran are latest-only. The llms.txt / repo URLs are structurally latest and
    /// are labeled as such when a pin is requested.
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

        // llms.txt leg: probe each host's candidates CONCURRENTLY (#57 — wall-clock
        // ≈ the slowest single probe instead of the sum), selecting by preference
        // order so the result is identical to the old sequential loop. The
        // llms-full "upgrade" is satisfied from the same collected results (the
        // sibling is in the candidate set), never re-probed. Hosts stay sequential
        // with an early break — concurrency is bounded to ONE host's candidate set
        // (≤6 in-flight requests), so a hit on the first host never spams the rest.
        for host in dedupe(docsHosts) {
            let hits = await probeLlmsAll(host: host)
            if let best = hits.first?.source {
                sources.append(best)
                if best.kind == .llmsIndex,
                   let fullURL = llmsFullSibling(of: best.url),
                   let full = hits.first(where: { $0.source.url == fullURL })?.source {
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

    /// Resolve AND fetch the top result's raw content in ONE call (#59) — removes a
    /// whole agent round-trip vs the resolve→fetch two-step, at zero extra process
    /// cost (the measured alternative — a spawned cheap-model subagent — loses
    /// ~7–30× on spawn overhead; see evals/look-up/perf_profile.md). Exact parity
    /// with the two-call flow: the fetch goes through the same HTTP client (SSRF
    /// guard included), and a fetch failure degrades gracefully — sources intact,
    /// content nil, the caller descends the list with fetch_docs.
    public func resolveSourcesFetchingTop(_ req: DiscoveryRequest) async
        -> (sources: [DiscoverySource], topContent: String?) {
        let sources = await resolveSources(req)
        guard let top = sources.first else { return (sources, nil) }
        return (sources, try? await fetchRaw(url: top.url))
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

        // Auto-detect ([.npm, .pypi]) + a pin: two passes. Pass 1 tries EVERY
        // ecosystem for the pinned URL (no latest fallback) so a pin present only
        // on the 2nd registry isn't pre-empted by the 1st's latest. Pass 2 runs
        // only if no registry had anything at the pinned URL — then fall back to
        // the first ecosystem that has the package at all, with pinHonored=false
        // (a pin was requested but not found anywhere). This fixes the wrong-package
        // short-circuit WITHOUT losing the helpful latest fallback (issue #36 r3).
        if ecosystem == nil, let v = version {
            for eco in order {
                if let res = await fetchRegistry(eco: eco, library: library, version: v, fallbackToLatest: false) {
                    return res
                }
            }
            for eco in order {
                if var res = await fetchRegistry(eco: eco, library: library, version: nil, fallbackToLatest: true) {
                    res.pinHonored = false
                    return res
                }
            }
            return nil
        }

        // Explicit ecosystem, or no pin: single pass with latest fallback allowed.
        for eco in order {
            if var res = await fetchRegistry(eco: eco, library: library, version: version, fallbackToLatest: true) {
                // Latest-only ecosystems: a requested pin could not be honored.
                // Say so explicitly instead of leaving the signal absent (issue #36).
                if version != nil, !eco.supportsVersionPin { res.pinHonored = false }
                return res
            }
        }
        return nil
    }

    /// One ecosystem's fetch+parse. A version pin is honored where the ecosystem
    /// has a first-class per-version endpoint (npm/PyPI directly; crates/Go/
    /// RubyGems via a confirm probe) — `pinHonored` records the outcome. Where a
    /// pin can't be confirmed we return latest with `pinHonored=false`, never a
    /// faked pin (issue #36). `fallbackToLatest` is false only for a non-last
    /// ecosystem during auto-detect, so a pinned miss yields nil and the loop
    /// continues instead of short-circuiting.
    private func fetchRegistry(eco: Ecosystem, library: String, version: String?, fallbackToLatest: Bool) async -> RegistryResolution? {
        switch eco {
        case .npm:
            return await fetchDirectPin(
                pinnedURL: { "https://registry.npmjs.org/\(library)/\($0)" },
                latestURL: "https://registry.npmjs.org/\(library)/latest",
                parse: parseNpmLatest, version: version, fallbackToLatest: fallbackToLatest)
        case .pypi:
            return await fetchDirectPin(
                pinnedURL: { "https://pypi.org/pypi/\(library)/\($0)/json" },
                latestURL: "https://pypi.org/pypi/\(library)/json",
                parse: parsePyPI, version: version, fallbackToLatest: fallbackToLatest)
        case .crates:
            return await fetchWithPinConfirm(
                latestURL: "https://crates.io/api/v1/crates/\(library)", latestParse: parseCratesIo,
                version: version,
                confirmURL: { "https://crates.io/api/v1/crates/\(library)/\($0)" }, confirmParse: parseCratesVersion)
        case .rubygems:
            return await fetchWithPinConfirm(
                latestURL: "https://rubygems.org/api/v1/gems/\(library).json", latestParse: parseRubyGems,
                version: version,
                confirmURL: { "https://rubygems.org/api/v2/rubygems/\(library)/versions/\($0).json" },
                confirmParse: parseRubyGemsVersion)
        case .go:
            guard var res = await getParse("https://proxy.golang.org/\(goEscape(library))/@latest", parseGoProxy) else { return nil }
            // The proxy omits Origin for some pseudo-versions/older modules. For a
            // module HOSTED on a known forge, the module path itself is the repo —
            // don't throw that away.
            if res.repository == nil, let repo = goRepoFromModulePath(library) {
                res.repository = repo
            }
            if let pin = version {
                // Go tags are v-prefixed; the proxy path adds its own `v`, so strip
                // any leading `v` on the input first (else v1.9.1 → …/@v/vv1.9.1.info,
                // a guaranteed 404 — issue #36 verify).
                if let confirmed = await confirmPin(
                    "https://proxy.golang.org/\(goEscape(library))/@v/v\(stripLeadingV(pin)).info", parseGoVersionInfo, wants: pin) {
                    res.version = confirmed   // keeps Go's v-prefix
                    res.pinHonored = true
                } else {
                    res.pinHonored = false
                }
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

    /// npm/PyPI honor a pin through a per-version URL that returns the package
    /// doc directly. Unlike the confirm-probe ecosystems, that doc carries its own
    /// version, so we compare it to the requested pin: an exact match →
    /// pinHonored=true; a mismatch → NOT a confirmed immutable pin (npm dist-tags
    /// like `beta`/`next`/`latest`, and partial pins like `18`, also 200 here but
    /// resolve to a moving/other concrete version — reporting them as honored
    /// would be a faked pin, issue #36 round-2). On an outright miss we fall back
    /// to latest with pinHonored=false, never a bare nil that hides the outcome.
    private func fetchDirectPin(
        pinnedURL: (String) -> String, latestURL: String,
        parse: (Data) throws -> RegistryResolution, version: String?, fallbackToLatest: Bool
    ) async -> RegistryResolution? {
        guard let pin = version else { return await getParse(latestURL, parse) }
        if var res = await getParse(pinnedURL(stripLeadingV(pin)), parse) {
            res.pinHonored = res.version.map { versionsEqual($0, pin) } ?? false
            return res
        }
        // The pinned version wasn't found. During auto-detect on a non-last
        // ecosystem, return nil so the loop tries the next registry's exact pin
        // instead of short-circuiting to this one's latest (issue #36 round-3).
        guard fallbackToLatest else { return nil }
        guard var latest = await getParse(latestURL, parse) else { return nil }
        latest.pinHonored = false
        return latest
    }

    /// Fetch the latest-level resolution (repo/docs), then — if a pin was
    /// requested — confirm it at the per-version endpoint. On confirmation,
    /// override `version` with the confirmed pin and set `pinHonored=true`;
    /// otherwise keep latest and set `pinHonored=false`. Repo/docs URLs stay
    /// latest-level (they're default-branch regardless of the pin).
    private func fetchWithPinConfirm(
        latestURL: String, latestParse: (Data) throws -> RegistryResolution,
        version: String?, confirmURL: (String) -> String, confirmParse: @escaping (Data) -> String?
    ) async -> RegistryResolution? {
        guard var res = await getParse(latestURL, latestParse) else { return nil }
        if let pin = version {
            // A leading `v` never appears in crates/rubygems version URLs; strip it
            // so a v-prefixed input (accepted by isSafeVersion) still matches.
            if let confirmed = await confirmPin(confirmURL(stripLeadingV(pin)), confirmParse, wants: pin) {
                res.version = confirmed
                res.pinHonored = true
            } else {
                res.pinHonored = false
            }
        }
        return res
    }

    /// Normalize a version string for interpolation into a per-version registry
    /// URL or for pin equality: drop a single leading `v` when it prefixes a digit
    /// (Go tags are written `v1.9.1` everywhere, but only the Go proxy path wants
    /// the `v` — and it adds its own; crates/rubygems/npm/pypi identifiers never
    /// carry a `v`). Used by BOTH the URL builders and `confirmPin`/`versionsEqual`
    /// so the normalization can't drift between them (issue #36 round-2).
    private func stripLeadingV(_ s: String) -> String {
        if s.hasPrefix("v"), let second = s.dropFirst().first, second.isNumber {
            return String(s.dropFirst())
        }
        return s
    }

    /// Two version strings are equal modulo a leading `v` (e.g. `v1.9.1` == `1.9.1`).
    private func versionsEqual(_ a: String, _ b: String) -> Bool {
        stripLeadingV(a) == stripLeadingV(b)
    }

    /// Confirm a pinned version exists at a per-version endpoint. Returns the
    /// endpoint's own version string on a match (so Go keeps its `v` prefix), or
    /// nil if the endpoint 404s / reports a different version. A leading `v` is
    /// normalized on both sides before comparison (Go tags are v-prefixed).
    private func confirmPin(_ url: String, _ parse: (Data) -> String?, wants: String) async -> String? {
        guard let resp = try? await http.get(url), resp.status == 200,
              let got = parse(resp.body) else { return nil }
        return versionsEqual(got, wants) ? got : nil
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

    /// Probe ALL ordered llms.txt candidates for a host concurrently (#57); return
    /// every real hit sorted by candidate index. Selection by INDEX — never by
    /// completion order — keeps the outcome deterministic and identical to the old
    /// sequential first-hit-wins loop, while the wall-clock cost drops from the sum
    /// of the probes to roughly the slowest one. Trade (documented + test-pinned):
    /// all of this ONE host's candidates are fetched even when the first would have
    /// hit — bounded politeness (≤6 requests to a single origin).
    private func probeLlmsAll(host: String) async -> [(index: Int, source: DiscoverySource)] {
        let candidates = llmsTxtCandidates(for: host)
        guard !candidates.isEmpty else { return [] }
        let hits = await withTaskGroup(of: (Int, DiscoverySource?).self) { group in
            for (i, url) in candidates.enumerated() {
                group.addTask { (i, await self.probeExact(url: url)) }
            }
            var out: [(Int, DiscoverySource)] = []
            for await (i, src) in group {
                if let s = src { out.append((i, s)) }
            }
            return out
        }
        return hits.sorted { $0.0 < $1.0 }.map { (index: $0.0, source: $0.1) }
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
