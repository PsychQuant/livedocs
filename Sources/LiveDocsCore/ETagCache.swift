import Foundation

/// Thread-safe per-process store of `ETag → last 200 response` keyed by URL.
/// In-memory only: it speeds up repeated fetches within a running MCP session
/// (a docs file probed then fetched, a registry hit re-queried) and is empty on
/// restart. Persisting to disk is a possible follow-up.
public actor ETagCacheStore {
    public struct Entry: Sendable {
        public let etag: String
        public let response: HTTPResponse
    }

    private var map: [String: Entry] = [:]
    public init() {}

    func entry(for url: String) -> Entry? { map[url] }
    func set(url: String, etag: String, response: HTTPResponse) {
        map[url] = Entry(etag: etag, response: response)
    }
}

/// An `HTTPClient` decorator that adds **ETag conditional revalidation**.
///
/// This is the ONLY thesis-safe way to cache content. It **always revalidates**:
/// when a URL is in the cache it sends `If-None-Match: <etag>` on every request,
/// so the server decides freshness. On `304 Not Modified` it serves the cached
/// body (the win: no re-download / re-parse of an unchanged, possibly large doc);
/// on `200` with a new `ETag` it refreshes the cache. It deliberately does NOT
/// honor `max-age` / serve blind-stale — "latest" stays latest, it's just cheaper
/// when nothing changed. POSTs (e.g. GraphQL introspection) are never cached.
public struct ETagCachingHTTPClient: HTTPClient {
    private let inner: any HTTPClient
    private let store: ETagCacheStore

    public init(inner: any HTTPClient, store: ETagCacheStore = ETagCacheStore()) {
        self.inner = inner
        self.store = store
    }

    public func get(_ url: String, headers: [String: String]) async throws -> HTTPResponse {
        var headers = headers
        let cached = await store.entry(for: url)
        if let cached { headers["If-None-Match"] = cached.etag }   // always revalidate

        let resp = try await inner.get(url, headers: headers)

        if resp.status == 304, let cached {
            return cached.response      // server confirmed unchanged → serve cache (no re-download)
        }
        if resp.status == 200, let etag = resp.etag {
            await store.set(url: url, etag: etag, response: resp)   // fresh + revalidatable → cache it
        }
        return resp
    }

    public func post(_ url: String, body: Data, headers: [String: String]) async throws -> HTTPResponse {
        try await inner.post(url, body: body, headers: headers)     // POST is never cached
    }
}
