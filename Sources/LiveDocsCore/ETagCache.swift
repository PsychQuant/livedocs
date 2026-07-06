import Foundation

/// Thread-safe per-process store of `ETag → last 200 response` keyed by URL,
/// with **opt-in disk persistence** (#58) so the revalidation half of the warm win
/// survives MCP server restarts. Only entries with a body ≤ `maxPersistEntryBytes`
/// (default 1 MB — sized to include registry JSONs like pypi's ~450 KB fastapi
/// payload while excluding multi-MB `llms-full` dumps whose write cost would
/// outweigh the value; measured in #58's acceptance run). The
/// connection-setup share of a warm win is NOT recoverable by any cache — see
/// evals/look-up/perf_profile.md.
///
/// Boundary note: this is a LOCAL cache on the user's machine, inside the
/// docs/positioning.md anti-positioning line — the forbidden thing is a
/// shared/central content cache, not local persistence. Semantics are unchanged:
/// **always revalidate** — the persisted body is only served after the origin
/// answers 304. That is a FRESHNESS guarantee, not a tamper barrier (#58 verify):
/// an attacker who can write this file could plant a current etag + a forged
/// body, but local write access as the user already implies full compromise
/// (patching the binary is easier) — the file adds no meaningful surface. Only
/// already-validated 200 responses ever enter the store.
///
/// **Bounded**: without eviction a long session that fetched many docs would keep
/// every full body (a multi-MB `llms-full.txt` each) for the process lifetime. The
/// store enforces a total-byte budget and an entry cap, evicting least-recently-used
/// entries, and refuses to cache a single body larger than `maxEntryBytes`.
public actor ETagCacheStore {
    public struct Entry: Sendable {
        public let etag: String
        public let response: HTTPResponse
    }

    private var map: [String: Entry] = [:]
    /// URLs in least-recently-used → most-recently-used order.
    private var lru: [String] = []
    private var totalBytes: Int = 0
    private var loaded = false

    private let maxTotalBytes: Int
    private let maxEntries: Int
    private let maxEntryBytes: Int
    private let maxPersistEntryBytes: Int
    /// nil (the default) = in-memory only, byte-for-byte the pre-#58 behavior.
    private let persistURL: URL?

    public init(maxTotalBytes: Int = 50_000_000, maxEntries: Int = 256, maxEntryBytes: Int = 5_000_000,
                persistURL: URL? = nil, maxPersistEntryBytes: Int = 1_048_576) {
        self.maxTotalBytes = maxTotalBytes
        self.maxEntries = maxEntries
        self.maxEntryBytes = maxEntryBytes
        self.persistURL = persistURL
        self.maxPersistEntryBytes = maxPersistEntryBytes
    }

    func entry(for url: String) -> Entry? {
        loadIfNeeded()
        guard let e = map[url] else { return nil }
        touch(url)
        return e
    }

    func set(url: String, etag: String, response: HTTPResponse) {
        loadIfNeeded()
        let size = response.body.count
        // A body too large to be worth caching is served through but not stored —
        // one giant doc must not evict the whole working set or blow the budget.
        if size > maxEntryBytes { return }
        if let old = map[url] { totalBytes -= old.response.body.count }
        map[url] = Entry(etag: etag, response: response)
        totalBytes += size
        touch(url)
        evictIfNeeded()
        // Rewrite the disk file only when THIS mutation can change the persisted
        // subset — a burst of over-cap bodies costs zero disk I/O (#57/#58 verify:
        // write-amplification advisory). Trade-off accepted: an eviction caused by
        // an over-cap body can leave already-evicted entries on disk until the next
        // persistable write; on load they are just cache entries again (bounds
        // re-applied, freshness still gated by revalidation) — harmless for a cache.
        if size <= maxPersistEntryBytes { saveIfPersistent() }
    }

    // ── disk persistence (#58) ─────────────────────────────────────────────────

    /// On-disk representation. Data encodes as base64 under Codable; a `version`
    /// field lets a future format change invalidate old files cleanly.
    private struct DiskFile: Codable {
        var version: Int
        var entries: [DiskEntry]
    }
    private struct DiskEntry: Codable {
        var url: String
        var etag: String
        var status: Int
        var contentType: String?
        var body: Data
        var responseEtag: String?
    }

    /// Lazy one-shot load. Corrupt / unreadable / wrong-version files start empty —
    /// a cache must never crash its owner. Loaded entries pass through the normal
    /// bounds (touch + evict) so a hand-grown file can't blow the budget.
    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let url = persistURL,
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(DiskFile.self, from: data),
              file.version == 1
        else { return }
        for e in file.entries {
            let resp = HTTPResponse(status: e.status, contentType: e.contentType,
                                    body: e.body, etag: e.responseEtag)
            let size = resp.body.count
            if size > maxEntryBytes { continue }
            map[e.url] = Entry(etag: e.etag, response: resp)
            totalBytes += size
            touch(e.url)
        }
        evictIfNeeded()
    }

    /// Best-effort write-through of the small-body subset (≤ maxPersistEntryBytes).
    /// Atomic write + owner-only permissions; failures are silent — persistence is
    /// an optimization, never a correctness dependency.
    private func saveIfPersistent() {
        guard let url = persistURL else { return }
        let entries: [DiskEntry] = lru.compactMap { key in
            guard let e = map[key], e.response.body.count <= maxPersistEntryBytes else { return nil }
            return DiskEntry(url: key, etag: e.etag, status: e.response.status,
                             contentType: e.response.contentType,
                             body: e.response.body, responseEtag: e.response.etag)
        }
        guard let data = try? JSONEncoder().encode(DiskFile(version: 1, entries: entries)) else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Create the temp file WITH 0600 and rename(2) it into place — permissions
        // travel with the inode, so there is never a world-readable window (#58
        // verify: the old write-then-chmod left a brief 0644 gap). rename is atomic
        // and replaces the destination (including a pre-planted symlink at the
        // final path — it is replaced, never written through).
        let tmpPath = url.path + ".tmp"
        guard FileManager.default.createFile(atPath: tmpPath, contents: data,
                                             attributes: [.posixPermissions: 0o600]) else { return }
        if rename(tmpPath, url.path) != 0 {
            try? FileManager.default.removeItem(atPath: tmpPath)   // best-effort cleanup
        }
    }

    /// Move a URL to the most-recently-used end of the order.
    private func touch(_ url: String) {
        if let i = lru.firstIndex(of: url) { lru.remove(at: i) }
        lru.append(url)
    }

    /// Drop least-recently-used entries until within both the byte budget and the
    /// entry cap. Always keeps at least the most-recent entry.
    private func evictIfNeeded() {
        while (totalBytes > maxTotalBytes || map.count > maxEntries), lru.count > 1 {
            let victim = lru.removeFirst()
            if let e = map.removeValue(forKey: victim) { totalBytes -= e.response.body.count }
        }
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
