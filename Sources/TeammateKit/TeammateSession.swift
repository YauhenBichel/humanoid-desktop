import Foundation
import Observation

/// Everything a teammate is doing, and the only place that decides what happens next: answering a message,
/// speaking, listening while the talk shortcut is held, switching teammates, teaching. The app's views show this state
/// and call these methods; the services it uses are injected, so every flow is tested without a server,
/// a speaker or a microphone.
@MainActor
@Observable
public final class TeammateSession {
    public enum Activity: Equatable, Sendable {
        case idle, thinking, speaking, listening, transcribing
    }

    /// A lesson or review in progress.
    public struct StudyStatus: Equatable, Sendable {
        /// Nil for a review.
        public var lessonTitle: String?
        /// 1-based, while a question is waiting for its answer.
        public var question: Int?
        public var questionCount: Int
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
    /// The course the current teammate teaches, and how far the person is in it; nil for a teammate without one.
    public private(set) var course: Course?
    public private(set) var progress: StudyProgress?
    /// The lesson or review in progress; nil while just talking.
    public private(set) var study: StudyStatus?
    public var draft = ""
    public var isChatOpen = false

    /// The voice's loudness 0...1. Read on every animation frame, so changes are not observed.
    @ObservationIgnored public private(set) var voiceLevel = 0.0

    @ObservationIgnored private var settings: TeammateSettings = .defaults
    @ObservationIgnored private var services: Services
    @ObservationIgnored private var conversation: Conversation
    @ObservationIgnored private var courses: CourseCatalog = .builtIn
    @ObservationIgnored private var tutor: Tutor?
    @ObservationIgnored private let makeServices: (TeammateSettings) -> Services
    @ObservationIgnored private let player: any AudioPlaying
    @ObservationIgnored private let recorder: any AudioRecording
    @ObservationIgnored private let choices: any TeammateChoiceStore
    @ObservationIgnored private let memories: any MemoryStore
    @ObservationIgnored private let progressStore: any ProgressStore
    @ObservationIgnored private let phrases: SessionPhrases
    @ObservationIgnored private var work: Task<Void, Never>?
    /// Increases whenever what the teammate is doing is interrupted; late results from earlier turns are dropped.
    @ObservationIgnored private var turn = 0
    /// True while the talk shortcut is held down.
    @ObservationIgnored private var isTalkKeyDown = false

    public init(
        player: any AudioPlaying,
        recorder: any AudioRecording,
        choices: any TeammateChoiceStore,
        memories: any MemoryStore,
        progressStore: any ProgressStore,
        phrases: SessionPhrases = .english,
        makeServices: @escaping (TeammateSettings) -> Services = Services.openAICompatible
    ) {
        self.player = player
        self.recorder = recorder
        self.choices = choices
        self.memories = memories
        self.progressStore = progressStore
        self.phrases = phrases
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
        courses = library.courses
        services = makeServices(library.settings)
        notice = library.problems.joined(separator: "\n")
        let remembered = choices.chosenKey.flatMap(catalog.teammate(key:))
        choose(remembered ?? catalog.teammate(key: teammate.key) ?? catalog.teammates[0])
    }

    public func choose(_ newTeammate: Teammate) {
        interrupt()
        teammate = newTeammate
        choices.chosenKey = newTeammate.key
        var memory = TeammateMemory()
        do {
            memory = try memories.load(teammateKey: newTeammate.key)
        } catch {
            addNotice(phrases.memoryFailed(String(describing: error)))
        }
        loadCourse(of: newTeammate)
        conversation = Conversation(
            teammate: newTeammate, userName: settings.userName, language: settings.language, phrases: phrases,
            memory: memory, studyNote: studyNote, chat: services.chat)
        expression = newTeammate.restingExpression
        bubble = phrases.greeting(settings.userName, newTeammate)
    }

    private func loadCourse(of teammate: Teammate) {
        tutor = nil
        study = nil
        course = teammate.course.flatMap(courses.course(key:))
        guard let course else {
            progress = nil
            return
        }
        do {
            progress = try progressStore.load(courseKey: course.key)
        } catch {
            progress = StudyProgress(course: course.key)
            addNotice(phrases.progressFailed(String(describing: error)))
        }
    }

    private var studyNote: String? {
        guard let course, let progress else { return nil }
        return progress.promptSection(course: course, at: Date())
    }

    /// Shows a problem below any already shown (a settings file with a mistake, say), once.
    private func addNotice(_ line: String) {
        let lines = notice.split(separator: "\n").map(String.init)
        guard !lines.contains(line) else { return }
        notice = (lines + [line]).joined(separator: "\n")
    }

    /// Deletes what the current teammate remembers, and starts over with an empty memory.
    public func forgetMemory() {
        interrupt()
        do {
            try memories.erase(teammateKey: teammate.key)
        } catch {
            notice = phrases.memoryFailed(String(describing: error))
            return
        }
        conversation = Conversation(
            teammate: teammate, userName: settings.userName, language: settings.language, phrases: phrases,
            studyNote: studyNote, chat: services.chat)
        expression = .happy
        bubble = phrases.forgotten(teammate)
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
        bubble = phrases.thinking
        let conversation = self.conversation
        let tutor = self.tutor
        work = Task { [weak self] in
            let reply =
                if let tutor { await tutor.respond(to: said) } else { await conversation.respond(to: said) }
            guard let self, self.isCurrent(turn) else { return }
            self.show(reply)
            if reply.source == .model {
                if let tutor {
                    await conversation.note(said: said, reply: reply)
                    await self.keepProgress(of: tutor, conversation: conversation)
                }
                await self.keepMemory(of: conversation)
            }
            if reply.source == .stopWord {
                self.activity = .idle
            } else {
                await self.speak(reply.say, turn: turn)
            }
        }
    }

