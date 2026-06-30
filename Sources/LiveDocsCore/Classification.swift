import Foundation

/// Result of probing a candidate `llms.txt`-style URL.
public enum LlmsProbeResult: Equatable, Sendable {
    case hit       // a real machine-readable doc index/full file
    case miss      // 404, a soft-404 HTML page, or too small to be real
}

/// The soft-404 guard, learned the hard way from live probing (2026-06-30):
/// several popular hosts answer `GET /llms.txt` with **HTTP 200 but a
/// `text/html` body** — their SPA shell or a styled 404 page — and others
/// answer 404 while still returning a 150 KB HTML error page. Trusting the
/// status code alone, or the byte size alone, both misclassify. A real
/// `llms.txt` is served as `text/plain` (occasionally markdown/octet-stream)
/// and is non-trivially sized.
///
/// Observed cases this rule must get right:
///   • tailwindcss.com/llms.txt → 404, text/html, 159 KB  → MISS
///   • platform.openai.com/llms.txt → 404, text/html, 3 KB → MISS
///   • svelte.dev/llms.txt → 200, text/plain, 1.6 KB → HIT (small but real index)
///   • docs.anthropic.com/llms.txt → 200, text/plain, 189 KB → HIT
public func classifyLlmsProbe(
    status: Int,
    contentType: String?,
    byteSize: Int,
    minimumBytes: Int = 200
) -> LlmsProbeResult {
    guard status == 200 else { return .miss }

    let ct = (contentType ?? "").lowercased()
    let looksLikeText =
        ct.contains("text/plain")
        || ct.contains("text/markdown")
        || ct.contains("application/octet-stream")
    guard looksLikeText else { return .miss }   // <- the soft-404 HTML guard

    guard byteSize >= minimumBytes else { return .miss }
    return .hit
}

/// Distinguish the two `llms.txt` flavors so the engine knows whether it already
/// holds substantial primary text (`full`) or just a link index it may need to
/// follow / upgrade to `llms-full.txt` (`index`). The threshold is heuristic:
/// link-index files cluster in the low-KB range, near-complete dumps in the tens
/// to hundreds of KB. Callers use this to pick fidelity, not correctness.
public func llmsFlavor(byteSize: Int, fullThreshold: Int = 20_000) -> SourceKind {
    byteSize >= fullThreshold ? .llmsFull : .llmsIndex
}
