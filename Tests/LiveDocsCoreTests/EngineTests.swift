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
}
