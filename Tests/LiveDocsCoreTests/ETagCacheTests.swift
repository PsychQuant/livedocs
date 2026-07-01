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
}
