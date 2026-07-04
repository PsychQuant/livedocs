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

    init(engine: DiscoveryEngine = DiscoveryEngine(http: ETagCachingHTTPClient(inner: URLSessionHTTPClient()))) {
        self.engine = engine
        self.tools = Self.defineTools()
        self.server = Server(
            name: "che-livedocs-mcp",
            version: LiveDocsVersion.current,
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
        let versionProp: Value = .object(["type": .string("string"), "description": .string("Pin to a specific version, e.g. '18.3.1' (React 18 vs 19). Honored for npm/pypi/crates/go/rubygems (confirmed at their per-version endpoints; latest_version returns pin_honored:true/false); jsr/packagist/maven/cran are latest-only and report pin_honored:false. llms.txt docs are always latest and get labeled as not-pinned.")])
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
                description: "The deterministic 'what is the latest released version right now' answer for a library, from its package registry, plus changelog/repo URLs. This is the strongest currency signal — more reliable than scraping a docs page. When you pass a version pin, the response includes pin_honored (true = confirmed at the ecosystem's per-version endpoint and 'version' is the pin; false = the pin was not confirmed as an exact version — a latest-only ecosystem, an unknown version, or a non-exact token like an npm dist-tag/partial version. On false, 'version' is the registry's current resolution, which may be the latest OR the concrete version a tag/partial resolved to — NOT guaranteed to be the latest stable, and not a confirmed pin).",
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
                description: "Introspect the HIGHEST-fidelity 'what can I actually call' source that lives OUTSIDE the web: an OpenAPI/Swagger JSON spec, a GraphQL endpoint's schema, an installed CLI's --help/--version, or the LOCALLY INSTALLED version of an R package (kind=r-pkg — the 'local' half of a version check; READ-ONLY, never installs). For the effective LANGUAGE-RUNTIME version of the current project (Python/Node/Go/Rust/Java/.NET/Swift/R; 'javascript' aliases to node), use kind=runtime with target=<language> or 'auto' — active toolchain is authoritative, declared pins cross-check, unresolved is reported honestly (READ-ONLY). This reads the machine/installed artifact itself, not prose about it. target = a URL (openapi/graphql), a bare command name (cli), or an R package name (r-pkg). kind defaults to auto (URL → try openapi then graphql; bare word → cli).",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "target": .object(["type": .string("string"), "description": .string("API base URL / GraphQL endpoint, or a CLI command name like 'gh'")]),
                        "kind": .object([
                            "type": .string("string"),
                            "enum": .array([.string("auto"), .string("openapi"), .string("graphql"), .string("cli"), .string("r-pkg"), .string("runtime")]),
                            "description": .string("Force a mode. Default auto.")
                        ]),
                        "flag": .object(["type": .string("string"), "description": .string("CLI mode only: --help (default) or --version")]),
                        "path": .object(["type": .string("string"), "description": .string("runtime kind only: the project directory to resolve the effective runtime for (absolute path). Defaults to the server's current working directory — set it when the project isn't the server's launch dir (marketplace/Desktop installs, monorepos).")])
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
            // Clamp: a negative max_bytes would trap `prefix(_:)` and kill the server.
            let cap = max(0, args["max_bytes"]?.intValue ?? 200_000)
            let raw = try await engine.fetchRaw(url: url)
            // Strip control/ANSI/bidi from untrusted fetched content, then truncate
            // on a UTF-8 byte boundary (the cap is in bytes, not Characters).
            let clean = TextSanitize.forModel(raw)
            return TextSanitize.truncateUTF8(clean, maxBytes: cap)

        case "latest_version":
            guard let lib = args["library"]?.stringValue else { throw ToolError.missing("library") }
            let eco = args["ecosystem"]?.stringValue.flatMap(Ecosystem.init(rawValue:))
            let pin = args["version"]?.stringValue
            let res = await engine.latestVersion(library: lib, ecosystem: eco, version: pin)
            return encodeLatestVersion(res, library: lib, pin: pin, eco: eco)

        case "introspect":
            guard let target = args["target"]?.stringValue else { throw ToolError.missing("target") }
            let kind = args["kind"]?.stringValue ?? "auto"
            return try await introspect(target: target, kind: kind,
                                        flag: args["flag"]?.stringValue ?? "--help",
                                        path: args["path"]?.stringValue)

        default:
            throw ToolError.unknownTool(name)
        }
    }

    private func introspect(target: String, kind: String, flag: String, path: String?) async throws -> String {
        let isURL = target.contains("://")
        switch kind {
        case "cli":
            return try CLIIntrospect.run(command: target, flag: flag)
        case "r-pkg":
            return encodeRInstalled(package: target)
        case "runtime":
            let langId = (target.lowercased() == "auto" || target.isEmpty) ? nil : target
            let cwd = try runtimeCwd(path)
            return encodeRuntime(RuntimeIntrospect.resolve(cwd: cwd, languageId: langId), cwd: cwd)
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

    /// Resolve the directory to introspect a runtime for. An explicit `path` must
    /// exist and be a directory (else a clear error, rather than silently reading
    /// the wrong place); with no path we fall back to the server's cwd.
    private func runtimeCwd(_ path: String?) throws -> String {
        guard let path, !path.isEmpty else { return FileManager.default.currentDirectoryPath }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw ToolError.invalidPath(path)
        }
        return path
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

    private func encodeResolution(_ r: RegistryResolution, note: String? = nil) -> String {
        var obj: [String: Any] = [
            "version": r.version as Any,
            "changelog": r.changelog as Any,
            "documentation": r.documentation as Any,
            "repository": r.repository as Any,
            "homepage": r.homepage as Any
        ]
        // pin_honored is a pin-request-only fact: emit it only when a pin was
        // actually requested (nil = no pin asked) so agents get a machine-readable
        // signal instead of parsing note text (issue #36).
        if let honored = r.pinHonored { obj["pin_honored"] = honored }
        if let note { obj["note"] = note }
        return jsonString(obj)
    }

    /// Build the `latest_version` tool response. Decides honored-vs-not from
    /// `pinHonored` (NOT string equality — Go pins carry a `v` prefix, so
    /// `version != pin` would misread a confirmed pin as not-applied), and always
    /// routes through `encodeResolution` so the `pin_honored` signal reaches the
    /// caller in every case, not just the exact-match one (issue #36 verify).
    /// `internal` (not private) so the boundary logic is unit-testable without the
    /// MCP transport layer.
    func encodeLatestVersion(_ res: RegistryResolution?, library: String, pin: String?, eco: Ecosystem?) -> String {
        guard let res else {
            // No resolution at all — package (or its whole registry) not found.
            // A pin was requested but couldn't be honored (there's nothing to pin
            // to), so still emit pin_honored:false — a requested pin ALWAYS gets a
            // machine-readable signal, never absent (which would read as "no pin
            // asked"). Issue #36 round-3.
            if let pin {
                return jsonString(["version": NSNull(), "requested": pin, "pin_honored": false,
                                   "note": "Not found for '\(library)'. Pass the right ecosystem (crates/go/rubygems/jsr/packagist/maven need it explicitly) and library format."])
            }
            return #"{"version":null,"note":"Not found. For crates/go/rubygems/jsr/packagist/maven you must pass ecosystem explicitly (and the right library format)."}"#
        }
        // A pin was requested but not honored → attach an accurate, ecosystem-aware
        // note alongside the machine-readable pin_honored:false. Auto-detect (nil
        // eco) only tries npm/pypi, which DO support pins → treat as pin-supporting.
        if let pin, res.pinHonored == false {
            // Two false sub-cases. Latest-only ecosystems never attempt a pin, so
            // 'version' is definitively the latest. For pin-supporting ecosystems a
            // false means the pin wasn't confirmed as an exact version — it may be a
            // dist-tag/range that resolved to some OTHER concrete version, or an
            // unknown version that fell back to latest; either way 'version' is the
            // registry's resolution, not a confirmed pin (don't over-claim "latest").
            let note: String
            if !(eco?.supportsVersionPin ?? true) {
                note = "Pin '\(pin)' not applied — this ecosystem is latest-only (jsr/packagist/maven/cran); 'version' is the latest. npm/pypi/crates/go/rubygems honor a confirmed pin."
            } else {
                note = "Pin '\(pin)' not confirmed as an exact version (it may be a dist-tag, partial version, or an unknown version); 'version' is the registry's current resolution, not a confirmed pin."
            }
            return encodeResolution(res, note: note)
        }
        return encodeResolution(res)
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

    private func encodeRuntime(_ results: [RuntimeIntrospect.LanguageResult], cwd: String) -> String {
        if results.isEmpty {
            return jsonString(["source": "runtime", "cwd": cwd,
                               "note": "No depth-adapter language detected here (pass target=<language> to force), or the language id was rejected."])
        }
        let arr: [[String: Any]] = results.map { r in
            switch r.resolution {
            case .resolved(let version, let src, let sem, let env):
                return ["language": r.languageId, "resolved": true, "effective_version": version,
                        "source": src, "semantics": semanticsName(sem), "resolved_env": env,
                        "note": "READ-ONLY: effective runtime version for this project; active toolchain is authoritative."]
            case .notResolved(let reason):
                return ["language": r.languageId, "resolved": false, "effective_version": NSNull(),
                        "note": "Not resolved (not fabricating a version): \(reason)"]
            }
        }
        return jsonString(["source": "runtime", "cwd": cwd, "runtimes": arr])
    }

    private func semanticsName(_ s: PinSemantics) -> String {
        switch s {
        case .activeToolchain: return "active-toolchain"
        case .exactVersion:    return "exact-version"
        case .directive:       return "directive"
        case .constraint:      return "constraint"
        case .languageMode:    return "language-mode"
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
    case invalidPath(String)

    var errorDescription: String? {
        switch self {
        case .missing(let p): return "Required parameter '\(p)' is missing"
        case .unknownTool(let n): return "Unknown tool '\(n)'"
        case .invalidPath(let p): return "path '\(p)' does not exist or is not a directory"
        }
    }
}
