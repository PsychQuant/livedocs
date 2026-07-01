import XCTest
@testable import LiveDocsCore

final class RIntrospectionTests: XCTestCase {

    func testSafeRPackageNames() {
        for n in ["dplyr", "ggplot2", "data.table", "R6", "Rcpp"] {
            XCTAssertTrue(isSafeRPackageName(n), "should accept \(n)")
        }
    }

    func testUnsafeRPackageNamesRejected() {
        // must start with a letter; no path/shell/space chars; no hyphen/underscore.
        for n in ["", "../dplyr", "1pkg", ".hidden", "d plyr", "a;b", "a-b", "a_b", "a/b"] {
            XCTAssertFalse(isSafeRPackageName(n), "should reject \(n)")
        }
    }

    func testProbeArgsGuardsName() {
        // Safe name → argv with package as a trailing ARG (not interpolated into -e).
        let args = rInstalledProbeArgs(package: "dplyr")
        XCTAssertEqual(args?.first, "-e")
        XCTAssertEqual(args?.last, "dplyr")                       // name is an argv entry
        XCTAssertEqual(args?.count, 3)
        // The R snippet reads the name via commandArgs, never string-builds it.
        XCTAssertTrue(rInstalledProbeSnippet.contains("commandArgs"))
        XCTAssertFalse(rInstalledProbeSnippet.contains("install"))  // read-only: never installs
        // Unsafe name → nil (probe refused before reaching R).
        XCTAssertNil(rInstalledProbeArgs(package: "../evil"))
    }

    func testParseInstalled() {
        // OK<TAB>version<TAB>libpath
        let r = parseRPackageVersion("OK\t1.2.1\t/Users/x/Library/R/4.6/library")
        XCTAssertEqual(r, .installed(version: "1.2.1", libPath: "/Users/x/Library/R/4.6/library"))
    }

    func testParseNotInstalled() {
        XCTAssertEqual(parseRPackageVersion("MISSING"), .notInstalled)
        XCTAssertEqual(parseRPackageVersion("  MISSING\n"), .notInstalled)   // trimmed
    }

    func testParseMalformed() {
        XCTAssertEqual(parseRPackageVersion(""), .malformed)
        XCTAssertEqual(parseRPackageVersion("Error: something"), .malformed)
        XCTAssertEqual(parseRPackageVersion("OK\t\t/lib"), .malformed)       // empty version
    }
}
