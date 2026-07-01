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
}
