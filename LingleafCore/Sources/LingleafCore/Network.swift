import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HttpResponse: Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }

    public init(status: Int, text: String) {
        self.init(status: status, body: Data(text.utf8))
    }

    public var text: String { String(decoding: body, as: UTF8.self) }
}

/// Minimal HTTP abstraction so network code stays testable without a server.
public protocol HttpFetcher: Sendable {
    func get(_ url: String) async throws -> HttpResponse
    /// Like `get`, reporting progress (0…1) while the body arrives.
    func get(_ url: String, progress: (@Sendable (Double) -> Void)?) async throws -> HttpResponse
}

extension HttpFetcher {
    public func get(_ url: String, progress: (@Sendable (Double) -> Void)?) async throws -> HttpResponse {
        let response = try await get(url)
        progress?(1)
        return response
    }
}

public struct NetworkError: Error, Equatable {
    public enum Kind: Equatable, Sendable {
        /// No internet connection.
        case offline
        case timedOut
        case other
    }

    public let message: String
    public let kind: Kind

    public init(_ message: String, kind: Kind = .other) {
        self.message = message
        self.kind = kind
    }
}

/// Wraps a closure; handy for tests and previews.
public struct ClosureFetcher: HttpFetcher {
    private let handler: @Sendable (String) async throws -> HttpResponse

    public init(_ handler: @escaping @Sendable (String) async throws -> HttpResponse) {
        self.handler = handler
    }

    public func get(_ url: String) async throws -> HttpResponse { try await handler(url) }
}

/// Size caps for anything read into memory. The longest recommended book
/// (Middlemarch) is under 2 MB of plain text.
public enum Limits {
    /// Largest download or imported file accepted.
    public static let maxBytes = 10 * 1024 * 1024
}

/// HTTPS-only fetcher. Plain HTTP is refused before any connection is made,
/// and responses larger than `maxBytes` are cut off with an error.
public struct URLSessionFetcher: HttpFetcher {
    private let maxBytes: Int

    public init(maxBytes: Int = Limits.maxBytes) { self.maxBytes = maxBytes }

    public func get(_ url: String) async throws -> HttpResponse {
        try await get(url, progress: nil)
    }

    /// Downloads the whole body in one go (not byte by byte), with progress from the
    /// task. 30 s without data times out; cancelling the calling task cancels the request.
    public func get(_ url: String, progress: (@Sendable (Double) -> Void)?) async throws -> HttpResponse {
        guard url.hasPrefix("https://"), let address = URL(string: url) else { throw NetworkError("Only HTTPS is allowed") }
        var request = URLRequest(url: address, timeoutInterval: 30)
        request.setValue("Lingleaf/0.1 (+https://github.com/erobinsonc/lingleaf-ios)", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        let observer = ProgressObserver(maxBytes: maxBytes, progress: progress)
        do {
            (data, response) = try await URLSession.shared.data(for: request, delegate: observer)
        } catch let error as URLError {
            throw observer.tooLarge ? NetworkError("Response too large") : Self.networkError(error)
        }
        guard data.count <= maxBytes else { throw NetworkError("Response too large") }
        progress?(1)
        return HttpResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }

    static func networkError(_ error: URLError) -> Error {
        switch error.code {
        case .cancelled:
            return CancellationError()
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return NetworkError(error.localizedDescription, kind: .offline)
        case .timedOut:
            return NetworkError(error.localizedDescription, kind: .timedOut)
        default:
            return NetworkError(error.localizedDescription)
        }
    }
}

/// Follows the request's progress and cancels it once it passes `maxBytes`.
private final class ProgressObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let maxBytes: Int
    private let progress: (@Sendable (Double) -> Void)?
    private var observation: NSKeyValueObservation?
    /// Set (on the KVO thread) when the body passed `maxBytes` and the request was cancelled for it.
    private let lock = NSLock()
    private var exceeded = false
    var tooLarge: Bool { lock.withLock { exceeded } }

    init(maxBytes: Int, progress: (@Sendable (Double) -> Void)?) {
        self.maxBytes = maxBytes
        self.progress = progress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        let maxBytes = Int64(maxBytes)
        let progress = progress
        observation = task.progress.observe(\.completedUnitCount) { [weak self, weak task] value, _ in
            if value.completedUnitCount > maxBytes {
                self?.lock.withLock { self?.exceeded = true }
                task?.cancel()
            }
            if value.totalUnitCount > 0 { progress?(value.fractionCompleted) }
        }
    }
}
