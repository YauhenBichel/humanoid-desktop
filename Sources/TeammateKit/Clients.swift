import Foundation

/// The three servers the teammate talks to, all with OpenAI-compatible APIs:
///
///   chat           POST {chat}/chat/completions          JSON-schema answers (Ollama, llama.cpp, vLLM, a router)
///   speech         POST {speech}/audio/speech            text -> WAV (Kokoro-FastAPI, a router)
///   transcription  POST {transcription}/audio/transcriptions   WAV -> text (Speaches, a router)
public struct ServerError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

private func send(_ request: URLRequest, session: URLSession) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw ServerError(message: "no HTTP response") }
    guard (200..<300).contains(http.statusCode) else {
        let body = String(decoding: data.prefix(300), as: UTF8.self)
        throw ServerError(message: "\(request.url?.absoluteString ?? "") answered \(http.statusCode): \(body)")
    }
    return data
}

public struct ChatClient: ChatCompleting {
    public let settings: Settings
    public var session: URLSession = .shared
    public var timeout: TimeInterval = 90

    public init(settings: Settings) { self.settings = settings }

    public func request(messages: [[String: String]], schema: [String: Any]) throws -> URLRequest {
        var body: [String: Any] = [
            "temperature": 0.3,
            "messages": messages,
            "response_format": ["type": "json_schema", "json_schema": ["name": "teammate_reply", "strict": true, "schema": schema]],
        ]
        if !settings.model.isEmpty { body["model"] = settings.model }
        var request = URLRequest(url: settings.chatBaseURL.appendingPathComponent("chat/completions"), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = settings.apiKey { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func complete(messages: [[String: String]], schema: [String: Any]) async throws -> String {
        let data = try await send(try request(messages: messages, schema: schema), session: session)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw ServerError(message: "the chat server's answer has no message content")
        }
        return content
    }
}

public struct SpeechClient {
    public let settings: Settings
    public var session: URLSession = .shared

    public init(settings: Settings) { self.settings = settings }

    public func speechRequest(text: String, voice: String) throws -> URLRequest {
        var request = URLRequest(url: settings.speechBaseURL.appendingPathComponent("audio/speech"), timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["model": "tts-1", "input": text, "voice": voice, "response_format": "wav"])
        return request
    }

    /// The spoken text as WAV data.
    public func speak(_ text: String, voice: String) async throws -> Data {
        try await send(try speechRequest(text: text, voice: voice), session: session)
    }

    public func transcriptionRequest(wav: Data, boundary: String = "humanoid-\(UUID().uuidString)") -> URLRequest {
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(wav)
        append("\r\n--\(boundary)--\r\n")
        var request = URLRequest(url: settings.transcriptionBaseURL.appendingPathComponent("audio/transcriptions"), timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    /// What was said in the recording.
    public func transcribe(wav: Data) async throws -> String {
        let data = try await send(transcriptionRequest(wav: wav), session: session)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let text = object["text"] as? String else {
            throw ServerError(message: "the transcription server's answer has no text")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
