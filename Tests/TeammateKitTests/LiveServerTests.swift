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

    /// The real model follows the tutor's steps: it moves on when the person follows, and judges a right and a
    /// wrong answer as such.
    @Test func byteTeachesALessonAndJudgesAnswers() async throws {
        let settings = try TeammateLibrary.loadSettings()
        let course = try #require(CourseCatalog.builtIn.course(key: "cs-foundations"))
        let lesson = try #require(course.lesson(key: "binary-search"))
        let tutor = Tutor(
            course: course, plan: .lesson(lesson), progress: StudyProgress(course: course.key),
            persona: Teammate.byte.persona(userName: settings.userName), chat: OpenAIChatClient(settings: settings))
        print("Byte: \(await tutor.begin().say)")
        for _ in lesson.points.indices {
            let said = "Got it, that makes sense. Next, please."
            print("> \(said)\nByte: \(await tutor.respond(to: said).say)")
        }
        #expect(await tutor.step == .asking(question: 0), "the model did not move through the points")
        let right = "The list has to be sorted, in the same order the comparisons use."
        print("> \(right)\nByte: \(await tutor.respond(to: right).say)")
        let wrong = "Because it checks every element one by one from the start."
        print("> \(wrong)\nByte: \(await tutor.respond(to: wrong).say)")
        let progress = await tutor.progress
        #expect(progress.questions["binary-search/q1"]?.last == .correct)
        #expect(progress.questions["binary-search/q2"]?.last == .wrong)
    }
}
