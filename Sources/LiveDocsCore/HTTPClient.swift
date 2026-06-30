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

    public init(status: Int, contentType: String?, body: Data) {
        self.status = status
        self.contentType = contentType
        self.body = body
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

public enum HTTPError: Error, Equatable {
    case invalidURL(String)
    case noResponse
}

/// URLSession-backed client. Redirects are followed by default (URLSession does
/// this automatically). A short timeout keeps a dead candidate from stalling the
/// whole chain — discovery probes several URLs and the slowest must not dominate.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 10) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData   // "latest" means latest
        self.session = URLSession(configuration: cfg)
        self.timeout = timeout
    }

    public func get(_ url: String, headers: [String: String]) async throws -> HTTPResponse {
        guard let u = URL(string: url) else { throw HTTPError.invalidURL(url) }
        var req = URLRequest(url: u)
        req.httpMethod = "GET"
        req.timeoutInterval = timeout
        // A real UA avoids 403s from hosts that reject empty/robot agents.
        req.setValue("LiveDocs/0.1 (+https://github.com/che-mcps/livedocs)", forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        return try await send(req)
    }

    public func post(_ url: String, body: Data, headers: [String: String]) async throws -> HTTPResponse {
        guard let u = URL(string: url) else { throw HTTPError.invalidURL(url) }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.httpBody = body
        req.timeoutInterval = timeout
        req.setValue("LiveDocs/0.1 (+https://github.com/che-mcps/livedocs)", forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return try await send(req)
    }

    private func send(_ req: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw HTTPError.noResponse }
        let ct = http.value(forHTTPHeaderField: "Content-Type")
        return HTTPResponse(status: http.statusCode, contentType: ct, body: data)
    }
}
