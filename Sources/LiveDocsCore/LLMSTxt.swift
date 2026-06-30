import Foundation

/// Generate the ordered list of candidate `llms.txt` URLs to probe for a given
/// docs base. Live probing showed the file lives in three places depending on
/// the host's docs framework:
///   • root:        hono.dev/llms.txt, react.dev/llms.txt
///   • /docs path:  nextjs.org/docs/llms.txt, www.prisma.io/docs/llms.txt,
///                  platform.openai.com/docs/llms.txt (root 404s!)
///   • full dump:   <base>/llms-full.txt (higher fidelity when present)
///
/// We probe the index (`llms.txt`) variants first because they hit ~88% of the
/// time and are cheap; the engine separately tries to upgrade a hit to its
/// `llms-full.txt` sibling for raw fidelity. Order is preserved and duplicates
/// are removed, so passing either "hono.dev" or "https://nextjs.org/docs" yields
/// a sensible, non-redundant probe sequence.
public func llmsTxtCandidates(for base: String) -> [String] {
    guard let (origin, path) = splitOriginAndPath(base) else { return [] }

    var out: [String] = []
    func add(_ u: String) { if !out.contains(u) { out.append(u) } }

    // 1. Honor an explicit non-root path the caller already pointed us at.
    if !path.isEmpty {
        add(origin + path + "/llms.txt")
        add(origin + path + "/llms-full.txt")
    }
    // 2. Root-hosted (the most common convention).
    add(origin + "/llms.txt")
    add(origin + "/llms-full.txt")
    // 3. Conventional /docs mount (Next.js, Prisma, OpenAI live here).
    add(origin + "/docs/llms.txt")
    add(origin + "/docs/llms-full.txt")

    return out
}

/// Split an input that may be a bare host, a scheme-less URL, or a full URL into
/// (origin, path) with the scheme defaulted to https and trailing slashes and
/// any query/fragment stripped. Returns nil only for input with no host.
func splitOriginAndPath(_ raw: String) -> (origin: String, path: String)? {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return nil }
    if !s.contains("://") { s = "https://" + s }

    guard let comps = URLComponents(string: s),
          let host = comps.host, !host.isEmpty
    else { return nil }

    let scheme = comps.scheme ?? "https"
    var origin = scheme + "://" + host
    if let port = comps.port { origin += ":\(port)" }

    var path = comps.path
    while path.hasSuffix("/") { path.removeLast() }   // normalize trailing slash

    return (origin, path)
}

/// Given a hit at `<x>/llms.txt`, the sibling `<x>/llms-full.txt` URL to attempt
/// upgrading to raw fidelity. Returns nil if the input isn't an `llms.txt` URL.
public func llmsFullSibling(of llmsTxtURL: String) -> String? {
    guard llmsTxtURL.hasSuffix("/llms.txt") else { return nil }
    return String(llmsTxtURL.dropLast("/llms.txt".count)) + "/llms-full.txt"
}
