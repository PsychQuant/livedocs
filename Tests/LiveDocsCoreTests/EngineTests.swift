import XCTest
@testable import LiveDocsCore

/// A routing fake: exact-URL → canned response, default 404 text/html (the
/// real-world soft-404 shape). No network, fully deterministic.
private struct FakeHTTP: HTTPClient {
    let routes: [String: HTTPResponse]
    func get(_ url: String, headers: [String: String]) async throws -> HTTPResponse {
        routes[url] ?? HTTPResponse(status: 404, contentType: "text/html", body: Data("nf".utf8))
    }
    func post(_ url: String, body: Data, headers: [String: String]) async throws -> HTTPResponse {
        routes[url] ?? HTTPResponse(status: 404, contentType: "text/html", body: Data("nf".utf8))
    }
}

private func textPlain(_ n: Int) -> HTTPResponse {
    HTTPResponse(status: 200, contentType: "text/plain; charset=utf-8",
                 body: Data(String(repeating: "x", count: n).utf8))
}

final class EngineTests: XCTestCase {

    func testRegistryOnlyFallbackWhenNoLlms() async {
        // fastapi: real-world has no llms.txt → registry is the whole answer.
        let pypi = """
        {"info":{"version":"0.138.2","home_page":"https://github.com/fastapi/fastapi",
          "project_urls":{"Changelog":"https://fastapi.tiangolo.com/release-notes/",
            "Documentation":"https://fastapi.tiangolo.com/",
            "Repository":"https://github.com/fastapi/fastapi"}}}
        """
        let http = FakeHTTP(routes: [
            "https://pypi.org/pypi/fastapi/json":
                HTTPResponse(status: 200, contentType: "application/json", body: Data(pypi.utf8))
        ])
        let engine = DiscoveryEngine(http: http)
        let sources = await engine.resolveSources(.init(library: "fastapi", ecosystem: .pypi))

        // repo (high) ranks before changelog (medium); both carry the version.
        XCTAssertEqual(sources.first?.kind, .repoReadme)
        XCTAssertEqual(sources.first?.version, "0.138.2")
        XCTAssertTrue(sources.contains { $0.kind == .registryDocs && $0.url.contains("release-notes") })
        XCTAssertFalse(sources.contains { $0.kind == .llmsFull || $0.kind == .llmsIndex })
    }

    func testLlmsIndexUpgradesToFull() async {
        // hono ships a small index llms.txt AND a full dump sibling.
        let http = FakeHTTP(routes: [
            "https://hono.dev/llms.txt": textPlain(5_000),        // index-sized
            "https://hono.dev/llms-full.txt": textPlain(40_000),  // full dump
        ])
        let engine = DiscoveryEngine(http: http)
        let sources = await engine.resolveSources(.init(docsURL: "https://hono.dev"))

        XCTAssertEqual(sources.first?.kind, .llmsFull)            // high fidelity wins
        XCTAssertTrue(sources.contains { $0.kind == .llmsIndex })
        XCTAssertEqual(sources.first?.url, "https://hono.dev/llms-full.txt")
    }

