import XCTest
@testable import CheLiveDocsMCP
@testable import LiveDocsCore

/// Filesystem-facing tests for the MCP-side runtime resolver: symlink refusal,
/// the universal-pin-layer generic fallback for uncovered languages, canonical
/// `mise.toml` support, and PATH-first executable resolution. These exercise the
/// exact defects the review flagged (#7, #8, #10, #15).
final class RuntimeIntrospectTests: XCTestCase {

    private var dir: String!

    override func setUpWithError() throws {
        dir = NSTemporaryDirectory() + "livedocs-rt-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: dir)
    }

    private func write(_ name: String, _ contents: String) throws {
        try contents.write(toFile: (dir as NSString).appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    // MARK: - #8 symlink refusal

    func testRefusesSymlinkVersionFile() throws {
        // A malicious `.python-version` symlinked at a "secret" file must not be
        // read and echoed as the effective version.
        let secret = (dir as NSString).appendingPathComponent("secret")
        try "SUPER-SECRET-KEY".write(toFile: secret, atomically: true, encoding: .utf8)
        let link = (dir as NSString).appendingPathComponent(".python-version")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: secret)

        let results = RuntimeIntrospect.resolve(cwd: dir, languageId: "python")
        // Whatever the toolchain probe finds, the secret content must never surface.
        for r in results {
            if case .resolved(let version, _, _, _) = r.resolution {
                XCTAssertFalse(version.contains("SECRET"), "symlinked secret leaked into effective_version")
            }
        }
    }

    // MARK: - #15 generic pin-layer fallback for uncovered languages

    func testUncoveredLanguageResolvesViaToolVersions() throws {
        try write(".tool-versions", "ruby 3.2.2\n")
        let results = RuntimeIntrospect.resolve(cwd: dir, languageId: "ruby")
        XCTAssertEqual(results.count, 1)
        guard case .resolved(let version, _, _, _) = results[0].resolution else {
            return XCTFail("ruby declared in .tool-versions should resolve")
        }
        XCTAssertEqual(version, "3.2.2")
        XCTAssertEqual(results[0].languageId, "ruby")
    }

    func testUncoveredLanguageIdiomaticFile() throws {
        try write(".ruby-version", "3.1.0\n")
        let results = RuntimeIntrospect.resolve(cwd: dir, languageId: "ruby")
        guard case .resolved(let version, _, _, _) = results[0].resolution else {
            return XCTFail(".ruby-version should resolve")
        }
        XCTAssertEqual(version, "3.1.0")
    }

    func testUnsafeLanguageIdRejected() {
        XCTAssertTrue(RuntimeIntrospect.resolve(cwd: dir, languageId: "../etc").isEmpty)
        XCTAssertTrue(RuntimeIntrospect.resolve(cwd: dir, languageId: "ruby; rm -rf").isEmpty)
    }

    // MARK: - #10 canonical mise.toml

    func testReadsCanonicalMiseToml() throws {
        try write("mise.toml", "[tools]\nruby = \"3.3.0\"\n")
        let results = RuntimeIntrospect.resolve(cwd: dir, languageId: "ruby")
        guard case .resolved(let version, _, _, _) = results[0].resolution else {
            return XCTFail("mise.toml (no dot) should be read")
        }
        XCTAssertEqual(version, "3.3.0")
    }

    // MARK: - #7 PATH-first executable resolution

    func testResolveExecutableFindsOnPath() {
        // `env` exists in a standard location on every macOS/Linux box.
        let path = ProcessRunner.resolveExecutable("env")
        XCTAssertNotNil(path)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path ?? ""))
    }

    func testResolveExecutableNilForNonsense() {
        XCTAssertNil(ProcessRunner.resolveExecutable("definitely-not-a-real-binary-xyzzy"))
    }

    // MARK: - #35 case-insensitive targets + javascript alias (end to end)

    func testResolveAcceptsUppercaseRAndPreservesRequestedId() {
        // The flagship `/livedocs:look-up R` sends target="R" verbatim. The raw
        // id must be canonicalized BEFORE the lowercase-only safety gate — the
        // pre-fix code returned [] here (PR #40 verify HIGH).
        let results = RuntimeIntrospect.resolve(cwd: dir, languageId: "R")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.languageId, "R")   // requested casing preserved
    }

    func testResolveJavascriptAliasKeepsRequestedIdAcrossCasing() {
        // Alias goes through the node adapter, but the caller-facing id stays
        // exactly as requested — returning "node" would break the spec's
        // "result keeps the requested identifier" clause.
        for spelled in ["javascript", "JavaScript"] {
            let results = RuntimeIntrospect.resolve(cwd: dir, languageId: spelled)
            XCTAssertEqual(results.count, 1, "id '\(spelled)' must not be rejected")
            XCTAssertEqual(results.first?.languageId, spelled)
        }
    }

    func testResolveJavascriptMatchesNodeWhenNodeUnresolvable() throws {
        // In an empty dir with no node version source, javascript must degrade
        // exactly as node does (notResolved), never invent a distinct runtime.
        // (If the machine has a global node on PATH both resolve identically
        // via the probe — equality is asserted either way.)
        let js = RuntimeIntrospect.resolve(cwd: dir, languageId: "javascript")[0].resolution
        let node = RuntimeIntrospect.resolve(cwd: dir, languageId: "node")[0].resolution
        switch (js, node) {
        case (.resolved(let v1, let s1, _, _), .resolved(let v2, let s2, _, _)):
            XCTAssertEqual(v1, v2)
            XCTAssertEqual(s1, s2)
        case (.notResolved, .notResolved):
            break   // equally unresolved — honest degrade
        default:
            XCTFail("javascript and node must resolve identically, got \(js) vs \(node)")
        }
    }

    func testResolveStillRejectsUnsafeIds() {
        XCTAssertTrue(RuntimeIntrospect.resolve(cwd: dir, languageId: "../evil").isEmpty)
        XCTAssertTrue(RuntimeIntrospect.resolve(cwd: dir, languageId: "py thon").isEmpty)
    }
}
