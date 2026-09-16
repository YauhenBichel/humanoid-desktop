import Foundation
import Observation

/// Everything a teammate is doing, and the only place that decides what happens next: answering a message,
/// speaking, listening while the talk shortcut is held, switching teammates. The app's views show this state
/// and call these methods; the services it uses are injected, so every flow is tested without a server,
/// a speaker or a microphone.
@MainActor
@Observable
public final class TeammateSession {
    public enum Activity: Equatable, Sendable {
        case idle, thinking, speaking, listening, transcribing
    }

    /// The servers a teammate talks to.
    public struct Services: Sendable {
        public var chat: any ChatCompleting
        public var speech: any SpeechSynthesizing
        public var transcription: any SpeechTranscribing

        public init(chat: any ChatCompleting, speech: any SpeechSynthesizing, transcription: any SpeechTranscribing) {
            self.chat = chat
            self.speech = speech
            self.transcription = transcription
        }

        public static func openAICompatible(_ settings: TeammateSettings) -> Services {
            Services(
                chat: OpenAIChatClient(settings: settings),
                speech: OpenAISpeechClient(settings: settings),
                transcription: OpenAITranscriptionClient(settings: settings))
        }
    }

    public private(set) var catalog: TeammateCatalog = .builtIn
    public private(set) var teammate: Teammate = .byte
    public private(set) var expression: FaceExpression = .neutral
    /// What the teammate said last, shown in its speech bubble.
    public private(set) var bubble = ""
    /// A problem worth showing: a server that does not answer, a broken file, a missing permission.
    public private(set) var notice = ""
    public private(set) var activity: Activity = .idle
    public var draft = ""
    public var isChatOpen = false

    /// The voice's loudness 0...1. Read on every animation frame, so changes are not observed.
    @ObservationIgnored public private(set) var voiceLevel = 0.0

    @ObservationIgnored private var settings: TeammateSettings = .defaults
    @ObservationIgnored private var services: Services
    @ObservationIgnored private var conversation: Conversation
    @ObservationIgnored private let makeServices: (TeammateSettings) -> Services
    @ObservationIgnored private let player: any AudioPlaying
    @ObservationIgnored private let recorder: any AudioRecording
    @ObservationIgnored private let choices: any TeammateChoiceStore
    @ObservationIgnored private var work: Task<Void, Never>?
    /// Increases whenever what the teammate is doing is interrupted; late results from earlier turns are dropped.
    @ObservationIgnored private var turn = 0
    /// True while the talk shortcut is held down.
    @ObservationIgnored private var isTalkKeyDown = false

    public init(
        player: any AudioPlaying,
        recorder: any AudioRecording,
        choices: any TeammateChoiceStore,
        makeServices: @escaping (TeammateSettings) -> Services = Services.openAICompatible
    ) {
        self.player = player
        self.recorder = recorder
        self.choices = choices
        self.makeServices = makeServices
        let services = makeServices(.defaults)
        self.services = services
        self.conversation = Conversation(teammate: .byte, userName: "", chat: services.chat)
    }

    // MARK: Setup

    /// New settings and teammates, at launch and after Reload.
    public func configure(with library: TeammateLibrary) {
        settings = library.settings
        catalog = library.catalog
        services = makeServices(library.settings)
        let remembered = choices.chosenKey.flatMap(catalog.teammate(key:))
        choose(remembered ?? catalog.teammate(key: teammate.key) ?? catalog.teammates[0])
        notice = library.problems.joined(separator: "\n")
    }

    public func choose(_ newTeammate: Teammate) {
        interrupt()
        teammate = newTeammate
        choices.chosenKey = newTeammate.key
        conversation = Conversation(teammate: newTeammate, userName: settings.userName, chat: services.chat)
        expression = newTeammate.restingExpression
        bubble = newTeammate.greeting(userName: settings.userName)
    }

    // MARK: Talking

