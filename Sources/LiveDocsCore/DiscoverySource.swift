import Foundation

/// What kind of primary source a discovered document is. Ordering of the cases
/// is *not* the ranking — ranking is computed from `fidelity` + `freshness` in
/// `DiscoverySource.rankKey` so the policy lives in one place.
public enum SourceKind: String, Sendable, Equatable, CaseIterable {
    case llmsFull       // llms-full.txt — near-complete primary text in one file
    case llmsIndex      // llms.txt — curated index of doc links (LLM-designed)
    case openAPI        // OpenAPI / Swagger schema (the API contract itself)
    case graphQL        // GraphQL introspection (__schema)
    case registryDocs   // docs/changelog URL resolved deterministically via npm/PyPI
    case repoReadme     // GitHub README / CHANGELOG / releases (raw)
    case cliIntrospect  // `<tool> --help` / --json field discovery (live binary)
    case context7       // pre-built lossy index — fallback only
    case web            // last-resort web search
}

/// How faithful the source is to the canonical truth. Higher = closer to raw.
/// This is the axis that makes LiveDocs different from a lossy index: a `high`
/// source can be read verbatim; a `low` source is a summary of a summary.
public enum Fidelity: Int, Sendable, Equatable, Comparable {
    case low = 0        // lossy index / summary (context7, web)
    case medium = 1     // curated or derived (llms index, registry-resolved links)
    case high = 2       // raw primary (llms-full, OpenAPI, repo raw, introspection)

    public static func < (lhs: Fidelity, rhs: Fidelity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// How current the source is relative to "the latest release right now".
public enum Freshness: Int, Sendable, Equatable, Comparable {
    case unknown = 0    // can't tell (static page, no version signal)
    case recent = 1     // periodically rebuilt index (context7-style)
    case live = 2       // fetched on demand from canonical host this instant

    public static func < (lhs: Freshness, rhs: Freshness) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A candidate primary source for a query, with enough metadata to rank it and
/// to tell the caller honestly how trustworthy it is.
public struct DiscoverySource: Sendable, Equatable {
    public let kind: SourceKind
    public let url: String
    public let fidelity: Fidelity
    public let freshness: Freshness
    public let title: String?
    /// Resolved "latest version" string when the source could supply one
    /// (registry `.version`, a release tag). nil when the source is version-less.
    public let version: String?

    public init(
        kind: SourceKind,
        url: String,
        fidelity: Fidelity,
        freshness: Freshness,
        title: String? = nil,
        version: String? = nil
    ) {
        self.kind = kind
        self.url = url
        self.fidelity = fidelity
        self.freshness = freshness
        self.title = title
        self.version = version
    }

    /// Ranking key — higher sorts first. Fidelity dominates (the whole point of
    /// LiveDocs), freshness breaks ties. Kept as a tuple so `Array.sorted` stays
    /// a one-liner and the policy is auditable in one spot.
    public var rankKey: (Int, Int) {
        (fidelity.rawValue, freshness.rawValue)
    }
}

public extension Array where Element == DiscoverySource {
    /// Best-first ordering: highest fidelity, then freshest. Stable for equal keys.
    func rankedBestFirst() -> [DiscoverySource] {
        enumerated()
            .sorted { a, b in
                if a.element.rankKey != b.element.rankKey {
                    return a.element.rankKey > b.element.rankKey
                }
                return a.offset < b.offset   // stable
            }
            .map(\.element)
    }
}