    private func keepMemory(of conversation: Conversation) async {
        let memory = await conversation.memory
        do {
            try memories.save(memory, teammateKey: conversation.teammate.key)
        } catch {
            notice = phrases.memoryFailed(String(describing: error))
        }
    }

    private func show(_ reply: Reply) {
        expression = reply.expression
        bubble = reply.say
        if case .failure(let reason) = reply.source {
            notice = phrases.chatServerFailed(settings.chatBaseURL.absoluteString, reason)
        } else {
            notice = ""
        }
    }

    private func speak(_ text: String, turn: Int) async {
        activity = .speaking
        do {
            let wav = try await services.speech.speak(text, voice: teammate.voice(for: settings.language))
            guard isCurrent(turn) else { return }
            try await player.play(wav) { [weak self] level in
                guard let self, self.isCurrent(turn) else { return }
                self.voiceLevel = level
            }
        } catch {
            // Without a speech server the teammate still answers, in the bubble only.
            if isCurrent(turn) { notice = phrases.speechServerFailed(settings.speechBaseURL.absoluteString) }
        }
        if isCurrent(turn) {
            voiceLevel = 0
            activity = .idle
        }
    }

    // MARK: Studying

    /// Starts a lesson of the teammate's course: the one given, or the first not finished yet.
    public func startLesson(_ lesson: Course.Lesson? = nil) {
        guard let course, let progress else { return }
        guard let lesson = lesson ?? progress.nextLesson(in: course) else {
            interrupt()
            expression = .happy
            bubble = phrases.courseFinished(course.title)
            return
        }
        beginStudy(.lesson(lesson))
    }

    /// Asks the questions that are due again, the longest overdue first.
    public func startReview() {
        guard let course, let progress else { return }
        beginStudy(.review(progress.due(in: course, at: Date())))
    }

    /// Stops the lesson or review; what was answered so far is already saved.
    public func endStudy() {
        guard tutor != nil else { return }
        interrupt()
        tutor = nil
        study = nil
        expression = teammate.restingExpression
        bubble = phrases.studyEnded
    }

    private func beginStudy(_ plan: Tutor.Plan) {
        guard let course, let progress else { return }
        let turn = interrupt()
        tutor = nil
        study = nil
        activity = .thinking
        expression = .thinking
        bubble = phrases.thinking
        let conversation = self.conversation
        let persona = teammate.persona(userName: settings.userName, language: settings.language)
        let (userName, language, chat) = (settings.userName, settings.language, services.chat)
        let phrases = self.phrases
        work = Task { [weak self] in
            let background = await conversation.memory.promptSection(
                personName: userName.isEmpty ? "the person" : userName)
            let tutor = Tutor(
                course: course, plan: plan, progress: progress, persona: persona, background: background,
                language: language, phrases: phrases, chat: chat)
            let reply = await tutor.begin()
            guard let self, self.isCurrent(turn) else { return }
            self.tutor = tutor
            self.show(reply)
            await self.keepProgress(of: tutor, conversation: conversation)
            await self.speak(reply.say, turn: turn)
        }
    }

    /// Saves the tutor's progress, shows where the lesson is, and returns to talking when it is over.
    private func keepProgress(of tutor: Tutor, conversation: Conversation) async {
        let latest = await tutor.progress
        if latest != progress {
            progress = latest
            do {
                try progressStore.save(latest)
            } catch {
                addNotice(phrases.progressFailed(String(describing: error)))
            }
        }
        guard self.tutor === tutor else { return }
        if await tutor.isFinished {
            self.tutor = nil
            study = nil
            await conversation.update(studyNote: studyNote)
            return
        }
        let question: Int? = if case .asking(let index) = await tutor.step { index + 1 } else { nil }
        study = StudyStatus(
            lessonTitle: await tutor.lessonTitle, question: question, questionCount: await tutor.questionCount)
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
            // The key may have been released while the system asked for permission: then there is nothing to record.
            guard self.isCurrent(turn), self.isTalkKeyDown else { return }
            guard allowed else {
                self.notice = self.phrases.microphoneOff
                return
            }
            do {
                try self.recorder.start()
                self.activity = .listening
                self.expression = .listening
                self.bubble = self.phrases.listening
            } catch {
                self.notice = self.phrases.microphoneFailed(String(describing: error))
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
            bubble = phrases.holdToTalk
            return
        }
        activity = .transcribing
        expression = .thinking
        bubble = phrases.thinking
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
                self.bubble = self.phrases.couldNotHear
                self.notice = self.phrases.transcriptionServerFailed(
                    self.settings.transcriptionBaseURL.absoluteString, String(describing: error))
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
