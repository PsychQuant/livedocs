import Foundation

public enum Ecosystem: String, Sendable, CaseIterable {
    case npm, pypi
}

/// What the caller (the router skill, via the MCP tool) asks the engine to
/// resolve. The fuzzy "which library is this" decision is made upstream by the
/// LLM; by the time it reaches here the inputs are concrete and the work is
/// deterministic.
public struct DiscoveryRequest: Sendable {
    public var library: String?
    public var ecosystem: Ecosystem?
    public var docsURL: String?

    public init(library: String? = nil, ecosystem: Ecosystem? = nil, docsURL: String? = nil) {
        self.library = library
        self.ecosystem = ecosystem
        self.docsURL = docsURL
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
           let res = await resolveRegistry(library: lib, ecosystem: req.ecosystem) {
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
    public func latestVersion(library: String, ecosystem: Ecosystem?) async -> RegistryResolution? {
        await resolveRegistry(library: library, ecosystem: ecosystem)
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

    private func resolveRegistry(library: String, ecosystem: Ecosystem?) async -> RegistryResolution? {
        let order: [Ecosystem] = ecosystem.map { [$0] } ?? [.npm, .pypi]
        for eco in order {
            let url: String
            switch eco {
            case .npm:  url = "https://registry.npmjs.org/\(library)/latest"
            case .pypi: url = "https://pypi.org/pypi/\(library)/json"
            }
            guard let resp = try? await http.get(url), resp.status == 200 else { continue }
            let parsed: RegistryResolution? = {
                switch eco {
                case .npm:  return try? parseNpmLatest(resp.body)
                case .pypi: return try? parsePyPI(resp.body)
                }
            }()
            if let parsed { return parsed }
        }
        return nil
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
