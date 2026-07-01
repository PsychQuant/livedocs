import Foundation

/// Why a URL was rejected before a fetch. Distinct cases so the transport can log
/// precisely and tests can assert the reason.
public enum URLSafetyError: Error, Equatable, Sendable {
    case malformed(String)
    case disallowedScheme(String)
    case blockedHost(String)
}

/// SSRF guard — pure classification of a URL / host as safe-to-fetch or internal.
///
/// The engine fetches URLs that ultimately trace back to tool arguments (a
/// `fetch_docs` url, a `docs_url`, an openapi/graphql base). Without a guard a
/// prompt-injection in fetched docs could steer a call at `169.254.169.254`
/// (cloud metadata) or `localhost` internal services. This file holds the pure,
/// unit-testable half: scheme allowlist + host/IP-literal classification. The
/// impure half (DNS resolution of a hostname + per-redirect re-validation) lives
/// in the transport and calls `isBlockedHost` / `isBlockedIPLiteral`.
public enum URLSafety {

    /// Schemes we are willing to fetch. Anything else (file, ftp, gopher, data…)
    /// is rejected — those are classic SSRF pivots.
    public static let allowedSchemes: Set<String> = ["http", "https"]

    /// Validate a URL string for outbound fetching: well-formed, allowed scheme,
    /// and a host that is not an internal/loopback/link-local/private target.
    /// Returns the parsed `URL` on success.
    public static func validate(_ raw: String) -> Result<URL, URLSafetyError> {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else {
            return .failure(.malformed(raw))
        }
        guard allowedSchemes.contains(scheme) else {
            return .failure(.disallowedScheme(scheme))
        }
        guard let host = url.host, !host.isEmpty else {
            return .failure(.malformed(raw))
        }
        if isBlockedHost(host) {
            return .failure(.blockedHost(host))
        }
        return .success(url)
    }

    /// A hostname or IP-literal that must not be fetched. Covers loopback, the
    /// cloud metadata endpoints, and mDNS/`.internal` naming conventions, plus
    /// any literal IP in a private/link-local/loopback range.
    public static func isBlockedHost(_ host: String) -> Bool {
        var h = host.lowercased()
        // Strip an IPv6 bracket wrapper and any zone id, e.g. "[fe80::1%en0]".
        if h.hasPrefix("["), h.hasSuffix("]") { h = String(h.dropFirst().dropLast()) }
        if let pct = h.firstIndex(of: "%") { h = String(h[..<pct]) }

        if h == "localhost" || h.hasSuffix(".localhost") { return true }
        // mDNS (`.local`) and the `.internal` convention resolve inside a network.
        if h.hasSuffix(".local") || h.hasSuffix(".internal") { return true }
        // Well-known cloud metadata hostnames (the IP forms are caught below).
        if h == "metadata.google.internal" || h == "metadata" { return true }

        if isBlockedIPLiteral(h) { return true }
        return false
    }

    /// Whether a string is a literal IP address in a blocked range: loopback,
    /// link-local (incl. the `169.254.169.254` metadata address), RFC-1918
    /// private, "this host" `0.0.0.0`, IPv6 loopback/link-local/ULA, and
    /// IPv4-mapped IPv6 wrapping any of the above.
    public static func isBlockedIPLiteral(_ s: String) -> Bool {
        if let octets = ipv4Octets(s) { return isBlockedIPv4(octets) }
        return isBlockedIPv6(s.lowercased())
    }

    // MARK: - IPv4

    /// Parse a dotted-quad into four octets, or nil if it isn't one.
    private static func ipv4Octets(_ s: String) -> [Int]? {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var out: [Int] = []
        for p in parts {
            guard !p.isEmpty, p.allSatisfy({ $0.isNumber }), let n = Int(p), (0...255).contains(n)
            else { return nil }
            out.append(n)
        }
        return out
    }

    private static func isBlockedIPv4(_ o: [Int]) -> Bool {
        switch (o[0], o[1]) {
        case (0, _):            return true          // 0.0.0.0/8 "this host"
        case (10, _):           return true          // 10.0.0.0/8 private
        case (127, _):          return true          // 127.0.0.0/8 loopback
        case (169, 254):        return true          // 169.254.0.0/16 link-local (+ metadata)
        case (172, 16...31):    return true          // 172.16.0.0/12 private
        case (192, 168):        return true          // 192.168.0.0/16 private
        case (100, 64...127):   return true          // 100.64.0.0/10 CGNAT
        default:                return false
        }
    }

    // MARK: - IPv6

    private static func isBlockedIPv6(_ s: String) -> Bool {
        // IPv4-mapped / -compatible: "::ffff:169.254.169.254" etc.
        if let mapped = s.split(separator: ":").last, mapped.contains("."),
           let octets = ipv4Octets(String(mapped)) {
            return isBlockedIPv4(octets)
        }
        if s == "::1" || s == "::" { return true }               // loopback / unspecified
        if s.hasPrefix("fe80") || s.hasPrefix("fe9") ||
           s.hasPrefix("fea") || s.hasPrefix("feb") { return true } // fe80::/10 link-local
        if s.hasPrefix("fc") || s.hasPrefix("fd") { return true }   // fc00::/7 unique-local
        return false
    }
}