    func testGoModulePathIsRepoWhenProxyOmitsOrigin() async {
        // proxy returns a version but NO Origin → the module path itself is the repo.
        let http = FakeHTTP(routes: [
            "https://proxy.golang.org/github.com/gin-gonic/gin/@latest":
                HTTPResponse(status: 200, contentType: "application/json",
                             body: Data(#"{"Version":"v1.12.0"}"#.utf8))
        ])
        let engine = DiscoveryEngine(http: http)
        let res = await engine.latestVersion(library: "github.com/gin-gonic/gin", ecosystem: .go)
        XCTAssertEqual(res?.version, "v1.12.0")
        XCTAssertEqual(res?.repository, "https://github.com/gin-gonic/gin")  // derived, not discarded
    }

    func testPinnedRequestLabelsRepoAsNotPinned() async {
        // npm react@18.3.1 resolves the version, but the repo URL is HEAD → must be labeled.
        let http = FakeHTTP(routes: [
            "https://registry.npmjs.org/react/18.3.1":
                HTTPResponse(status: 200, contentType: "application/json",
                             body: Data(#"{"version":"18.3.1","repository":{"url":"git+https://github.com/facebook/react.git"}}"#.utf8))
        ])
        let engine = DiscoveryEngine(http: http)
        let sources = await engine.resolveSources(.init(library: "react", ecosystem: .npm, version: "18.3.1"))
        let repo = sources.first { $0.kind == .repoReadme }
        XCTAssertEqual(repo?.version, "18.3.1")
        XCTAssertTrue(repo?.title?.contains("NOT pinned") ?? false, "repo source must be labeled not-pinned; got \(String(describing: repo?.title))")
    }

    func testNoSignalsYieldsEmpty() async {
        let engine = DiscoveryEngine(http: FakeHTTP(routes: [:]))
        let sources = await engine.resolveSources(.init(library: "does-not-exist", ecosystem: .npm))
        XCTAssertTrue(sources.isEmpty)   // → caller falls back to context7/web, labeled low-fidelity
    }

    // MARK: - Non-npm/pypi version pins (issue #36)

    private static let cratesLatest = #"{"crate":{"name":"serde","max_stable_version":"1.0.228","repository":"https://github.com/serde-rs/serde","documentation":"https://docs.rs/serde"}}"#

    func testCratesPinHonoredWhenVersionConfirmed() async {
        // A pinned crates request confirms the version at the per-version endpoint
        // and reports THAT version with pin_honored = true.
        let http = FakeHTTP(routes: [
            "https://crates.io/api/v1/crates/serde":
                HTTPResponse(status: 200, contentType: "application/json", body: Data(Self.cratesLatest.utf8)),
            "https://crates.io/api/v1/crates/serde/1.0.100":
                HTTPResponse(status: 200, contentType: "application/json",
                             body: Data(#"{"version":{"num":"1.0.100"}}"#.utf8)),
        ])
        let engine = DiscoveryEngine(http: http)
        let res = await engine.latestVersion(library: "serde", ecosystem: .crates, version: "1.0.100")
        XCTAssertEqual(res?.version, "1.0.100")            // the confirmed pin, not latest
        XCTAssertEqual(res?.pinHonored, true)
        XCTAssertEqual(res?.repository, "https://github.com/serde-rs/serde")  // repo still from latest-level
    }

    func testCratesPinNotHonoredWhenVersionMissing() async {
        // The pinned version 404s at the per-version endpoint → fall back to latest,
        // pin_honored = false (never fake a pin we couldn't confirm).
        let http = FakeHTTP(routes: [
            "https://crates.io/api/v1/crates/serde":
                HTTPResponse(status: 200, contentType: "application/json", body: Data(Self.cratesLatest.utf8)),
            // no route for /serde/9.9.9 → 404
        ])
        let engine = DiscoveryEngine(http: http)
        let res = await engine.latestVersion(library: "serde", ecosystem: .crates, version: "9.9.9")
        XCTAssertEqual(res?.version, "1.0.228")            // latest, honestly
        XCTAssertEqual(res?.pinHonored, false)
    }

    func testNoPinLeavesPinHonoredNil() async {
        // Without a pin, pin_honored is absent (nil) — it's a pin-request-only fact.
        let http = FakeHTTP(routes: [
            "https://crates.io/api/v1/crates/serde":
                HTTPResponse(status: 200, contentType: "application/json", body: Data(Self.cratesLatest.utf8)),
        ])
        let engine = DiscoveryEngine(http: http)
        let res = await engine.latestVersion(library: "serde", ecosystem: .crates)
        XCTAssertEqual(res?.version, "1.0.228")
        XCTAssertNil(res?.pinHonored)
    }

    func testGoPinHonoredViaVersionInfo() async {
        // Go confirms a pin at /<mod>/@v/vX.Y.Z.info; keeps the v-prefix.
        let http = FakeHTTP(routes: [
            "https://proxy.golang.org/github.com/gin-gonic/gin/@latest":
                HTTPResponse(status: 200, contentType: "application/json",
                             body: Data(#"{"Version":"v1.12.0"}"#.utf8)),
            "https://proxy.golang.org/github.com/gin-gonic/gin/@v/v1.9.1.info":
                HTTPResponse(status: 200, contentType: "application/json",
                             body: Data(#"{"Version":"v1.9.1"}"#.utf8)),
        ])
        let engine = DiscoveryEngine(http: http)
        let res = await engine.latestVersion(library: "github.com/gin-gonic/gin", ecosystem: .go, version: "1.9.1")
        XCTAssertEqual(res?.version, "v1.9.1")
        XCTAssertEqual(res?.pinHonored, true)
    }

    func testLatestOnlyEcosystemSetsPinHonoredFalseAtEngine() async {
        // Drive the actual `!eco.supportsVersionPin → pinHonored=false` engine line
        // (CRAN is latest-only), not just the server-encoding shortcut (round-3).
        let http = FakeHTTP(routes: [
            "https://crandb.r-pkg.org/dplyr":
                HTTPResponse(status: 200, contentType: "application/json",
                             body: Data(#"{"Version":"1.1.4","URL":"https://github.com/tidyverse/dplyr"}"#.utf8)),
        ])
        let res = await DiscoveryEngine(http: http).latestVersion(library: "dplyr", ecosystem: .cran, version: "1.0.0")
        XCTAssertEqual(res?.version, "1.1.4")
        XCTAssertEqual(res?.pinHonored, false)   // requested a pin on a latest-only ecosystem
    }

    func testAutoDetectFallsThroughToPyPIOnNpmPinMiss() async {
        // A name that exists on npm (but NOT at the pinned version) AND on PyPI at
        // the exact pin. Auto-detect must not short-circuit to npm's latest — it
        // must try PyPI's exact pin (round-3: pinned-miss on a non-last ecosystem
        // returns nil to preserve fall-through).
        let http = FakeHTTP(routes: [
            // npm has the package but not 2.0.0 → per-version 404, latest present
            "https://registry.npmjs.org/foo/latest":
                HTTPResponse(status: 200, contentType: "application/json", body: Data(#"{"version":"1.0.0"}"#.utf8)),
            // PyPI has the exact pinned version
            "https://pypi.org/pypi/foo/2.0.0/json":
                HTTPResponse(status: 200, contentType: "application/json",
                             body: Data(#"{"info":{"version":"2.0.0","project_urls":{"Repository":"https://github.com/py/foo"}}}"#.utf8)),
        ])
        // ecosystem: nil → auto-detect [.npm, .pypi]
        let res = await DiscoveryEngine(http: http).latestVersion(library: "foo", ecosystem: nil, version: "2.0.0")
        XCTAssertEqual(res?.version, "2.0.0", "must resolve PyPI's exact pin, not npm's latest 1.0.0")
        XCTAssertEqual(res?.pinHonored, true)
        XCTAssertEqual(res?.repository, "https://github.com/py/foo")
    }

    func testAutoDetectPinMissAnywhereStillReturnsNpmLatest() async {
        // Pin exists on NEITHER registry, but npm has the package. Pass 1 (exact
        // pin) misses everywhere; pass 2 must still return npm's latest+false so we
        // don't lose the helpful current-version answer (round-3 two-pass).
        let http = FakeHTTP(routes: [
            "https://registry.npmjs.org/leftpad/latest":
                HTTPResponse(status: 200, contentType: "application/json", body: Data(#"{"version":"1.3.0"}"#.utf8)),
            // no /leftpad/9.9.9, no PyPI leftpad at all
        ])
        let res = await DiscoveryEngine(http: http).latestVersion(library: "leftpad", ecosystem: nil, version: "9.9.9")
        XCTAssertEqual(res?.version, "1.3.0", "must fall back to npm latest, not return not-found")
        XCTAssertEqual(res?.pinHonored, false)
    }

    // ── #57: concurrent llms.txt candidate probing ────────────────────────────

    func testParallelProbeSelectsByPreferenceOrderNotCompletionOrder() async {
        // BOTH root llms.txt and /docs/llms.txt hit. The winner must be the root one
        // (lower candidate index) — selection is by PREFERENCE order, never by which
        // response happens to land first (#57 determinism contract).
        let http = RecordingHTTP(routes: [
            "https://ex.dev/llms.txt": textPlain(5_000),
            "https://ex.dev/docs/llms.txt": textPlain(5_000),
        ])
        let sources = await DiscoveryEngine(http: http).resolveSources(.init(docsURL: "https://ex.dev"))
        XCTAssertEqual(sources.first?.url, "https://ex.dev/llms.txt")
        XCTAssertEqual(sources.first?.kind, .llmsIndex)
    }

    func testParallelProbeFiresAllCandidatesOfProbedHost() async {
        // The parallel design's documented politeness trade (#57): ALL candidates of
        // the ONE probed host are fired concurrently (sequential early-exit fired only
        // the first). Bounded to that host's candidate set (4 here) — pin it.
        let http = RecordingHTTP(routes: [
            "https://ex.dev/llms.txt": textPlain(5_000),   // first candidate already hits
        ])
        _ = await DiscoveryEngine(http: http).resolveSources(.init(docsURL: "https://ex.dev"))
        let probed = await http.requested.filter { $0.contains("llms") }
        XCTAssertEqual(Set(probed), [
            "https://ex.dev/llms.txt", "https://ex.dev/llms-full.txt",
            "https://ex.dev/docs/llms.txt", "https://ex.dev/docs/llms-full.txt",
        ], "all candidates of the probed host fire concurrently")
    }

    func testFullSiblingAbsorbedFromCollectedResultsNoReprobe() async {
        // The llms-full "upgrade" must be satisfied from the already-collected
        // concurrent results — the sibling is IN the candidate set, so it is fetched
        // exactly once, never re-probed (#57).
        let http = RecordingHTTP(routes: [
            "https://hono.dev/llms.txt": textPlain(5_000),        // index-sized
            "https://hono.dev/llms-full.txt": textPlain(40_000),  // full dump
        ])
        let sources = await DiscoveryEngine(http: http).resolveSources(.init(docsURL: "https://hono.dev"))
        XCTAssertEqual(sources.first?.kind, .llmsFull)            // upgrade semantics preserved
        XCTAssertTrue(sources.contains { $0.kind == .llmsIndex })
        let fullFetches = await http.requested.filter { $0 == "https://hono.dev/llms-full.txt" }.count
        XCTAssertEqual(fullFetches, 1, "sibling absorbed from collected results, not re-probed")
    }
}

/// Concurrency-safe recording fake: an actor, so concurrent TaskGroup probes (#57)
/// can log requests without data races.
private actor RequestLog {
    var urls: [String] = []
    func add(_ u: String) { urls.append(u) }
}

private struct RecordingHTTP: HTTPClient {
    let routes: [String: HTTPResponse]
    let log = RequestLog()
    var requested: [String] { get async { await log.urls } }
    func get(_ url: String, headers: [String: String]) async throws -> HTTPResponse {
        await log.add(url)
        return routes[url] ?? HTTPResponse(status: 404, contentType: "text/html", body: Data("nf".utf8))
    }
    func post(_ url: String, body: Data, headers: [String: String]) async throws -> HTTPResponse {
        await log.add(url)
        return routes[url] ?? HTTPResponse(status: 404, contentType: "text/html", body: Data("nf".utf8))
    }
}
