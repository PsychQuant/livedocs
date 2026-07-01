import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One HTTP response, reduced to exactly what the discovery logic needs:
/// status, content-type, and the body. Keeping this tiny keeps the engine
/// testable — fakes conform to `HTTPClient` and hand back canned `HTTPResponse`s
/// without a server.
public struct HTTPResponse: Sendable, Equatable {
    public let status: Int
    public let contentType: String?
    public let body: Data
    /// The response's `ETag`, if any — the token for cheap conditional
    /// revalidation (`If-None-Match`). nil when the server doesn't provide one.
    public let etag: String?

    public init(status: Int, contentType: String?, body: Data, etag: String? = nil) {
        self.status = status
        self.contentType = contentType
        self.body = body
        self.etag = etag
    }

    public var bodyText: String { String(decoding: body, as: UTF8.self) }
}

/// The single seam between the engine and the network. Production uses
/// `URLSessionHTTPClient`; tests inject a fake. `follow` mirrors curl -L: registry
/// and docs hosts redirect liberally.
public protocol HTTPClient: Sendable {
    func get(_ url: String, headers: [String: String]) async throws -> HTTPResponse
    func post(_ url: String, body: Data, headers: [String: String]) async throws -> HTTPResponse
}

public extension HTTPClient {
    func get(_ url: String) async throws -> HTTPResponse {
        try await get(url, headers: [:])
    }
    func post(_ url: String, jsonBody: String) async throws -> HTTPResponse {
        try await post(url, body: Data(jsonBody.utf8), headers: ["Content-Type": "application/json"])
    }
}

public enum HTTPError: Error, Equatable, LocalizedError {
    case invalidURL(String)
    case noResponse
    /// The URL (or a redirect hop) targets an internal/loopback/private address.
    case blocked(String)
    /// The response body exceeded the transport size ceiling.
    case tooLarge(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let u): return "Invalid URL: \(u)"
        case .noResponse:        return "No HTTP response"
        case .blocked(let why):  return "Refusing to fetch — blocked as an internal/unsafe target (\(why))"
        case .tooLarge(let n):   return "Response exceeded the \(n)-byte size limit"
        }
    }
}

/// URLSession-backed client with SSRF and response-size hardening.
///
/// - **SSRF guard**: the initial URL and *every redirect hop* are validated —
///   scheme allowlist, plus a host classification that rejects loopback /
///   link-local / private / metadata targets, including a DNS resolution check
///   so a public hostname that resolves to an internal IP is caught.
/// - **Size ceiling**: the body is streamed and aborted past a byte limit, which
///   bounds the *decompressed* size (URLSession gunzips transparently) — a small
///   gzip bomb can't expand to gigabytes and OOM the server.
/// Redirects are still followed (registry/docs hosts redirect liberally), but
/// each hop is re-validated by `SSRFGuardDelegate`.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    private let delegate: SSRFGuardDelegate
    private let timeout: TimeInterval
    private let maxResponseBytes: Int

    public init(timeout: TimeInterval = 10, maxResponseBytes: Int = 10_000_000) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData   // "latest" means latest
        let delegate = SSRFGuardDelegate()
        self.delegate = delegate
        self.session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        self.timeout = timeout
        self.maxResponseBytes = maxResponseBytes
    }

    public func get(_ url: String, headers: [String: String]) async throws -> HTTPResponse {
        let u = try guardedURL(url)
        var req = URLRequest(url: u)
        req.httpMethod = "GET"
        req.timeoutInterval = timeout
        req.setValue(LiveDocsVersion.userAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return try await send(req)
    }

    public func post(_ url: String, body: Data, headers: [String: String]) async throws -> HTTPResponse {
        let u = try guardedURL(url)
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.httpBody = body
        req.timeoutInterval = timeout
        req.setValue(LiveDocsVersion.userAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return try await send(req)
    }

    /// Validate scheme + host (literal and DNS-resolved) before we build a request.
    private func guardedURL(_ raw: String) throws -> URL {
        switch URLSafety.validate(raw) {
        case .failure(let e):
            throw HTTPError.blocked(String(describing: e))
        case .success(let url):
            if let host = url.host, hostResolvesToBlocked(host) {
                throw HTTPError.blocked("host '\(host)' resolves to an internal address")
            }
            return url
        }
    }

    /// Stream the response with a hard byte ceiling. Iterating `AsyncBytes` counts
    /// *decoded* bytes, so a gzip bomb is bounded by the ceiling rather than the
    /// compressed size.
    private func send(_ req: URLRequest) async throws -> HTTPResponse {
        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw HTTPError.noResponse }

        var data = Data()
        data.reserveCapacity(min(maxResponseBytes, 1 << 16))
        for try await b in bytes {
            data.append(b)
            if data.count > maxResponseBytes {
                bytes.task.cancel()
                throw HTTPError.tooLarge(maxResponseBytes)
            }
        }

        let ct = http.value(forHTTPHeaderField: "Content-Type")
        let etag = http.value(forHTTPHeaderField: "ETag")
        return HTTPResponse(status: http.statusCode, contentType: ct, body: data, etag: etag)
    }

    /// DNS-resolve a hostname and reject it if any address is internal — closes
    /// the DNS-rebinding hole where a public name points at an internal IP.
    private func hostResolvesToBlocked(_ host: String) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0 else { return false }
        defer { freeaddrinfo(res) }

        var node = res
        while let n = node {
            if let sa = n.pointee.ai_addr {
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, n.pointee.ai_addrlen, &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                    if URLSafety.isBlockedIPLiteral(String(cString: buf)) { return true }
                }
            }
            node = n.pointee.ai_next
        }
        return false
    }
}

/// Re-validates every redirect hop: a public URL that 302s to an internal host
/// would otherwise bypass the front-door check, since redirects are followed
/// automatically. Returning `nil` from the redirect handler cancels the redirect.
final class SSRFGuardDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let raw = request.url?.absoluteString,
              case .success = URLSafety.validate(raw) else {
            completionHandler(nil)   // block the redirect to an internal/invalid target
            return
        }
        completionHandler(request)
    }
}
