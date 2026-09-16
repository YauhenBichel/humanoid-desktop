import Foundation
import Testing

@testable import TeammateKit

/// Answers every request with one status and body, and keeps the last request.
final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    private let status: Int
    private let body: Data
    let lastRequest = Box<URLRequest>()

    init(status: Int = 200, body: String) {
        self.status = status
        self.body = Data(body.utf8)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest.value = request
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite struct OpenAIClientTests {
    private var settings: TeammateSettings {
        var settings = TeammateSettings.defaults
        settings.model = "qwen3:8b"
        return settings
    }

    @Test func chatAsksForTheReplySchemaAndReadsTheMessage() async throws {
        let transport = RecordingTransport(body: #"{"choices": [{"message": {"content": "{\"say\": \"Hi\"}"}}]}"#)
        let content = try await OpenAIChatClient(settings: settings, transport: transport)
            .complete([ChatMessage(.user, "hi")], schema: ReplyRules.schema)
        #expect(content == #"{"say": "Hi"}"#)

        let request = try #require(transport.lastRequest.value)
        #expect(request.url?.absoluteString == "http://127.0.0.1:11434/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let httpBody = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: httpBody) as? [String: Any])
        #expect(body["model"] as? String == "qwen3:8b")
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let named = try #require(format["json_schema"] as? [String: Any])
        #expect(named["strict"] as? Bool == true && named["schema"] is [String: Any])
    }

    @Test func anErrorStatusSaysWhichServerAndWhat() async throws {
        let transport = RecordingTransport(status: 404, body: "model not found")
        await #expect {
            _ = try await OpenAIChatClient(settings: settings, transport: transport).complete(
                [], schema: ReplyRules.schema)
        } throws: { error in
            (error as? ServerError)
                == .status(
                    url: URL(string: "http://127.0.0.1:11434/v1/chat/completions"), statusCode: 404,
                    body: "model not found")
        }
    }

    @Test func anAnswerWithoutAMessageIsAnUnexpectedBody() async {
        let transport = RecordingTransport(body: #"{"choices": []}"#)
        await #expect(throws: ServerError.self) {
            _ = try await OpenAIChatClient(settings: settings, transport: transport).complete(
                [], schema: ReplyRules.schema)
        }
    }

    @Test func speechUsesTheOpenAIWire() async throws {
        let transport = RecordingTransport(body: "RIFF....WAVE")
        let wav = try await OpenAISpeechClient(settings: settings, transport: transport).speak(
            "Hello", voice: "af_heart")
        #expect(wav == Data("RIFF....WAVE".utf8))
        let request = try #require(transport.lastRequest.value)
        #expect(request.url?.absoluteString == "http://127.0.0.1:8880/v1/audio/speech")
        let body = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: String]
        #expect(body == ["model": "tts-1", "input": "Hello", "voice": "af_heart", "response_format": "wav"])
    }

    @Test func transcriptionSendsAMultipartWavAndReadsTheText() async throws {
        let client = OpenAITranscriptionClient(
            settings: settings, transport: RecordingTransport(body: #"{"text": " hello \n"}"#))
        #expect(try await client.transcribe(Data([1, 2, 3])) == "hello")
        let request = client.request(wav: Data([1, 2, 3]), boundary: "B")
        #expect(request.url?.absoluteString == "http://127.0.0.1:8000/v1/audio/transcriptions")
        let text = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(text.contains("name=\"model\"\r\n\r\nwhisper-1") && text.contains("filename=\"speech.wav\""))
        #expect(text.hasSuffix("--B--\r\n"))
    }
}
