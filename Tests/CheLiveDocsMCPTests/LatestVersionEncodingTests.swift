import XCTest
@testable import CheLiveDocsMCP
@testable import LiveDocsCore

/// Boundary tests for the `latest_version` tool response (issue #36 verify).
/// The engine-level pin logic was already covered in LiveDocsCoreTests, but the
/// CRITICAL bug lived at the SERVER boundary (`encodeLatestVersion`): it decided
/// honored-vs-not by string equality, which (a) misread a Go pin's `v` prefix and
/// (b) never emitted pin_honored:false. These drive that exact seam.
private struct FakeHTTP: HTTPClient {
    let routes: [String: HTTPResponse]
    func get(_ url: String, headers: [String: String]) async throws -> HTTPResponse {
        routes[url] ?? HTTPResponse(status: 404, contentType: "text/html", body: Data("nf".utf8))
    }
    func post(_ url: String, body: Data, headers: [String: String]) async throws -> HTTPResponse {
        routes[url] ?? HTTPResponse(status: 404, contentType: "text/html", body: Data("nf".utf8))
    }
}

final class LatestVersionEncodingTests: XCTestCase {

    private func server(_ routes: [String: HTTPResponse] = [:]) -> CheLiveDocsMCPServer {
        CheLiveDocsMCPServer(engine: DiscoveryEngine(http: FakeHTTP(routes: routes)))
    }

    /// Parse the tool's JSON (pretty-printed) into a dictionary — assert on values,
    /// not on brittle substrings of whitespace-formatted output.
    private func parse(_ json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? [:]
    }

    // MARK: - pin_honored surfacing (the machine-readable signal)

    func testHonoredPinEmitsPinHonoredTrueNoNote() {
        let res = RegistryResolution(version: "1.0.100", repository: "https://github.com/serde-rs/serde", pinHonored: true)
        let obj = parse(server().encodeLatestVersion(res, library: "serde", pin: "1.0.100", eco: .crates))
        XCTAssertEqual(obj["pin_honored"] as? Bool, true)
        XCTAssertEqual(obj["version"] as? String, "1.0.100")
        XCTAssertNil(obj["note"], "a honored pin must not carry a not-applied note")
    }

    func testNotFoundVersionEmitsPinHonoredFalseAndNote() {
        // crates pin that wasn't found → engine returns latest + pinHonored=false.
        let res = RegistryResolution(version: "1.0.228", pinHonored: false)
        let obj = parse(server().encodeLatestVersion(res, library: "serde", pin: "9.9.9", eco: .crates))
        XCTAssertEqual(obj["pin_honored"] as? Bool, false)
        XCTAssertEqual(obj["version"] as? String, "1.0.228")
        let note = obj["note"] as? String ?? ""
        XCTAssertTrue(note.contains("not confirmed as an exact version"), note)
        XCTAssertFalse(note.contains("only npm/pypi"), "the stale 'only npm/pypi honor a pin' claim must be gone")
        XCTAssertFalse(note.contains("is the latest"), "a pin-supporting ecosystem false must not over-claim 'version is latest' (may be a dist-tag)")
    }

    func testLatestOnlyEcosystemEmitsPinHonoredFalseWithLatestOnlyNote() {
        let res = RegistryResolution(version: "3.5.13", pinHonored: false)
        let obj = parse(server().encodeLatestVersion(res, library: "vue", pin: "3.0.0", eco: .jsr))
        XCTAssertEqual(obj["pin_honored"] as? Bool, false)
        XCTAssertTrue((obj["note"] as? String ?? "").contains("latest-only"), obj["note"] as? String ?? "nil")
    }

    func testNoPinOmitsPinHonored() {
        let res = RegistryResolution(version: "1.0.228")   // pinHonored nil
        let obj = parse(server().encodeLatestVersion(res, library: "serde", pin: nil, eco: .crates))
        XCTAssertNil(obj["pin_honored"], "no pin requested → no pin_honored key")
    }

