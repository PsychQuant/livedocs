import XCTest
@testable import LiveDocsCore

final class RankingTests: XCTestCase {

    func testFidelityDominatesThenFreshness() {
        let context7 = DiscoverySource(kind: .context7, url: "c7", fidelity: .low, freshness: .recent)
        let llmsIndex = DiscoverySource(kind: .llmsIndex, url: "idx", fidelity: .medium, freshness: .live)
        let llmsFull = DiscoverySource(kind: .llmsFull, url: "full", fidelity: .high, freshness: .live)
        let repo = DiscoverySource(kind: .repoReadme, url: "repo", fidelity: .high, freshness: .unknown)

        let ranked = [context7, llmsIndex, llmsFull, repo].rankedBestFirst()

        // high+live wins, then high+unknown, then medium, then low.
        XCTAssertEqual(ranked.map(\.url), ["full", "repo", "idx", "c7"])
    }

    func testStableForEqualKeys() {
        let a = DiscoverySource(kind: .repoReadme, url: "a", fidelity: .high, freshness: .live)
        let b = DiscoverySource(kind: .openAPI, url: "b", fidelity: .high, freshness: .live)
        // Equal rank keys keep input order (a before b).
        XCTAssertEqual([a, b].rankedBestFirst().map(\.url), ["a", "b"])
        XCTAssertEqual([b, a].rankedBestFirst().map(\.url), ["b", "a"])
    }
}
