import XCTest
@testable import LiveDocsCore

/// The SSRF guard's pure classification half: scheme allowlist + host/IP-literal
/// blocking. The DNS-resolution + redirect-revalidation half lives in the impure
/// transport and isn't unit-tested here.
final class URLSafetyTests: XCTestCase {

    func testAllowsPublicHTTPS() {
        guard case .success = URLSafety.validate("https://hono.dev/llms.txt") else {
            return XCTFail("public https should pass")
        }
    }

    func testRejectsNonHTTPScheme() {
        for u in ["file:///etc/passwd", "ftp://host/x", "gopher://h", "data:text/plain,x"] {
            guard case .failure(.disallowedScheme) = URLSafety.validate(u) else {
                return XCTFail("\(u) should be a disallowed scheme")
            }
        }
    }

    func testBlocksCloudMetadataIP() {
        guard case .failure(.blockedHost) = URLSafety.validate("http://169.254.169.254/latest/meta-data/") else {
            return XCTFail("link-local metadata IP must be blocked")
        }
    }

    func testBlocksLocalhostAndLoopback() {
        for h in ["http://localhost:8080/", "http://127.0.0.1/", "http://127.5.5.5/", "http://[::1]/"] {
            guard case .failure(.blockedHost) = URLSafety.validate(h) else {
                return XCTFail("\(h) must be blocked")
            }
        }
    }

    func testBlocksPrivateRanges() {
        for ip in ["10.0.0.1", "172.16.0.1", "172.31.255.1", "192.168.1.1", "100.64.0.1", "0.0.0.0"] {
            XCTAssertTrue(URLSafety.isBlockedIPLiteral(ip), "\(ip) should be blocked")
        }
    }

    func testAllowsPublicIPs() {
        for ip in ["8.8.8.8", "1.1.1.1", "172.32.0.1", "192.169.0.1", "100.128.0.1"] {
            XCTAssertFalse(URLSafety.isBlockedIPLiteral(ip), "\(ip) should be allowed")
        }
    }

    func testBlocksInternalNamingConventions() {
        for h in ["http://metadata.google.internal/", "http://foo.internal/", "http://bar.local/", "http://x.localhost/"] {
            guard case .failure(.blockedHost) = URLSafety.validate(h) else {
                return XCTFail("\(h) must be blocked")
            }
        }
    }

    func testBlocksIPv6LinkLocalAndULA() {
        XCTAssertTrue(URLSafety.isBlockedIPLiteral("fe80::1"))
        XCTAssertTrue(URLSafety.isBlockedIPLiteral("fd00::1"))
        XCTAssertTrue(URLSafety.isBlockedIPLiteral("fc00::1"))
        XCTAssertTrue(URLSafety.isBlockedIPLiteral("::ffff:169.254.169.254"))
    }

    func testMalformedRejected() {
        guard case .failure = URLSafety.validate("not a url at all ::: %%%") else {
            return XCTFail("garbage should fail")
        }
    }
}
