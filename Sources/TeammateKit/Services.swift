import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux and Windows
#endif

// The seams between the teammate and the outside world. Each is one small job, so a test (or another app)
// supplies only what it needs, and the session depends on these rather than on URLSession or AVFoundation.

/// Answers chat messages with text matching a JSON schema.
public protocol ChatCompleting: Sendable {
    func complete(_ messages: [ChatMessage], schema: JSONValue) async throws -> String
}

/// Turns text into spoken audio (WAV).
public protocol SpeechSynthesizing: Sendable {
    func speak(_ text: String, voice: String) async throws -> Data
}

/// Turns recorded speech (WAV) into text.
public protocol SpeechTranscribing: Sendable {
    func transcribe(_ wav: Data) async throws -> String
}

/// Plays audio and reports how loud it is while playing, for the mouth.
@MainActor
public protocol AudioPlaying: AnyObject {
    /// Returns when playback ends or `stop()` is called. `level` receives 0...1 while playing.
    func play(_ wav: Data, level: @escaping @MainActor (Double) -> Void) async throws
    func stop()
}

/// Records speech from the microphone.
@MainActor
public protocol AudioRecording: AnyObject {
    func requestPermission() async -> Bool
    func start() throws
    /// The recording, or nil when it was too short to hold a word.
    func stop() -> Data?
}

/// Remembers which teammate was chosen last.
@MainActor
public protocol TeammateChoiceStore: AnyObject {
    var chosenKey: String? { get set }
}

/// Sends HTTP requests; URLSession in the app, a fake in tests.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServerError.notHTTP(url: request.url) }
        return (data, http)
    }
}

public enum ServerError: Error, Equatable, Sendable, CustomStringConvertible {
    case notHTTP(url: URL?)
    case status(url: URL?, statusCode: Int, body: String)
    case unexpectedBody(url: URL?)

    public var description: String {
        switch self {
        case .notHTTP(let url):
            "\(url?.absoluteString ?? "the server") did not answer over HTTP"
        case .status(let url, let statusCode, let body):
            "\(url?.absoluteString ?? "the server") answered \(statusCode): \(body)"
        case .unexpectedBody(let url):
            "\(url?.absoluteString ?? "the server") answered in an unexpected format"
        }
    }
}
