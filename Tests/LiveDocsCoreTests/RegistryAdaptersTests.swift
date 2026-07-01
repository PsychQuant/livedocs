import XCTest
@testable import LiveDocsCore

/// Fixtures transcribed from live curls (2026-07-01) of each registry.
final class RegistryAdaptersTests: XCTestCase {

    func testCratesIo() throws {
        let json = #"""
        {"crate":{"name":"serde","max_stable_version":"1.0.228","newest_version":"1.0.228",
          "repository":"https://github.com/serde-rs/serde","homepage":"https://serde.rs",
          "documentation":"https://docs.rs/serde"}}
        """#.data(using: .utf8)!
        let r = try parseCratesIo(json)
        XCTAssertEqual(r.version, "1.0.228")
        XCTAssertEqual(r.repository, "https://github.com/serde-rs/serde")
        XCTAssertEqual(r.homepage, "https://serde.rs")
        XCTAssertEqual(r.documentation, "https://docs.rs/serde")
        XCTAssertNil(r.changelog)
    }

    func testRubyGems() throws {
        let json = #"""
        {"name":"rails","version":"8.1.3","homepage_uri":"https://rubyonrails.org",
          "source_code_uri":"https://github.com/rails/rails/tree/v8.1.3",
          "documentation_uri":"https://api.rubyonrails.org/v8.1.3/",
          "changelog_uri":"https://github.com/rails/rails/releases/tag/v8.1.3"}
        """#.data(using: .utf8)!
        let r = try parseRubyGems(json)
        XCTAssertEqual(r.version, "8.1.3")
        XCTAssertEqual(r.repository, "https://github.com/rails/rails/tree/v8.1.3")
        XCTAssertEqual(r.changelog, "https://github.com/rails/rails/releases/tag/v8.1.3")
    }

    func testGoProxy() throws {
        let json = #"""
        {"Version":"v1.12.0","Time":"2026-02-28T10:10:09Z",
          "Origin":{"VCS":"git","URL":"https://github.com/gin-gonic/gin","Ref":"refs/tags/v1.12.0"}}
        """#.data(using: .utf8)!
        let r = try parseGoProxy(json)
        XCTAssertEqual(r.version, "v1.12.0")
        XCTAssertEqual(r.repository, "https://github.com/gin-gonic/gin")
    }

    func testGoProxyWithoutOrigin() throws {
        // Older/pseudo-version modules omit Origin → version but no repo.
        let r = try parseGoProxy(#"{"Version":"v3.0.1"}"#.data(using: .utf8)!)
        XCTAssertEqual(r.version, "v3.0.1")
        XCTAssertNil(r.repository)
    }

    func testJSRMetaAndPackage() throws {
        let meta = try parseJSRMeta(#"{"scope":"std","name":"assert","latest":"1.0.19","versions":{"1.0.19":{}}}"#.data(using: .utf8)!)
        XCTAssertEqual(meta.version, "1.0.19")
        let pkg = try parseJSRPackage(#"""
        {"githubRepository":{"owner":"denoland","name":"std"},"latestVersion":"1.0.19"}
        """#.data(using: .utf8)!)
        XCTAssertEqual(pkg.repository, "https://github.com/denoland/std")
        XCTAssertEqual(pkg.version, "1.0.19")
    }

    func testPackagist() throws {
        let json = #"""
        {"packages":{"laravel/framework":[
          {"version":"v13.18.0","source":{"url":"https://github.com/laravel/framework.git"},
           "homepage":"https://laravel.com","support":{"source":"https://github.com/laravel/framework"}},
          {"version":"v13.17.0"}]}}
        """#.data(using: .utf8)!
        let r = try parsePackagist(json)
        XCTAssertEqual(r.version, "v13.18.0")                       // [0] is latest
        XCTAssertEqual(r.repository, "https://github.com/laravel/framework")  // .git stripped
        XCTAssertEqual(r.homepage, "https://laravel.com")
        XCTAssertNil(r.documentation)   // support.source is the repo URL, not docs — don't mislabel
    }

    func testMavenSearch() throws {
        let json = #"""
        {"response":{"numFound":1,"docs":[{"g":"com.google.guava","a":"guava",
          "latestVersion":"33.4.8-jre","versionCount":150}]}}
        """#.data(using: .utf8)!
        let r = try parseMavenSearch(json)
        XCTAssertEqual(r.version, "33.4.8-jre")
    }

    func testCRAN() throws {
        let json = #"""
        {"Package":"dplyr","Version":"1.2.1",
          "URL":"https://dplyr.tidyverse.org, https://github.com/tidyverse/dplyr",
          "BugReports":"https://github.com/tidyverse/dplyr/issues"}
        """#.data(using: .utf8)!
        let r = try parseCRAN(json)
        XCTAssertEqual(r.version, "1.2.1")
        XCTAssertEqual(r.repository, "https://github.com/tidyverse/dplyr")   // forge URL from list
        XCTAssertEqual(r.homepage, "https://dplyr.tidyverse.org")            // non-forge = docs site
    }

    func testCRANRepoFromBugReportsWhenURLLacksForge() throws {
        let json = #"{"Version":"2.0.0","URL":"https://example.org/pkg","BugReports":"https://github.com/o/r/issues"}"#.data(using: .utf8)!
        let r = try parseCRAN(json)
        XCTAssertEqual(r.repository, "https://github.com/o/r")   // recovered from BugReports
        XCTAssertEqual(r.homepage, "https://example.org/pkg")
    }

    func testCRANNoRepo() throws {
        let r = try parseCRAN(#"{"Version":"1.0"}"#.data(using: .utf8)!)   // base pkg, no URLs
        XCTAssertEqual(r.version, "1.0")
        XCTAssertNil(r.repository)
        XCTAssertNil(r.homepage)
    }

    func testMalformedRejected() {
        XCTAssertThrowsError(try parseCRAN(Data("{}".utf8)))   // no Version
        XCTAssertThrowsError(try parseCratesIo(Data("{}".utf8)))
        XCTAssertThrowsError(try parseRubyGems(Data("[]".utf8)))
        XCTAssertThrowsError(try parseGoProxy(Data("{}".utf8)))
        XCTAssertThrowsError(try parsePackagist(Data(#"{"packages":{}}"#.utf8)))
        XCTAssertThrowsError(try parseMavenSearch(Data(#"{"response":{"docs":[]}}"#.utf8)))
    }
}
