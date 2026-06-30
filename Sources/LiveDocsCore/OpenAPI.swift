import Foundation

/// A compact view of an OpenAPI / Swagger document — enough for an agent to know
/// the API surface and exact version without us shipping the whole (often huge)
/// spec back. This is the highest-fidelity "what can I call" source: the schema
/// IS the contract, not prose describing it.
public struct OpenAPISummary: Sendable, Equatable {
    public let title: String?
    public let apiVersion: String?       // info.version — the API's own version
    public let specVersion: String?      // "openapi": "3.1.0" / "swagger": "2.0"
    public let operations: [OpenAPIOperation]

    public init(title: String?, apiVersion: String?, specVersion: String?, operations: [OpenAPIOperation]) {
        self.title = title
        self.apiVersion = apiVersion
        self.specVersion = specVersion
        self.operations = operations
    }
}

public struct OpenAPIOperation: Sendable, Equatable {
    public let method: String            // GET, POST, ...
    public let path: String              // /v1/things/{id}
    public let summary: String?
    public let operationId: String?

    public init(method: String, path: String, summary: String?, operationId: String?) {
        self.method = method
        self.path = path
        self.summary = summary
        self.operationId = operationId
    }
}

/// Ordered candidate URLs where an OpenAPI/Swagger JSON spec conventionally lives,
/// covering the big framework defaults: bare `/openapi.json`, Spring's
/// `/v3/api-docs`, Swagger-UI's `/swagger.json`, and the `.well-known` proposal.
public func openAPICandidates(for base: String) -> [String] {
    guard let (origin, path) = splitOriginAndPath(base) else { return [] }
    var out: [String] = []
    func add(_ u: String) { if !out.contains(u) { out.append(u) } }

    if !path.isEmpty { add(origin + path + "/openapi.json") }
    add(origin + "/openapi.json")
    add(origin + "/swagger.json")
    add(origin + "/v3/api-docs")              // Spring springdoc default
    add(origin + "/api-docs")
    add(origin + "/.well-known/openapi.json")
    return out
}

public enum OpenAPIError: Error, Equatable { case notAnOpenAPIDocument }

/// Parse an OpenAPI/Swagger **JSON** document into a summary. YAML specs are out
/// of scope for the MVP (no YAML parser dependency); a YAML spec simply fails to
/// parse here and the engine moves to the next source. The `methods` allowlist
/// keeps `parameters`/`$ref`/`servers` siblings of an operation from being read
/// as bogus HTTP verbs.
public func parseOpenAPI(_ data: Data) throws -> OpenAPISummary {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw OpenAPIError.notAnOpenAPIDocument
    }
    let specVersion = (root["openapi"] as? String) ?? (root["swagger"] as? String)
    guard specVersion != nil else { throw OpenAPIError.notAnOpenAPIDocument }

    let info = root["info"] as? [String: Any]
    let httpMethods: Set<String> = ["get", "put", "post", "delete", "options", "head", "patch", "trace"]

    var ops: [OpenAPIOperation] = []
    if let paths = root["paths"] as? [String: Any] {
        for (path, item) in paths {
            guard let methods = item as? [String: Any] else { continue }
            for (method, op) in methods where httpMethods.contains(method.lowercased()) {
                let opObj = op as? [String: Any]
                ops.append(OpenAPIOperation(
                    method: method.uppercased(),
                    path: path,
                    summary: opObj?["summary"] as? String,
                    operationId: opObj?["operationId"] as? String
                ))
            }
        }
    }
    // Deterministic ordering so output is stable for the same spec.
    ops.sort { ($0.path, $0.method) < ($1.path, $1.method) }

    return OpenAPISummary(
        title: info?["title"] as? String,
        apiVersion: info?["version"] as? String,
        specVersion: specVersion,
        operations: ops
    )
}
