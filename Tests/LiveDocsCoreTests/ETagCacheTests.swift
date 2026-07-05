import XCTest
@testable import LiveDocsCore

private actor CallLog { private(set) var count = 0; func inc() { count += 1 } }

/// Fake inner client: returns 304 when the request's `If-None-Match` matches the
/// current etag, else a fresh 200. Records how many times it was hit (to prove the
/// cache always revalidates — it never skips the inner round-trip).
private struct FakeInner: HTTPClient {
    let currentEtag: String?
    let body: String
    let log: CallLog?
    init(etag: String?, body: String, log: CallLog? = nil) {
        self.currentEtag = etag; self.body = body; self.log = log
    }
    func get(_ url: String, headers: [String: String]) async throws -> HTTPResponse {
        await log?.inc()
        if let e = currentEtag, headers["If-None-Match"] == e {
            return HTTPResponse(status: 304, contentType: nil, body: Data(), etag: e)
        }
        return HTTPResponse(status: 200, contentType: "text/plain", body: Data(body.utf8), etag: currentEtag)
    }
    func post(_ url: String, body: Data, headers: [String: String]) async throws -> HTTPResponse {
        HTTPResponse(status: 200, contentType: "application/json", body: Data("POSTED".utf8))
    }
}

final class ETagCacheTests: XCTestCase {
    let url = "https://example.com/llms.txt"

    func testFirstGetReturns200AndCaches() async throws {
        let client = ETagCachingHTTPClient(inner: FakeInner(etag: "v1", body: "content-1"))
        let r = try await client.get(url)
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.bodyText, "content-1")
    }

    func testUnchangedServesCacheViaRevalidation() async throws {
        let log = CallLog()
        let store = ETagCacheStore()
        let client = ETagCachingHTTPClient(inner: FakeInner(etag: "v1", body: "content-1", log: log), store: store)
        _ = try await client.get(url)                    // 200 → cache
        let second = try await client.get(url)           // If-None-Match:v1 → inner 304 → serve cache
        XCTAssertEqual(second.status, 200)               // caller sees a valid 200, not a bare 304
        XCTAssertEqual(second.bodyText, "content-1")     // cached body (no re-download)
        let hits = await log.count
        XCTAssertEqual(hits, 2)                           // ALWAYS revalidates — inner hit both times
    }

    func testContentChangeUpdatesCache() async throws {
        let store = ETagCacheStore()
        _ = try await ETagCachingHTTPClient(inner: FakeInner(etag: "v1", body: "content-1"), store: store).get(url)
        // Same URL, server now has a new etag+body → If-None-Match:v1 no longer matches → 200 fresh.
        let changed = try await ETagCachingHTTPClient(inner: FakeInner(etag: "v2", body: "content-2"), store: store).get(url)
        XCTAssertEqual(changed.bodyText, "content-2")
        // And the cache updated to v2 → next call revalidates against v2.
        let after = try await ETagCachingHTTPClient(inner: FakeInner(etag: "v2", body: "content-2"), store: store).get(url)
        XCTAssertEqual(after.bodyText, "content-2")
    }

    func testNoEtagIsNotCached() async throws {
        let log = CallLog()
        let store = ETagCacheStore()
        let client = ETagCachingHTTPClient(inner: FakeInner(etag: nil, body: "no-etag", log: log), store: store)
        _ = try await client.get(url)
        let second = try await client.get(url)
        XCTAssertEqual(second.bodyText, "no-etag")       // always fresh from inner (no 304 path)
        let hits = await log.count
        XCTAssertEqual(hits, 2)
    }

    func testPostNotCached() async throws {
        let client = ETagCachingHTTPClient(inner: FakeInner(etag: "v1", body: "x"))
        let r = try await client.post(url, jsonBody: "{}")
        XCTAssertEqual(r.bodyText, "POSTED")
    }

    // ── #58: disk persistence (opt-in, small entries only) ────────────────────

    private func tmpCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("etag-test-\(UUID().uuidString)")
            .appendingPathComponent("etag-cache.json")
    }

    func testPersistedEntrySurvivesRestart() async throws {
        // Store A caches a 200; a NEW store on the same file (fresh "process") must
        // revalidate with If-None-Match and serve the persisted body on 304 — the
        // revalidation share of the warm win survives restart (#58).
        let file = tmpCacheURL()
        let a = ETagCacheStore(persistURL: file)
        _ = try await ETagCachingHTTPClient(inner: FakeInner(etag: "v1", body: "content-1"), store: a).get(url)

        let log = CallLog()
        let b = ETagCacheStore(persistURL: file)             // fresh store, same file
        let second = try await ETagCachingHTTPClient(
            inner: FakeInner(etag: "v1", body: "SHOULD-NOT-REDOWNLOAD", log: log), store: b).get(url)
        XCTAssertEqual(second.status, 200)
        XCTAssertEqual(second.bodyText, "content-1", "304 must serve the DISK-loaded body")
        let hits = await log.count
        XCTAssertEqual(hits, 1, "still exactly one revalidation round-trip — never blind-stale")
        // Owner-only from birth: the temp file is CREATED 0600 and rename(2)'d in,
        // so there is never a world-readable window (#58 verify advisory).
        let perms = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int)
        XCTAssertEqual(perms & 0o777, 0o600)
    }

    func testCorruptCacheFileStartsEmptyAndRecovers() async throws {
        // A corrupt/garbage file must NEVER crash: start empty, work normally, and
        // rewrite the file on the next cache write (#58 robustness).
        let file = tmpCacheURL()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json {{{".utf8).write(to: file)
        let store = ETagCacheStore(persistURL: file)
        let r = try await ETagCachingHTTPClient(inner: FakeInner(etag: "v1", body: "fresh"), store: store).get(url)
        XCTAssertEqual(r.bodyText, "fresh")
        let reloaded = ETagCacheStore(persistURL: file)      // file was rewritten valid
        let hit = try await ETagCachingHTTPClient(inner: FakeInner(etag: "v1", body: "X"), store: reloaded).get(url)
        XCTAssertEqual(hit.bodyText, "fresh", "rewritten file loads cleanly after corruption")
    }

    func testOversizedBodyNotPersistedAndNilURLWritesNothing() async throws {
        // Bodies over the persist cap stay in-memory only (a fresh store re-downloads);
        // and the nil-persistURL default has zero file side effects (#58 scope).
        let file = tmpCacheURL()
        let big = String(repeating: "x", count: 1_500_000)   // > 1 MB persist cap, < 5 MB memory cap
        let a = ETagCacheStore(persistURL: file)
        _ = try await ETagCachingHTTPClient(inner: FakeInner(etag: "v1", body: big), store: a).get(url)
        let b = ETagCacheStore(persistURL: file)
        let refetched = try await ETagCachingHTTPClient(inner: FakeInner(etag: "v2", body: "fresh-dl"), store: b).get(url)
        XCTAssertEqual(refetched.bodyText, "fresh-dl", "oversized body must not come from disk")

        let noFile = tmpCacheURL()
        let c = ETagCacheStore()                              // default: in-memory only
        _ = try await ETagCachingHTTPClient(inner: FakeInner(etag: "v1", body: "mem"), store: c).get(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: noFile.path))
    }
}
