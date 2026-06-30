import XCTest
@testable import LiveDocsCore

final class RegistryTests: XCTestCase {

    func testParseNpmLatest() throws {
        // Shape from registry.npmjs.org/react/latest (verified 2026-06-30).
        let json = """
        {"name":"react","version":"19.2.0","homepage":"https://react.dev/",
         "repository":{"type":"git","url":"git+https://github.com/facebook/react.git"}}
        """.data(using: .utf8)!
        let r = try parseNpmLatest(json)
        XCTAssertEqual(r.version, "19.2.0")
        XCTAssertEqual(r.homepage, "https://react.dev/")
        XCTAssertEqual(r.repository, "https://github.com/facebook/react")
    }

    func testParseNpmBareStringRepository() throws {
        let json = #"{"version":"1.0.0","repository":"github:sindresorhus/got"}"#.data(using: .utf8)!
        let r = try parseNpmLatest(json)
        XCTAssertEqual(r.repository, "https://github.com/sindresorhus/got")
    }

    func testParsePyPI() throws {
        // Shape from pypi.org/pypi/fastapi/json (verified 2026-06-30).
        let json = """
        {"info":{"version":"0.138.2","home_page":"https://github.com/fastapi/fastapi",
          "project_urls":{"Changelog":"https://fastapi.tiangolo.com/release-notes/",
            "Documentation":"https://fastapi.tiangolo.com/",
            "Homepage":"https://github.com/fastapi/fastapi",
            "Repository":"https://github.com/fastapi/fastapi"}}}
        """.data(using: .utf8)!
        let r = try parsePyPI(json)
        XCTAssertEqual(r.version, "0.138.2")
        XCTAssertEqual(r.changelog, "https://fastapi.tiangolo.com/release-notes/")
        XCTAssertEqual(r.documentation, "https://fastapi.tiangolo.com/")
        XCTAssertEqual(r.repository, "https://github.com/fastapi/fastapi")
    }

    func testMalformedThrows() {
        XCTAssertThrowsError(try parseNpmLatest(Data("not json".utf8)))
        XCTAssertThrowsError(try parsePyPI(Data("{}".utf8)))  // missing "info"
    }

    func testRepoURLNormalization() {
        XCTAssertEqual(normalizeRepoURL("git+https://github.com/x/y.git"), "https://github.com/x/y")
        XCTAssertEqual(normalizeRepoURL("git+ssh://git@github.com/x/y.git"), "https://github.com/x/y")
        XCTAssertEqual(normalizeRepoURL("git@github.com:x/y.git"), "https://github.com/x/y")
        XCTAssertEqual(normalizeRepoURL("github:x/y"), "https://github.com/x/y")
        XCTAssertEqual(normalizeRepoURL("https://gitlab.com/x/y"), "https://gitlab.com/x/y")
        XCTAssertNil(normalizeRepoURL(nil))
        XCTAssertNil(normalizeRepoURL(""))
    }
}
