import Foundation
import Testing

@testable import TeammateKit

// MARK: - Fakes

@MainActor
final class FakePlayer: AudioPlaying {
    private(set) var played: [Data] = []

    func play(_ wav: Data, level: @escaping @MainActor (Double) -> Void) async throws {
        played.append(wav)
        level(0.8)
    }

    func stop() {}
}

@MainActor
final class FakeRecorder: AudioRecording {
    var recording: Data? = Data("RIFF-speech".utf8)
    var permissionGranted = true
    /// While set, permission answers only when `answerPermission()` is called, like the system dialog.
    var asksLikeTheSystem = false
    private(set) var startCount = 0
    private var pendingPermission: CheckedContinuation<Bool, Never>?

    func requestPermission() async -> Bool {
        guard asksLikeTheSystem else { return permissionGranted }
        return await withCheckedContinuation { pendingPermission = $0 }
    }

    func answerPermission() {
        pendingPermission?.resume(returning: permissionGranted)
        pendingPermission = nil
    }

    var isWaitingForPermission: Bool { pendingPermission != nil }

    func start() throws { startCount += 1 }
    func stop() -> Data? { recording }
}

@MainActor
final class MemoryChoices: TeammateChoiceStore {
    var chosenKey: String?
}

struct FixedSpeech: SpeechSynthesizing {
    var fails = false
    func speak(_ text: String, voice: String) async throws -> Data {
        if fails { throw ServerError.status(url: nil, statusCode: 503, body: "down") }
        return Data("wav:\(voice):\(text)".utf8)
    }
}

struct FixedTranscription: SpeechTranscribing {
    var heard = "what is recursion?"
    func transcribe(_ wav: Data) async throws -> String { heard }
}

/// A chat server that holds its answer until the test releases it.
actor GatedChat: ChatCompleting {
    private var waiting: CheckedContinuation<Void, Never>?
    private(set) var questions: [String] = []

    func complete(_ messages: [ChatMessage], schema: JSONValue) async throws -> String {
        questions.append(messages.last?.content ?? "")
        await withCheckedContinuation { waiting = $0 }
        return #"{"say": "Late answer.", "expression": "surprised"}"#
    }

    var isWaiting: Bool { waiting != nil }

    func release() {
        waiting?.resume()
        waiting = nil
    }
}

@MainActor
private func makeSession(
    chat: any ChatCompleting = CannedChat(say: "Recursion is a function calling itself."),
    speech: FixedSpeech = FixedSpeech(),
    transcription: FixedTranscription = FixedTranscription(),
    recorder: FakeRecorder = FakeRecorder(),
    choices: MemoryChoices = MemoryChoices()
) -> (TeammateSession, FakePlayer) {
    let player = FakePlayer()
    let session = TeammateSession(player: player, recorder: recorder, choices: choices) { _ in
        .init(chat: chat, speech: speech, transcription: transcription)
    }
    session.configure(with: TeammateLibrary(settings: .defaults, catalog: .builtIn, problems: []))
    return (session, player)
}

/// Waits for work the session started in the background to reach a state.
@MainActor
private func eventually(_ condition: @MainActor () async -> Bool) async {
    for _ in 0..<200 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("the condition was never met")
}

// MARK: - Tests

@MainActor
@Suite struct TeammateSessionTests {
    @Test func aMessageIsAnsweredShownAndSpokenInTheTeammatesVoice() async {
        let (session, player) = makeSession()
        session.draft = "what is recursion?"
        session.send(session.draft)
        #expect(session.activity == .thinking && session.expression == .thinking && session.draft.isEmpty)

        await eventually { session.activity == .idle && !player.played.isEmpty }
        #expect(session.bubble == "Recursion is a function calling itself." && session.expression == .happy)
        #expect(player.played == [Data("wav:af_heart:Recursion is a function calling itself.".utf8)])
        #expect(session.voiceLevel == 0 && session.notice.isEmpty)
    }

