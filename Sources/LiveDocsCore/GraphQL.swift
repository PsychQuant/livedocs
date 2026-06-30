import Foundation

/// A minimal GraphQL introspection query. We deliberately ask for only the
/// schema's shape (root type names + the type list), not the full recursive
/// field/arg tree — enough to confirm "this is a live GraphQL endpoint and here
/// is its surface" without pulling megabytes. Agents can drill in with a
/// targeted follow-up query if needed.
public let graphQLIntrospectionQuery =
    "{\"query\":\"{__schema{queryType{name} mutationType{name} subscriptionType{name} types{name kind}}}\"}"

public struct GraphQLSummary: Sendable, Equatable {
    public let queryType: String?
    public let mutationType: String?
    public let subscriptionType: String?
    public let typeCount: Int
    /// User-defined types only (introspection/scalar noise filtered out), capped.
    public let sampleTypes: [String]

    public init(queryType: String?, mutationType: String?, subscriptionType: String?, typeCount: Int, sampleTypes: [String]) {
        self.queryType = queryType
        self.mutationType = mutationType
        self.subscriptionType = subscriptionType
        self.typeCount = typeCount
        self.sampleTypes = sampleTypes
    }
}

public enum GraphQLError: Error, Equatable { case notAGraphQLResponse }

/// Parse a GraphQL introspection response: `{ "data": { "__schema": { ... } } }`.
/// Internal `__*` types and built-in scalars are filtered from `sampleTypes` so
/// the agent sees the domain surface, not plumbing.
public func parseGraphQLIntrospection(_ data: Data, sampleLimit: Int = 40) throws -> GraphQLSummary {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let schema = (root["data"] as? [String: Any])?["__schema"] as? [String: Any]
    else { throw GraphQLError.notAGraphQLResponse }

    func rootName(_ key: String) -> String? {
        (schema[key] as? [String: Any])?["name"] as? String
    }

    let allTypes = (schema["types"] as? [[String: Any]]) ?? []
    let builtinScalars: Set<String> = ["String", "Int", "Float", "Boolean", "ID"]
    let domain = allTypes.compactMap { $0["name"] as? String }
        .filter { !$0.hasPrefix("__") && !builtinScalars.contains($0) }
        .sorted()

    return GraphQLSummary(
        queryType: rootName("queryType"),
        mutationType: rootName("mutationType"),
        subscriptionType: rootName("subscriptionType"),
        typeCount: allTypes.count,
        sampleTypes: Array(domain.prefix(sampleLimit))
    )
}
