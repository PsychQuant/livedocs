import XCTest
@testable import CheLiveDocsMCP
@testable import LiveDocsCore

/// Boundary test for the composite `resolve_source{fetch_top:true}` response (#59).
/// The engine-level composite is covered in LiveDocsCoreTests; this drives the
/// SERVER seam: content rides with the list, and a top-fetch miss degrades to an
/// explicit note pointing at the fetch_docs fallback — never a silent drop.
final class ResolveSourceEncodingTests: XCTestCase {

    private func parse(_ json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? [:]
    }

    func testEncodeSourcesWithTopCarriesContentAndDegradesToNote() {
        let server = CheLiveDocsMCPServer()
        let src = DiscoverySource(kind: .llmsFull, url: "https://ex.dev/llms-full.txt",
                                  fidelity: .high, freshness: .live)

        let withTop = parse(server.encodeSourcesWithTop([src], topContent: "BODY"))
        let top = withTop["top_content"] as? [String: Any]
        XCTAssertEqual(top?["url"] as? String, "https://ex.dev/llms-full.txt")
        XCTAssertEqual(top?["content"] as? String, "BODY")
        XCTAssertEqual((withTop["sources"] as? [[String: Any]])?.count, 1)

        let missed = parse(server.encodeSourcesWithTop([src], topContent: nil))
        XCTAssertNil(missed["top_content"])
        XCTAssertTrue((missed["note"] as? String)?.contains("fetch_docs") == true,
                      "a top-fetch miss must point the agent at the fallback path")
        XCTAssertEqual((missed["sources"] as? [[String: Any]])?.count, 1, "list survives the miss")
    }
}
