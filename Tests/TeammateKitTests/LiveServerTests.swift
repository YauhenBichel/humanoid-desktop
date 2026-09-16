import Foundation
import Testing

@testable import TeammateKit

/// Against your real servers, from your settings.toml. Off by default (CI has no servers):
///
///     HUMANOID_LIVE_SERVERS=1 swift test --filter LiveServer
@Suite(.enabled(if: ProcessInfo.processInfo.environment["HUMANOID_LIVE_SERVERS"] == "1"))
struct LiveServerTests {
    @Test func byteAnswersSpeaksAndIsHeard() async throws {
        let settings = try TeammateLibrary.loadSettings()
        let conversation = Conversation(
            teammate: .byte, userName: settings.userName, chat: OpenAIChatClient(settings: settings))
        let reply = await conversation.respond(to: "In one sentence, what is a hash map?")
        #expect(reply.source == .model, "chat server: \(reply.source)")
        print("Byte [\(reply.expression.rawValue)]: \(reply.say)")

        let wav = try await OpenAISpeechClient(settings: settings).speak(reply.say, voice: Teammate.byte.voice)
        #expect(wav.prefix(4) == Data("RIFF".utf8))
        let heard = try await OpenAITranscriptionClient(settings: settings).transcribe(wav)
        print("heard back: \(heard)")
        func words(_ text: String) -> Set<String> {
            Set(text.lowercased().split { !$0.isLetter }.map(String.init))
        }
        let overlap = Double(words(reply.say).intersection(words(heard)).count) / Double(max(1, words(reply.say).count))
        #expect(overlap > 0.6)
    }
}
