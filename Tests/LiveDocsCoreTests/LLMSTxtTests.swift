import XCTest
@testable import LiveDocsCore

final class LLMSTxtTests: XCTestCase {

    func testBareHostGetsRootAndDocsVariants() {
        let c = llmsTxtCandidates(for: "hono.dev")
        XCTAssertEqual(c.first, "https://hono.dev/llms.txt")
        XCTAssertTrue(c.contains("https://hono.dev/llms-full.txt"))
        XCTAssertTrue(c.contains("https://hono.dev/docs/llms.txt"))
    }

    func testExplicitDocsPathProbedFirst() {
        // OpenAI/Prisma/Next live under /docs — honor the path the caller gave us.
        let c = llmsTxtCandidates(for: "https://platform.openai.com/docs")
        XCTAssertEqual(c.first, "https://platform.openai.com/docs/llms.txt")
        XCTAssertTrue(c.contains("https://platform.openai.com/llms.txt"))
    }

    func testTrailingSlashAndSchemeNormalized() {
        let c = llmsTxtCandidates(for: "http://example.com/docs/")
        XCTAssertEqual(c.first, "http://example.com/docs/llms.txt")  // scheme preserved
    }

    func testNoDuplicates() {
        let c = llmsTxtCandidates(for: "https://hono.dev")
        XCTAssertEqual(c.count, Set(c).count)
    }

    func testEmptyInput() {
        XCTAssertTrue(llmsTxtCandidates(for: "   ").isEmpty)
    }

    func testFullSibling() {
        XCTAssertEqual(
            llmsFullSibling(of: "https://nextjs.org/docs/llms.txt"),
            "https://nextjs.org/docs/llms-full.txt"
        )
        XCTAssertNil(llmsFullSibling(of: "https://nextjs.org/docs/llms-full.txt"))
    }
}
