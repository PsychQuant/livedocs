import XCTest
@testable import LiveDocsCore

/// Tests for the pure runtime-version-introspection core: the universal pin layer,
/// per-language declaration parsers, active-toolchain output parsers, the
/// precedence engine (active toolchain authoritative), and boundary validation.
/// All pure — no filesystem or process needed (the MCP side feeds content in).
final class RuntimeIntrospectionTests: XCTestCase {

    // MARK: - Universal pin layer

    func testParseToolVersions() {
        let content = """
        # a comment
        python 3.11.4
        nodejs 20.1.0

        ruby 3.2.2
        """
        let m = parseToolVersions(content)
        XCTAssertEqual(m["python"], "3.11.4")
        XCTAssertEqual(m["nodejs"], "20.1.0")
        XCTAssertEqual(m["ruby"], "3.2.2")
        XCTAssertNil(m["go"])
    }

    func testParseMiseToml() {
        let content = """
        [tools]
        python = "3.12"
        node = "20"
        [env]
        FOO = "bar"
        """
        let m = parseMiseToml(content)
        XCTAssertEqual(m["python"], "3.12")
        XCTAssertEqual(m["node"], "20")
        XCTAssertNil(m["FOO"])   // env section is not a tool
    }

    func testParseIdiomaticVersionFile() {
        XCTAssertEqual(parseIdiomaticVersionFile("3.11.4\n"), "3.11.4")
        XCTAssertEqual(parseIdiomaticVersionFile("  v20.1.0  "), "20.1.0")  // strip leading v
        XCTAssertNil(parseIdiomaticVersionFile("\n\n"))
    }

    // MARK: - Precedence engine (the spec's example table)

    func testPrecedenceActiveToolchainOverridesConstraint() {
        // active venv 3.12.1 + requires-python >=3.9 → 3.12.1
        let cands = [
            PinCandidate(version: "3.12.1", source: "active venv python", semantics: .activeToolchain),
            PinCandidate(version: ">=3.9", source: "pyproject requires-python", semantics: .constraint),
        ]
        XCTAssertEqual(resolveEffectiveRuntime(cands, env: "venv"),
                       .resolved(version: "3.12.1", source: "active venv python", semantics: .activeToolchain, env: "venv"))
    }

    func testPrecedencePinFileWhenNoToolchain() {
        // .python-version 3.11.4, no active venv → 3.11.4
        let cands = [PinCandidate(version: "3.11.4", source: ".python-version", semantics: .exactVersion)]
        XCTAssertEqual(resolveEffectiveRuntime(cands, env: "cwd"),
                       .resolved(version: "3.11.4", source: ".python-version", semantics: .exactVersion, env: "cwd"))
    }

    func testPrecedenceSwiftLanguageModeIgnored() {
        // swift-tools-version 5.9 (language-mode) + swift --version 6.0 → 6.0
        let cands = [
            PinCandidate(version: "6.0", source: "swift --version", semantics: .activeToolchain),
            PinCandidate(version: "5.9", source: "swift-tools-version", semantics: .languageMode),
        ]
        XCTAssertEqual(resolveEffectiveRuntime(cands, env: "toolchain"),
                       .resolved(version: "6.0", source: "swift --version", semantics: .activeToolchain, env: "toolchain"))
    }

    func testPrecedenceGoDirectiveCrossCheckedByToolchain() {
        // go.mod go 1.21 (directive) + go version 1.22 → 1.22 (active authoritative)
        let cands = [
            PinCandidate(version: "1.22", source: "go version", semantics: .activeToolchain),
            PinCandidate(version: "1.21", source: "go.mod go directive", semantics: .directive),
        ]
        XCTAssertEqual(resolveEffectiveRuntime(cands, env: "toolchain"),
                       .resolved(version: "1.22", source: "go version", semantics: .activeToolchain, env: "toolchain"))
    }

    func testPrecedenceDirectiveWhenNoToolchain() {
        // only go.mod directive, no toolchain → use the directive (it's a real language version)
        let cands = [PinCandidate(version: "1.21", source: "go.mod", semantics: .directive)]
        if case .resolved(let v, _, let sem, _) = resolveEffectiveRuntime(cands, env: "cwd") {
            XCTAssertEqual(v, "1.21"); XCTAssertEqual(sem, .directive)
        } else { XCTFail("directive alone should resolve") }
    }