    func testNilResolutionWithPinReportsNotFound() {
        let obj = parse(server().encodeLatestVersion(nil, library: "nope", pin: "1.0.0", eco: .crates))
        XCTAssertTrue(obj["version"] is NSNull)
        XCTAssertEqual(obj["requested"] as? String, "1.0.0")
        // A requested pin ALWAYS gets a machine-readable signal, even when nothing
        // resolved — absent pin_honored would read as "no pin asked" (round-3).
        XCTAssertEqual(obj["pin_honored"] as? Bool, false)
    }

    func testNilResolutionNoPinOmitsPinHonored() {
        let obj = parse(server().encodeLatestVersion(nil, library: "nope", pin: nil, eco: .crates))
        XCTAssertNil(obj["pin_honored"], "no pin asked → no pin_honored even in the not-found path")
    }

    // MARK: - CRITICAL: Go v-prefixed confirmed pin must NOT read as "not applied"

    func testGoConfirmedPinEndToEndReportsHonored() async {
        let http: [String: HTTPResponse] = [
            "https://proxy.golang.org/github.com/gin-gonic/gin/@latest":
                HTTPResponse(status: 200, contentType: "application/json", body: Data(#"{"Version":"v1.12.0"}"#.utf8)),
            "https://proxy.golang.org/github.com/gin-gonic/gin/@v/v1.9.1.info":
                HTTPResponse(status: 200, contentType: "application/json", body: Data(#"{"Version":"v1.9.1"}"#.utf8)),
        ]
        let srv = server(http)
        let res = await DiscoveryEngine(http: FakeHTTP(routes: http))
            .latestVersion(library: "github.com/gin-gonic/gin", ecosystem: .go, version: "1.9.1")
        let obj = parse(srv.encodeLatestVersion(res, library: "github.com/gin-gonic/gin", pin: "1.9.1", eco: .go))
        XCTAssertEqual(obj["pin_honored"] as? Bool, true, "confirmed Go pin (v-prefix) was misread as not-applied — the CRITICAL regression")
        XCTAssertEqual(obj["version"] as? String, "v1.9.1")
        XCTAssertNil(obj["note"])
    }

    // MARK: - v-prefixed input must build a valid confirm URL (no double-v 404)

    func testGoVPrefixedInputStillHonored() async {
        // version:"v1.9.1" (canonical Go spelling) must not become …/@v/vv1.9.1.info.
        let http: [String: HTTPResponse] = [
            "https://proxy.golang.org/github.com/gin-gonic/gin/@latest":
                HTTPResponse(status: 200, contentType: "application/json", body: Data(#"{"Version":"v1.12.0"}"#.utf8)),
            "https://proxy.golang.org/github.com/gin-gonic/gin/@v/v1.9.1.info":
                HTTPResponse(status: 200, contentType: "application/json", body: Data(#"{"Version":"v1.9.1"}"#.utf8)),
        ]
        let res = await DiscoveryEngine(http: FakeHTTP(routes: http))
            .latestVersion(library: "github.com/gin-gonic/gin", ecosystem: .go, version: "v1.9.1")
        XCTAssertEqual(res?.pinHonored, true)
        XCTAssertEqual(res?.version, "v1.9.1")
    }

    func testCratesVPrefixedInputStillHonored() async {
        let http: [String: HTTPResponse] = [
            "https://crates.io/api/v1/crates/serde":
                HTTPResponse(status: 200, contentType: "application/json",
                             body: Data(#"{"crate":{"max_stable_version":"1.0.228"}}"#.utf8)),
            "https://crates.io/api/v1/crates/serde/1.0.100":
                HTTPResponse(status: 200, contentType: "application/json",
                             body: Data(#"{"version":{"num":"1.0.100"}}"#.utf8)),
        ]
        let res = await DiscoveryEngine(http: FakeHTTP(routes: http))
            .latestVersion(library: "serde", ecosystem: .crates, version: "v1.0.100")
        XCTAssertEqual(res?.pinHonored, true)
        XCTAssertEqual(res?.version, "1.0.100")
    }

    // MARK: - npm/pypi not-found pin now falls back to latest + pinHonored=false

    func testNpmNotFoundPinFallsBackToLatestFalse() async {
        let http: [String: HTTPResponse] = [
            // no /react/99.0.0 route → per-version 404
            "https://registry.npmjs.org/react/latest":
                HTTPResponse(status: 200, contentType: "application/json", body: Data(#"{"version":"19.0.0"}"#.utf8)),
        ]
        let res = await DiscoveryEngine(http: FakeHTTP(routes: http))
            .latestVersion(library: "react", ecosystem: .npm, version: "99.0.0")
        XCTAssertEqual(res?.version, "19.0.0")
        XCTAssertEqual(res?.pinHonored, false)
    }

    func testNpmDistTagIsNotAFakePin() async {
        // /react/beta 200s but resolves to a MOVING concrete version — reporting
        // pin_honored:true would fake an immutable pin (issue #36 round-2 / Codex).
        let http: [String: HTTPResponse] = [
            "https://registry.npmjs.org/react/beta":
                HTTPResponse(status: 200, contentType: "application/json", body: Data(#"{"version":"19.2.0-beta.1"}"#.utf8)),
        ]
        let res = await DiscoveryEngine(http: FakeHTTP(routes: http))
            .latestVersion(library: "react", ecosystem: .npm, version: "beta")
        XCTAssertEqual(res?.version, "19.2.0-beta.1")   // the resolved tag, honestly
        XCTAssertEqual(res?.pinHonored, false, "a dist-tag is not a confirmed immutable pin")
    }

    func testNpmExactPinConfirmed() async {
        let http: [String: HTTPResponse] = [
            "https://registry.npmjs.org/react/18.3.1":
                HTTPResponse(status: 200, contentType: "application/json", body: Data(#"{"version":"18.3.1"}"#.utf8)),
        ]
        let res = await DiscoveryEngine(http: FakeHTTP(routes: http))
            .latestVersion(library: "react", ecosystem: .npm, version: "18.3.1")
        XCTAssertEqual(res?.version, "18.3.1")
        XCTAssertEqual(res?.pinHonored, true)
    }

    // MARK: - RubyGems end-to-end pin (coverage parity with crates/go)

    func testRubyGemsPinHonoredEndToEnd() async {
        let http: [String: HTTPResponse] = [
            "https://rubygems.org/api/v1/gems/rails.json":
                HTTPResponse(status: 200, contentType: "application/json",
                             body: Data(#"{"name":"rails","version":"8.1.3","source_code_uri":"https://github.com/rails/rails"}"#.utf8)),
            "https://rubygems.org/api/v2/rubygems/rails/versions/7.0.0.json":
                HTTPResponse(status: 200, contentType: "application/json",
                             body: Data(#"{"name":"rails","number":"7.0.0"}"#.utf8)),
        ]
        let res = await DiscoveryEngine(http: FakeHTTP(routes: http))
            .latestVersion(library: "rails", ecosystem: .rubygems, version: "7.0.0")
        XCTAssertEqual(res?.version, "7.0.0")
        XCTAssertEqual(res?.pinHonored, true)
        XCTAssertEqual(res?.repository, "https://github.com/rails/rails")  // repo from latest-level
    }

    func testRubyGemsPinNotFoundFalse() async {
        let http: [String: HTTPResponse] = [
            "https://rubygems.org/api/v1/gems/rails.json":
                HTTPResponse(status: 200, contentType: "application/json",
                             body: Data(#"{"name":"rails","version":"8.1.3"}"#.utf8)),
            // no v2 route for 0.0.1 → confirm 404
        ]
        let res = await DiscoveryEngine(http: FakeHTTP(routes: http))
            .latestVersion(library: "rails", ecosystem: .rubygems, version: "0.0.1")
        XCTAssertEqual(res?.version, "8.1.3")
        XCTAssertEqual(res?.pinHonored, false)
    }
}
