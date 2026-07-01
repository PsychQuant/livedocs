import XCTest
@testable import LiveDocsCore

/// The ETag cache's bounded-growth behavior (LRU + byte budget + per-entry cap).
/// The revalidation semantics are covered by ETagCacheTests.
final class ETagCacheLRUTests: XCTestCase {

    private func resp(_ n: Int) -> HTTPResponse {
        HTTPResponse(status: 200, contentType: "text/plain", body: Data(count: n), etag: "e\(n)")
    }

    func testEvictsLeastRecentlyUsedOverByteBudget() async {
        let store = ETagCacheStore(maxTotalBytes: 100, maxEntries: 100, maxEntryBytes: 100)
        await store.set(url: "a", etag: "ea", response: resp(60))
        await store.set(url: "b", etag: "eb", response: resp(60))   // total 120 > 100 → evict LRU (a)
        let a = await store.entry(for: "a")
        let b = await store.entry(for: "b")
        XCTAssertNil(a, "a was least-recently-used and should be evicted")
        XCTAssertNotNil(b)
    }

    func testTouchOnReadUpdatesRecency() async {
        let store = ETagCacheStore(maxTotalBytes: 100, maxEntries: 100, maxEntryBytes: 100)
        await store.set(url: "a", etag: "ea", response: resp(40))
        await store.set(url: "b", etag: "eb", response: resp(40))
        _ = await store.entry(for: "a")                              // a is now most-recent
        await store.set(url: "c", etag: "ec", response: resp(40))    // total 120 → evict LRU (b)
        let a = await store.entry(for: "a")
        let b = await store.entry(for: "b")
        let c = await store.entry(for: "c")
        XCTAssertNotNil(a)
        XCTAssertNil(b)
        XCTAssertNotNil(c)
    }

    func testRefusesOversizedEntry() async {
        let store = ETagCacheStore(maxTotalBytes: 1000, maxEntries: 100, maxEntryBytes: 50)
        await store.set(url: "big", etag: "e", response: resp(200))
        let big = await store.entry(for: "big")
        XCTAssertNil(big, "a body over maxEntryBytes must not be stored")
    }

    func testEntryCapEvicts() async {
        let store = ETagCacheStore(maxTotalBytes: 1_000_000, maxEntries: 2, maxEntryBytes: 1000)
        await store.set(url: "a", etag: "ea", response: resp(10))
        await store.set(url: "b", etag: "eb", response: resp(10))
        await store.set(url: "c", etag: "ec", response: resp(10))   // over entry cap → evict a
        let a = await store.entry(for: "a")
        let b = await store.entry(for: "b")
        let c = await store.entry(for: "c")
        XCTAssertNil(a)
        XCTAssertNotNil(b)
        XCTAssertNotNil(c)
    }
}
