import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLRequest on Linux and Windows
#endif

// Clients for OpenAI-compatible servers, the API that Ollama, llama.cpp, vLLM, Kokoro-FastAPI, Speaches and
// most routers speak. Request and response bodies are typed Codable structs.

public struct OpenAIChatClient: ChatCompleting {
    private let settings: TeammateSettings
    private let transport: any HTTPTransport

    public init(settings: TeammateSettings, transport: any HTTPTransport = URLSessionTransport()) {
        self.settings = settings
        self.transport = transport
    }

    struct Body: Encodable {
        struct ResponseFormat: Encodable {
            struct NamedSchema: Encodable {
                let name: String
                let strict: Bool
                let schema: JSONValue
            }

            let type = "json_schema"
            let jsonSchema: NamedSchema

            enum CodingKeys: String, CodingKey { case type, jsonSchema = "json_schema" }
        }

        let model: String?
        let temperature: Double
        let messages: [ChatMessage]
        let responseFormat: ResponseFormat

        enum CodingKeys: String, CodingKey { case model, temperature, messages, responseFormat = "response_format" }
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    func request(_ messages: [ChatMessage], schema: JSONValue) throws -> URLRequest {
        let body = Body(
            model: settings.model.isEmpty ? nil : settings.model,
            temperature: 0.3,
            messages: messages,
            responseFormat: .init(jsonSchema: .init(name: "teammate_reply", strict: true, schema: schema))
        )
        var request = URLRequest(
            url: settings.chatBaseURL.appendingPathComponent("chat/completions"), timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = settings.apiKey { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    public func complete(_ messages: [ChatMessage], schema: JSONValue) async throws -> String {
        let request = try request(messages, schema: schema)
        let data = try await sendChecked(request, over: transport)
        guard let content = try? JSONDecoder().decode(Response.self, from: data).choices.first?.message.content else {
            throw ServerError.unexpectedBody(url: request.url)
        }
        return content
    }
}

public struct OpenAISpeechClient: SpeechSynthesizing {
    private let settings: TeammateSettings
    private let transport: any HTTPTransport

    public init(settings: TeammateSettings, transport: any HTTPTransport = URLSessionTransport()) {
        self.settings = settings
        self.transport = transport
    }

    struct Body: Encodable {
        let model = "tts-1"
        let input: String
        let voice: String
        let responseFormat = "wav"

        enum CodingKeys: String, CodingKey { case model, input, voice, responseFormat = "response_format" }
    }

    func request(text: String, voice: String) throws -> URLRequest {
        var request = URLRequest(
            url: settings.speechBaseURL.appendingPathComponent("audio/speech"), timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(input: text, voice: voice))
        return request
    }

    public func speak(_ text: String, voice: String) async throws -> Data {
        try await sendChecked(try request(text: text, voice: voice), over: transport)
    }
}

public struct OpenAITranscriptionClient: SpeechTranscribing {
    private let settings: TeammateSettings
    private let transport: any HTTPTransport

    public init(settings: TeammateSettings, transport: any HTTPTransport = URLSessionTransport()) {
        self.settings = settings
        self.transport = transport
    }

    private struct Response: Decodable { let text: String }

    func request(wav: Data, boundary: String = "humanoid-\(UUID().uuidString)") -> URLRequest {
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n".utf8))
        body.append(
            Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let url = settings.transcriptionBaseURL.appendingPathComponent("audio/transcriptions")
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    public func transcribe(_ wav: Data) async throws -> String {
        let request = request(wav: wav)
        let data = try await sendChecked(request, over: transport)
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ServerError.unexpectedBody(url: request.url)
        }
        return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func sendChecked(_ request: URLRequest, over transport: any HTTPTransport) async throws -> Data {
    let (data, response) = try await transport.send(request)
    guard (200..<300).contains(response.statusCode) else {
        let body = String(decoding: data.prefix(300), as: UTF8.self)
        throw ServerError.status(url: request.url, statusCode: response.statusCode, body: body)
    }
    return data
}