    @Test func aLateAnswerForTheOldTeammateNeverReachesTheNewOne() async {
        let chat = GatedChat()
        let (session, player) = makeSession(chat: chat)
        session.send("tell me about heaps")
        await eventually { await chat.isWaiting }

        session.choose(.tempo)
        await chat.release()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(session.teammate == .tempo && session.bubble == SessionPhrases.english.greeting("", .tempo))
        #expect(session.expression == .happy && session.activity == .idle && player.played.isEmpty)
    }

    @Test func messagesAreIgnoredWhileThinking() async {
        let chat = GatedChat()
        let (session, _) = makeSession(chat: chat)
        session.send("first")
        session.send("second")
        await eventually { await chat.isWaiting }
        #expect(await chat.questions == ["first"])
        await chat.release()
    }

    @Test func aStopWordIsNotSpoken() async {
        let (session, player) = makeSession()
        session.send("stop")
        await eventually { session.activity == .idle }
        #expect(session.bubble == "Okay, I'll be quiet." && player.played.isEmpty)
    }

    @Test func withoutASpeechServerTheAnswerStaysInTheBubble() async {
        let (session, player) = makeSession(speech: FixedSpeech(fails: true))
        session.send("hello")
        await eventually { session.activity == .idle && !session.notice.isEmpty }
        #expect(session.bubble == "Recursion is a function calling itself." && player.played.isEmpty)
        #expect(session.notice.hasPrefix("No voice"))
    }

    @Test func withoutAChatServerTheTeammateApologisesAndSaysWhere() async {
        let (session, _) = makeSession(
            chat: CannedChat { _ in throw ServerError.status(url: nil, statusCode: 500, body: "boom") })
        session.send("hello")
        await eventually { !session.notice.isEmpty }
        #expect(session.expression == .sad && session.notice.contains("http://127.0.0.1:11434/v1"))
    }

    @Test func holdingTheTalkKeyListensThenSendsWhatWasHeard() async {
        let chat = Box<[ChatMessage]>()
        let (session, player) = makeSession(
            chat: CannedChat { messages in
                chat.value = messages
                return #"{"say": "A function that calls itself.", "expression": "happy"}"#
            })
        session.talkKeyPressed()
        await eventually { session.activity == .listening }
        #expect(session.expression == .listening)

        session.talkKeyReleased()
        #expect(session.activity == .transcribing)
        await eventually { session.activity == .idle && !player.played.isEmpty }
        #expect(chat.value?.last?.content == "what is recursion?")
        #expect(session.bubble == "A function that calls itself.")
    }

    @Test func releasingTheKeyBeforeMicrophonePermissionMeansNoRecording() async {
        let recorder = FakeRecorder()
        recorder.asksLikeTheSystem = true
        let (session, _) = makeSession(recorder: recorder)
        session.talkKeyPressed()
        await eventually { recorder.isWaitingForPermission }

        session.talkKeyReleased()  // a quick tap: released while macOS is still asking
        recorder.answerPermission()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(recorder.startCount == 0 && session.activity == .idle)
    }

    @Test func withoutMicrophonePermissionTheTeammateSaysWhereToAllowIt() async {
        let recorder = FakeRecorder()
        recorder.permissionGranted = false
        let (session, _) = makeSession(recorder: recorder)
        session.talkKeyPressed()
        await eventually { !session.notice.isEmpty }
        #expect(session.notice == SessionPhrases.english.microphoneOff && recorder.startCount == 0)
    }

    @Test func aTapTooShortForAWordAsksToHoldTheKey() async {
        let recorder = FakeRecorder()
        recorder.recording = nil
        let (session, _) = makeSession(recorder: recorder)
        session.talkKeyPressed()
        await eventually { session.activity == .listening }
        session.talkKeyReleased()
        #expect(session.activity == .idle && session.bubble == SessionPhrases.english.holdToTalk)
    }

    @Test func theLastChosenTeammateComesBackAndFileProblemsAreShown() {
        let choices = MemoryChoices()
        choices.chosenKey = "tempo"
        let (session, _) = makeSession(choices: choices)
        #expect(session.teammate == .tempo)

        session.configure(
            with: TeammateLibrary(settings: .defaults, catalog: .builtIn, problems: ["nova.toml: accessory"]))
        #expect(session.notice == "nova.toml: accessory")
        session.choose(.byte)
        #expect(choices.chosenKey == "byte")
    }
}