    /// Ask the teammate something. Ignored while it is thinking, listening or transcribing; while it is speaking,
    /// the new message interrupts.
    public func send(_ text: String) {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty, activity == .idle || activity == .speaking else { return }
        let turn = interrupt()
        draft = ""
        activity = .thinking
        expression = .thinking
        bubble = "…"
        let conversation = self.conversation
        work = Task { [weak self] in
            let reply = await conversation.respond(to: said)
            guard let self, self.isCurrent(turn) else { return }
            self.show(reply)
            if reply.source == .stopWord {
                self.activity = .idle
            } else {
                await self.speak(reply.say, turn: turn)
            }
        }
    }

    private func show(_ reply: Reply) {
        expression = reply.expression
        bubble = reply.say
        if case .failure(let reason) = reply.source {
            notice = "No answer from the chat server at \(settings.chatBaseURL.absoluteString): \(reason)"
        } else {
            notice = ""
        }
    }

    private func speak(_ text: String, turn: Int) async {
        activity = .speaking
        do {
            let wav = try await services.speech.speak(text, voice: teammate.voice)
            guard isCurrent(turn) else { return }
            try await player.play(wav) { [weak self] level in
                guard let self, self.isCurrent(turn) else { return }
                self.voiceLevel = level
            }
        } catch {
            // Without a speech server the teammate still answers, in the bubble only.
            if isCurrent(turn) {
                notice = "No voice: the speech server at \(settings.speechBaseURL.absoluteString) did not answer."
            }
        }
        if isCurrent(turn) {
            voiceLevel = 0
            activity = .idle
        }
    }

    // MARK: Hold to talk

    /// The talk shortcut went down: stop speaking and start listening once the microphone may be used.
    public func talkKeyPressed() {
        guard activity == .idle || activity == .speaking else { return }
        isTalkKeyDown = true
        let turn = interrupt(keepTalkKey: true)
        work = Task { [weak self] in
            guard let self else { return }
            let allowed = await self.recorder.requestPermission()
            // The key may have been released while macOS asked for permission: then there is nothing to record.
            guard self.isCurrent(turn), self.isTalkKeyDown else { return }
            guard allowed else {
                self.notice = "Microphone access is off: System Settings > Privacy & Security > Microphone."
                return
            }
            do {
                try self.recorder.start()
                self.activity = .listening
                self.expression = .listening
                self.bubble = "I'm listening…"
            } catch {
                self.notice = "Could not start the microphone: \(error)"
            }
        }
    }

    /// The talk shortcut came up: send what was said.
    public func talkKeyReleased() {
        isTalkKeyDown = false
        guard activity == .listening else { return }
        guard let wav = recorder.stop() else {
            activity = .idle
            expression = teammate.restingExpression
            bubble = "Hold ⌥Space while you speak."
            return
        }
        activity = .transcribing
        expression = .thinking
        bubble = "…"
        let turn = self.turn
        let transcription = services.transcription
        work = Task { [weak self] in
            do {
                let heard = try await transcription.transcribe(wav)
                guard let self, self.isCurrent(turn) else { return }
                self.activity = .idle
                self.send(heard)
            } catch {
                guard let self, self.isCurrent(turn) else { return }
                self.activity = .idle
                self.expression = .sad
                self.bubble = "Sorry, I could not hear that."
                self.notice = "No transcription from \(self.settings.transcriptionBaseURL.absoluteString): \(error)"
            }
        }
    }

    // MARK: Interrupting

    /// Stops whatever the teammate is doing and starts a new turn.
    @discardableResult
    private func interrupt(keepTalkKey: Bool = false) -> Int {
        turn += 1
        work?.cancel()
        work = nil
        player.stop()
        if activity == .listening { _ = recorder.stop() }
        if !keepTalkKey { isTalkKeyDown = false }
        activity = .idle
        voiceLevel = 0
        return turn
    }

    private func isCurrent(_ turn: Int) -> Bool { turn == self.turn }
}
