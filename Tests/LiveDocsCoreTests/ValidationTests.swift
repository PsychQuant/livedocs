import XCTest
@testable import LiveDocsCore

final class ValidationTests: XCTestCase {

    func testRealPackageNamesAccepted() {
        for n in ["react", "@angular/core", "fastapi", "github.com/gin-gonic/gin",
                  "com.google.guava:guava", "laravel/framework", "@std/assert", "serde", "yaml.v3"] {
            XCTAssertTrue(isSafePackageName(n), "should accept \(n)")
        }
    }

    func testDangerousPackageNamesRejected() {
        for n in ["", "../../etc/passwd", "/leading", "a/../b", "has space",
                  "q?inject=1", "a#frag", "a&b", "a%2e", "pkg\nnewline"] {
            XCTAssertFalse(isSafePackageName(n), "should reject \(n)")
        }
        // length bound
        XCTAssertFalse(isSafePackageName(String(repeating: "a", count: 300)))
    }

    func testRealVersionsAccepted() {
        for v in ["18.3.1", "0.100.0", "v1.12.0", "1.0.0-rc.1", "33.4.8-jre", "19.3.0-canary-d5736f09"] {
            XCTAssertTrue(isSafeVersion(v), "should accept \(v)")
        }
    }

    func testDangerousVersionsRejected() {
        for v in ["", "-1.0", ".5", "1.0/../2", "1 0", "1?x", "latest;rm", "v/../"] {
            XCTAssertFalse(isSafeVersion(v), "should reject \(v)")
        }
    }
}
