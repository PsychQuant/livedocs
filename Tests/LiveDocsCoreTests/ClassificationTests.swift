import XCTest
@testable import LiveDocsCore

/// These cases are transcribed directly from live probing of 25 popular docs
/// hosts on 2026-06-30 — they are the ground truth the soft-404 guard exists for.
final class ClassificationTests: XCTestCase {

    func testRealHits() {
        // svelte.dev/llms.txt — small (1.6 KB) but a genuine text/plain index.
        XCTAssertEqual(classifyLlmsProbe(status: 200, contentType: "text/plain; charset=utf-8", byteSize: 1676), .hit)
        // docs.anthropic.com/llms.txt — large near-full dump.
        XCTAssertEqual(classifyLlmsProbe(status: 200, contentType: "text/plain; charset=UTF-8", byteSize: 189209), .hit)
        // octet-stream is tolerated (some CDNs mislabel .txt).
        XCTAssertEqual(classifyLlmsProbe(status: 200, contentType: "application/octet-stream", byteSize: 5000), .hit)
        // markdown content-type tolerated.
        XCTAssertEqual(classifyLlmsProbe(status: 200, contentType: "text/markdown", byteSize: 5000), .hit)
    }

    func testSoft404HtmlIsMiss() {
        // tailwindcss.com/llms.txt — 404 yet returns a 159 KB HTML error page.
        XCTAssertEqual(classifyLlmsProbe(status: 404, contentType: "text/html; charset=utf-8", byteSize: 158983), .miss)
        // platform.openai.com root — 404 small HTML.
        XCTAssertEqual(classifyLlmsProbe(status: 404, contentType: "text/html; charset=utf-8", byteSize: 2890), .miss)
        // The nastiest: HTTP 200 but text/html (SPA shell). Status alone would lie.
        XCTAssertEqual(classifyLlmsProbe(status: 200, contentType: "text/html; charset=utf-8", byteSize: 50000), .miss)
    }

    func testTinyOrEmptyIsMiss() {
        XCTAssertEqual(classifyLlmsProbe(status: 200, contentType: "text/plain", byteSize: 0), .miss)
        XCTAssertEqual(classifyLlmsProbe(status: 200, contentType: "text/plain", byteSize: 199), .miss)
        XCTAssertEqual(classifyLlmsProbe(status: 200, contentType: nil, byteSize: 5000), .miss)
    }

    func testFlavorSplit() {
        // svelte index is small; anthropic dump is large.
        XCTAssertEqual(llmsFlavor(byteSize: 1676), .llmsIndex)
        XCTAssertEqual(llmsFlavor(byteSize: 189209), .llmsFull)
    }
}
