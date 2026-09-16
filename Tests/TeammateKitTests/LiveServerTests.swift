import Foundation
import Testing

@testable import TeammateKit

/// Against your real servers, from your settings.toml. Off by default (CI has no servers):
///
///     HUMANOID_LIVE_SERVERS=1 swift test --filter LiveServer
@Suite(.enabled(if: ProcessInfo.processInfo.environment["HUMANOID_LIVE_SERVERS"] == "1"))
struct LiveServerTests {
    @Test func byteAnswersSpeaksAndIsHeard() async throws {
        let settings = try Settings.load()
        let conversation = Conversation(teammate: .byte, userName: settings.userName, chat: ChatClient(settings: settings))
        let reply = await conversation.respond(to: "In one sentence, what is a hash map?")
        #expect(reply.source == .model, "chat server: \(reply.error)")
        print("Byte [\(reply.expression.rawValue)]: \(reply.say)")

        let speech = SpeechClient(settings: settings)
        let wav = try await speech.speak(reply.say, voice: Teammate.byte.voice)
        #expect(wav.prefix(4) == Data("RIFF".utf8))
        let heard = try await speech.transcribe(wav: wav)
        print("heard back: \(heard)")
        let spokenWords = Set(reply.say.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let heardWords = Set(heard.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        #expect(Double(spokenWords.intersection(heardWords).count) / Double(max(1, spokenWords.count)) > 0.6)
    }
}