    // MARK: - Honest not-resolved

    func testNotResolvedWhenOnlyConstraint() {
        // requires-python >=3.9 alone → cannot claim an exact version
        let cands = [PinCandidate(version: ">=3.9", source: "requires-python", semantics: .constraint)]
        if case .notResolved = resolveEffectiveRuntime(cands, env: "cwd") { } else {
            XCTFail("a constraint alone must not be reported as an exact version")
        }
    }

    func testNotResolvedWhenNoSources() {
        if case .notResolved = resolveEffectiveRuntime([], env: "cwd") { } else {
            XCTFail("no sources → not resolved")
        }
    }

    // MARK: - Per-language declaration parsers

    func testParsePyprojectRequiresPython() {
        let toml = """
        [project]
        name = "x"
        requires-python = ">=3.9"
        """
        XCTAssertEqual(parsePyprojectRequiresPython(toml), ">=3.9")
    }

    func testParsePackageJsonEnginesNode() {
        let json = #"{"name":"x","engines":{"node":">=18"}}"#
        XCTAssertEqual(parsePackageJsonEnginesNode(json), ">=18")
    }

    func testParseGoModDirective() {
        let gomod = "module example.com/x\n\ngo 1.21\n\nrequire ()\n"
        XCTAssertEqual(parseGoModDirective(gomod), "1.21")
    }

    func testParseGlobalJsonSdk() {
        let json = #"{"sdk":{"version":"8.0.100"}}"#
        XCTAssertEqual(parseGlobalJsonSdk(json), "8.0.100")
    }

    func testParseSwiftToolsVersion() {
        XCTAssertEqual(parseSwiftToolsVersion("// swift-tools-version:5.9\nimport PackageDescription"), "5.9")
        XCTAssertEqual(parseSwiftToolsVersion("// swift-tools-version: 6.0"), "6.0")
    }

    // MARK: - Active-toolchain output parsers

    func testParseActiveToolchainOutput() {
        XCTAssertEqual(parseToolchainVersion("Python 3.12.1", language: .python), "3.12.1")
        XCTAssertEqual(parseToolchainVersion("v20.1.0", language: .node), "20.1.0")
        XCTAssertEqual(parseToolchainVersion("go version go1.22 darwin/arm64", language: .go), "1.22")
        XCTAssertEqual(parseToolchainVersion("rustc 1.75.0 (82e1608df 2023-12-21)", language: .rust), "1.75.0")
        XCTAssertEqual(parseToolchainVersion("8.0.100", language: .dotnet), "8.0.100")
        // java prints to stderr like: openjdk version "21.0.1" 2023-10-17
        XCTAssertEqual(parseToolchainVersion(#"openjdk version "21.0.1" 2023-10-17"#, language: .java), "21.0.1")
        // swift --version multi-line
        XCTAssertEqual(parseToolchainVersion("Apple Swift version 6.0 (swiftlang-6.0)\nTarget: arm64", language: .swift), "6.0")
    }

    // MARK: - Language detection from cwd file presence

    func testDetectLanguageFromFiles() {
        XCTAssertEqual(detectLanguages(files: ["pyproject.toml"]), [.python])
        XCTAssertEqual(detectLanguages(files: ["go.mod"]), [.go])
        XCTAssertEqual(detectLanguages(files: ["Package.swift"]), [.swift])
        XCTAssertEqual(detectLanguages(files: ["global.json"]), [.dotnet])
        XCTAssertEqual(Set(detectLanguages(files: ["package.json", "go.mod"])), Set([.node, .go]))
        XCTAssertEqual(detectLanguages(files: ["README.md"]), [])
    }

    // MARK: - Boundary validation

    func testIsSafeLanguageId() {
        XCTAssertTrue(isSafeLanguageId("python"))
        XCTAssertTrue(isSafeLanguageId("node"))
        XCTAssertTrue(isSafeLanguageId("c#"))       // .NET friendly display id
        XCTAssertFalse(isSafeLanguageId("py; rm -rf /"))
        XCTAssertFalse(isSafeLanguageId("../evil"))
        XCTAssertFalse(isSafeLanguageId(""))
    }
}
