import Foundation
import MCP
import LiveDocsCore

/// MCP stdio server exposing the LiveDocs discovery engine. The fuzzy "which
/// library" decision is the calling agent's job (a router skill); these tools
/// take concrete inputs and do deterministic, primary-source-first work.
final class CheLiveDocsMCPServer {
    private let server: Server
    private let transport: StdioTransport
    private let engine: DiscoveryEngine
    private let tools: [Tool]

    init(engine: DiscoveryEngine = DiscoveryEngine(http: URLSessionHTTPClient())) {
        self.engine = engine
        self.tools = Self.defineTools()
        self.server = Server(
            name: "che-livedocs-mcp",
            version: "0.3.0",
            capabilities: .init(tools: .init())
        )
        self.transport = StdioTransport()
    }

    func run() async throws {
        await registerHandlers()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    // MARK: - Tool definitions

    static func defineTools() -> [Tool] {
        let ecosystemEnum: Value = .object([
            "type": .string("string"),
            "enum": .array([.string("npm"), .string("pypi"), .string("crates"), .string("go"),
                            .string("rubygems"), .string("jsr"), .string("packagist"), .string("maven"), .string("cran")]),
            "description": .string("Package registry the library lives in. npm/pypi auto-detect if omitted; crates/go/rubygems/jsr/packagist/maven/cran MUST be named explicitly. Library format per ecosystem: npm 'react' or '@scope/name'; go full module path 'github.com/gin-gonic/gin'; jsr '@scope/name'; packagist 'vendor/package'; maven 'group:artifact'; cran (R) 'dplyr'.")
        ])
        let versionProp: Value = .object(["type": .string("string"), "description": .string("Pin to a specific version, e.g. '18.3.1' (React 18 vs 19). Honored for npm/pypi; other ecosystems are latest-only. llms.txt docs are always latest and get labeled as not-pinned.")])
        return [
            Tool(
                name: "resolve_source",
                description: "Discover the best PRIMARY documentation source(s) for a library, freshest+highest-fidelity first. Tries llms.txt → package registry → repo. Returns ranked JSON {kind,url,fidelity,freshness,version}. Empty result means no primary source found — fall back to context7/web and label it low-fidelity. Provide library (+ecosystem) and/or an explicit docs_url.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "library": .object(["type": .string("string"), "description": .string("Package name, e.g. react, fastapi")]),
                        "ecosystem": ecosystemEnum,
                        "version": versionProp,
                        "docs_url": .object(["type": .string("string"), "description": .string("Explicit docs host/URL to probe for llms.txt, e.g. https://hono.dev")])
                    ])
                ])
            ),
            Tool(
                name: "fetch_docs",
                description: "Fetch the RAW text of a source URL (a resolve_source result, an llms.txt, a raw README). This is the high-fidelity path: verbatim primary content, no lossy index in between. Use for config/API-signature questions where exactness matters.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "url": .object(["type": .string("string"), "description": .string("The source URL to fetch verbatim")]),
                        "max_bytes": .object(["type": .string("integer"), "description": .string("Optional truncation cap (default 200000)")])
                    ]),
                    "required": .array([.string("url")])
                ])
            ),
            Tool(
                name: "latest_version",
                description: "The deterministic 'what is the latest released version right now' answer for a library, from its package registry, plus changelog/repo URLs. This is the strongest currency signal — more reliable than scraping a docs page.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "library": .object(["type": .string("string"), "description": .string("Package name")]),
                        "ecosystem": ecosystemEnum,
                        "version": versionProp
                    ]),
                    "required": .array([.string("library")])
                ])
            ),
            Tool(
                name: "introspect",
                description: "Introspect the HIGHEST-fidelity 'what can I actually call' source that lives OUTSIDE the web: an OpenAPI/Swagger JSON spec, a GraphQL endpoint's schema, an installed CLI's --help/--version, or the LOCALLY INSTALLED version of an R package (kind=r-pkg — the 'local' half of a version check; READ-ONLY, never installs). This reads the machine/installed artifact itself, not prose about it. target = a URL (openapi/graphql), a bare command name (cli), or an R package name (r-pkg). kind defaults to auto (URL → try openapi then graphql; bare word → cli).",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "target": .object(["type": .string("string"), "description": .string("API base URL / GraphQL endpoint, or a CLI command name like 'gh'")]),
                        "kind": .object([
                            "type": .string("string"),
                            "enum": .array([.string("auto"), .string("openapi"), .string("graphql"), .string("cli"), .string("r-pkg")]),
                            "description": .string("Force a mode. Default auto.")
                        ]),
                        "flag": .object(["type": .string("string"), "description": .string("CLI mode only: --help (default) or --version")])
                    ]),
                    "required": .array([.string("target")])
                ])
            )
        ]
    }

    // MARK: - Handlers

    private func registerHandlers() async {
        await server.withMethodHandler(ListTools.self) { [tools] _ in
            ListTools.Result(tools: tools)
        }
        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self else {
                return CallTool.Result(content: [.text(text: "Server unavailable", annotations: nil, _meta: nil)], isError: true)
            }
            do {
                let text = try await self.execute(name: params.name, args: params.arguments ?? [:])
                return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
            } catch {
                return CallTool.Result(content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)], isError: true)
            }
        }
    }

    private func execute(name: String, args: [String: Value]) async throws -> String {
        switch name {
        case "resolve_source":
            let req = DiscoveryRequest(
                library: args["library"]?.stringValue,
                ecosystem: args["ecosystem"]?.stringValue.flatMap(Ecosystem.init(rawValue:)),
                docsURL: args["docs_url"]?.stringValue,
                version: args["version"]?.stringValue
            )
            let sources = await engine.resolveSources(req)
            if sources.isEmpty {
                return #"{"sources":[],"note":"No primary source found. Fall back to context7/web and label it LOW fidelity."}"#
            }
            return encodeSources(sources)

        case "fetch_docs":
            guard let url = args["url"]?.stringValue else { throw ToolError.missing("url") }
            let cap = args["max_bytes"]?.intValue ?? 200_000
            let raw = try await engine.fetchRaw(url: url)
            return raw.count > cap
                ? String(raw.prefix(cap)) + "\n\n[...truncated at \(cap) bytes; raise max_bytes for the rest]"
                : raw

        case "latest_version":
            guard let lib = args["library"]?.stringValue else { throw ToolError.missing("library") }
            let eco = args["ecosystem"]?.stringValue.flatMap(Ecosystem.init(rawValue:))
            let pin = args["version"]?.stringValue
            if let res = await engine.latestVersion(library: lib, ecosystem: eco, version: pin) {
                // A pin was asked for but the resolved version differs → the pin was
                // ignored (latest-only ecosystem) or wasn't matched. Say so instead of
                // passing latest off as the pinned version.
                if let pin, res.version != pin {
                    return jsonString([
                        "version": res.version as Any, "requested": pin,
                        "note": "Pinned version '\(pin)' not applied — this ecosystem is latest-only (only npm/pypi honor a pin), or the version wasn't found; 'version' is the latest.",
                        "changelog": res.changelog as Any, "repository": res.repository as Any,
                        "documentation": res.documentation as Any, "homepage": res.homepage as Any])
                }
                return encodeResolution(res)
            }
            // A pinned version that didn't resolve: fall back to latest so the agent
            // learns the current version instead of a bare null.
            if let pin, let latest = await engine.latestVersion(library: lib, ecosystem: eco) {
                return jsonString(["version": NSNull(), "requested": pin, "latest": latest.version as Any,
                                   "note": "Version \(pin) not found; current latest shown under 'latest'."])
            }
            return #"{"version":null,"note":"Not found. For crates/go/rubygems/jsr/packagist/maven you must pass ecosystem explicitly (and the right library format)."}"#

        case "introspect":
            guard let target = args["target"]?.stringValue else { throw ToolError.missing("target") }
            let kind = args["kind"]?.stringValue ?? "auto"
            return try await introspect(target: target, kind: kind, flag: args["flag"]?.stringValue ?? "--help")

        default:
            throw ToolError.unknownTool(name)
        }
    }

    private func introspect(target: String, kind: String, flag: String) async throws -> String {
        let isURL = target.contains("://")
        switch kind {
        case "cli":
            return try CLIIntrospect.run(command: target, flag: flag)
        case "r-pkg":
            return encodeRInstalled(package: target)
        case "openapi":
            guard let s = await engine.introspectOpenAPI(baseURL: target) else { return #"{"note":"No OpenAPI spec found at that base."}"# }
            return encodeOpenAPI(s)
        case "graphql":
            guard let s = await engine.introspectGraphQL(endpoint: target) else { return #"{"note":"No GraphQL schema at that endpoint."}"# }
            return encodeGraphQL(s)
        default: // auto
            if !isURL { return try CLIIntrospect.run(command: target, flag: flag) }
            if let s = await engine.introspectOpenAPI(baseURL: target) { return encodeOpenAPI(s) }
            if let s = await engine.introspectGraphQL(endpoint: target) { return encodeGraphQL(s) }
            return #"{"note":"No OpenAPI or GraphQL schema discoverable at that URL."}"#
        }
    }

    // MARK: - JSON encoding (hand-rolled to keep LiveDocsCore free of an encoding policy)

    private func encodeSources(_ sources: [DiscoverySource]) -> String {
        let arr: [[String: Any]] = sources.map {
            [
                "kind": $0.kind.rawValue,
                "url": $0.url,
                "fidelity": fidelityName($0.fidelity),
                "freshness": freshnessName($0.freshness),
                "version": $0.version as Any,
                "title": $0.title as Any
            ]
        }
        return jsonString(["sources": arr])
    }

    private func encodeResolution(_ r: RegistryResolution) -> String {
        jsonString([
            "version": r.version as Any,
            "changelog": r.changelog as Any,
            "documentation": r.documentation as Any,
            "repository": r.repository as Any,
            "homepage": r.homepage as Any
        ])
    }

    private func encodeOpenAPI(_ s: OpenAPISummary) -> String {
        let ops = s.operations.map { op -> [String: Any] in
            ["method": op.method, "path": op.path,
             "summary": op.summary as Any, "operationId": op.operationId as Any]
        }
        return jsonString([
            "source": "openapi",
            "title": s.title as Any,
            "apiVersion": s.apiVersion as Any,
            "specVersion": s.specVersion as Any,
            "operationCount": s.operations.count,
            "operations": ops
        ])
    }

    private func encodeGraphQL(_ s: GraphQLSummary) -> String {
        jsonString([
            "source": "graphql",
            "queryType": s.queryType as Any,
            "mutationType": s.mutationType as Any,
            "subscriptionType": s.subscriptionType as Any,
            "typeCount": s.typeCount,
            "sampleTypes": s.sampleTypes
        ])
    }

    /// Encode an installed-R-package probe. READ-ONLY: distinguishes R-absent,
    /// package-not-installed, and installed (with the resolved library path).
    private func encodeRInstalled(package: String) -> String {
        switch RIntrospect.installed(package: package) {
        case .none:
            return jsonString(["installed_version": NSNull(),
                               "note": "R (Rscript) not found on this machine; cannot introspect installed R packages."])
        case .some(.notInstalled):
            return jsonString(["package": package, "installed_version": NSNull(),
                               "note": "'\(package)' is not installed in the current context (not fabricating a global version)."])
        case .some(.malformed):
            return jsonString(["package": package, "installed_version": NSNull(),
                               "note": "Could not read the installed version (invalid R package name or R error)."])
        case .some(.installed(let version, let libPath)):
            return jsonString(["source": "r-installed", "package": package, "ecosystem": "cran",
                               "installed_version": version, "resolved_env": libPath,
                               "note": "READ-ONLY: this is your locally installed version, not the CRAN latest."])
        }
    }

    private func fidelityName(_ f: Fidelity) -> String {
        switch f { case .low: return "low"; case .medium: return "medium"; case .high: return "high" }
    }
    private func freshnessName(_ f: Freshness) -> String {
        switch f { case .unknown: return "unknown"; case .recent: return "recent"; case .live: return "live" }
    }

    private func jsonString(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}

enum ToolError: Error, LocalizedError {
    case missing(String)
    case unknownTool(String)

    var errorDescription: String? {
        switch self {
        case .missing(let p): return "Required parameter '\(p)' is missing"
        case .unknownTool(let n): return "Unknown tool '\(n)'"
        }
    }
}
