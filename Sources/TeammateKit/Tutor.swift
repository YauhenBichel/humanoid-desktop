import Foundation

/// Teaches one lesson, or reviews questions that are due, one short spoken turn at a time.
///
/// A lesson teaches its points in order, then asks its questions word for word; a review asks due questions only.
/// Every decision is made apart from the teammate's voice: a `LessonChecker` with no persona decides whether the
/// person follows or needs help, and judges each answer against the course's own correct answer. The teammate then
/// gets one plain job per turn (say this point, help with it, tell them how they did). Asking one warm teammate
/// call to decide and speak at once did not work with a local model: it praised wrong answers, and it lost track
/// of the points. The plan, the steps and the scoring stay here, in code.
public actor Tutor {
    public enum Plan: Equatable, Sendable {
        case lesson(Course.Lesson)
        case review([StudyItem])
    }

    public enum Step: Equatable, Sendable {
        case teaching(point: Int)
        case asking(question: Int)
        case finished
    }

    /// Latest turns of this lesson sent back to the model.
    static let contextMessages = 8

    public let course: Course
    public let plan: Plan
    public private(set) var step: Step
    public private(set) var progress: StudyProgress
    public private(set) var correctAnswers = 0

    private let items: [StudyItem]
    private let points: [String]
    private let persona: String
    private let background: String?
    private let language: Language?
    private let phrases: SessionPhrases
    private let chat: any ChatCompleting
    private let checker: LessonChecker
    private let now: @Sendable () -> Date
    private var transcript: [ChatMessage] = []

    public init(
        course: Course,
        plan: Plan,
        progress: StudyProgress,
        persona: String,
        background: String? = nil,
        language: Language? = nil,
        phrases: SessionPhrases = .english,
        chat: any ChatCompleting,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.course = course
        self.plan = plan
        self.progress = progress
        self.persona = persona
        self.background = background
        self.language = language
        self.phrases = phrases
        self.chat = chat
        self.checker = LessonChecker(chat: chat)
        self.now = now
        switch plan {
        case .lesson(let lesson):
            items = lesson.questions.map { StudyItem(lesson: lesson, question: $0) }
            points = lesson.points
            step = .teaching(point: 0)
        case .review(let due):
            items = due
            points = []
            step = due.isEmpty ? .finished : .asking(question: 0)
        }
    }

    public var isFinished: Bool { step == .finished }

    public var questionCount: Int { items.count }

    /// The lesson's title, or nil for a review.
    public var lessonTitle: String? {
        guard case .lesson(let lesson) = plan else { return nil }
        return lesson.title
    }

    // MARK: Turns

    /// The tutor's first turn: introduce the lesson and teach its first point, or start the review.
    public func begin() async -> Reply {
        switch plan {
        case .lesson(let lesson):
            return await say(
                """
                Start the lesson "\(lesson.title)": greet the person in a few words, then say this first point out \
                loud, close to its own words and with its example: \(points[0]) End by checking that they follow.
                """)
        case .review:
            guard !items.isEmpty else { return Reply(say: phrases.nothingToReview, expression: .happy) }
            let reply = await say(
                """
                Say in one short sentence that you will now review \(items.count) questions from lessons you already \
                did together. Do not ask a question yourself: it is read out right after your words.
                """)
            return reply.source == .model ? withQuestion(0, after: reply) : reply
        }
    }

    public func respond(to said: String) async -> Reply {
        let text = said.trimmingCharacters(in: .whitespacesAndNewlines)
        if ReplyRules.containsStopWord(text, language: language) {
            return Reply(say: phrases.stopping, expression: .neutral, source: .stopWord)
        }
        guard !text.isEmpty else {
            return Reply(say: phrases.didNotCatchThat, expression: .thinking, source: .failure("empty input"))
        }
        switch step {
        case .teaching(let point): return await teach(point: point, after: text)
        case .asking(let question): return await check(question: question, answer: text)
        case .finished: return Reply(say: phrases.didNotCatchThat, expression: .thinking, source: .failure("finished"))
        }
    }

    private func teach(point index: Int, after text: String) async -> Reply {
        guard let intent = await checker.intent(of: text, after: points[index]) else { return couldNotCheck }
        switch intent {
        case .help:
            return await say(
                """
                The person asked about this point, or is unsure: \(points[index]) Help with what they said, in plain \
                words and one to three sentences, then check that they follow.
                """, after: text)
        case .next where index + 1 < points.count:
            let reply = await say(
                """
                Say this next point out loud, close to its own words and with its example, then check that they \
                follow: \(points[index + 1])
                """, after: text)
            if reply.source == .model { step = .teaching(point: index + 1) }
            return reply
        case .next:
            let reply = await say(
                """
                Say in one short sentence that \(items.count) short questions come next. Do not ask a question \
                yourself: it is read out right after your words.
                """, after: text)
            guard reply.source == .model else { return reply }
            step = .asking(question: 0)
            return withQuestion(0, after: reply)
        }
    }

    private func check(question index: Int, answer text: String) async -> Reply {
        let item = items[index]
        guard let grade = await checker.grade(text, to: item.question) else { return couldNotCheck }
        guard let verdict = grade.verdict else {
            let reply = await say(
                """
                The person did not answer the question "\(item.question.ask)": they asked for a hint or asked \
                something else. Help briefly without giving the answer, which is: \(item.question.answer) Do not ask \
                a question yourself: the question is read out again after your words.
                """, after: text)
            return reply.source == .model ? withQuestion(index, after: reply) : reply
        }
        let missing = grade.missing.isEmpty ? "" : " What was missing or wrong: \(grade.missing)"
        let reply = await say(
            """
            The person answered the question "\(item.question.ask)". The answer is \(verdict.spoken). The correct \
            answer: \(item.question.answer)\(missing) Tell them kindly and honestly that it is \(verdict.spoken), \
            then say what was missing or the correct answer, in one or two sentences. Do not ask a question \
            yourself: the next one is read out after your words.
            """, after: text)
        guard reply.source == .model else { return reply }
        progress.record(verdict, for: item, at: now())
        if verdict == .correct { correctAnswers += 1 }
        guard index + 1 == items.count else {
            step = .asking(question: index + 1)
            return withQuestion(index + 1, after: reply)
        }
        step = .finished
        if case .lesson(let lesson) = plan {
            progress.finish(lesson, correct: correctAnswers, at: now())
            return extended(reply, with: phrases.lessonFinished(lesson.title, correctAnswers, items.count))
        }
        return extended(reply, with: phrases.reviewFinished(correctAnswers, items.count))
    }

    private var couldNotCheck: Reply {
        Reply(say: phrases.noAnswer, expression: .sad, source: .failure("the checker gave no usable answer"))
    }

    /// The course's own question, word for word, after what the teammate said: a question is never lost, changed or
    /// given away with its answer.
    private func withQuestion(_ index: Int, after reply: Reply) -> Reply {
        extended(reply, with: phrases.question(index + 1, items.count, items[index].question.ask))
    }

    private func extended(_ reply: Reply, with text: String) -> Reply {
        var longer = reply
        longer.say = "\(reply.say) \(text)"
        if !transcript.isEmpty { transcript[transcript.count - 1] = ChatMessage(.assistant, longer.say) }
        return longer
    }

    // MARK: The teammate's voice

    /// Marks the tutor's instructions inside the last user message.
    static let instructionsMarker = "[The tutor's instructions for this reply, not said by the person]"

    static let speakingSchema: JSONValue = [
        "type": "object", "additionalProperties": false, "required": ["expression", "say"],
        "properties": [
            "say": ["type": "string"],
            "expression": ["type": "string", "enum": .array(FaceExpression.allCases.map { .string($0.rawValue) })],
        ],
    ]

    /// One spoken turn in the teammate's voice: the persona and the lesson in the one system message, the lesson so
    /// far, and the person's words with this turn's instructions after them, where a model follows them most closely.
    /// Not a second system message: routers and chat templates may drop every system message but the first
    /// (llm-harness's route to Ollama did).
    private func say(_ instruction: String, after said: String? = nil) async -> Reply {
        let setting = [persona, background, lessonContext].compactMap { $0 }.joined(separator: "\n\n")
        let note = "\(Self.instructionsMarker) \(instruction)"
        let messages =
            [ChatMessage(.system, setting)] + transcript.suffix(Self.contextMessages)
            + [ChatMessage(.user, said.map { "\($0)\n\n\(note)" } ?? note)]
        do {
            let reply = try ReplyRules.reply(
                fromModelAnswer: try await chat.complete(messages, schema: Self.speakingSchema))
            if let said { transcript.append(ChatMessage(.user, said)) }
            transcript.append(ChatMessage(.assistant, reply.say))
            return reply
        } catch {
            return Reply(say: phrases.noAnswer, expression: .sad, source: .failure(String(describing: error)))
        }
    }

    private var lessonContext: String {
        switch plan {
        case .lesson(let lesson):
            "You are teaching the lesson \"\(lesson.title)\" from the course \"\(course.title)\", one point at a "
                + "time. Its goal: \(lesson.goal) Stay on this lesson's topic. Keep each turn short enough to say out "
                + "loud."
        case .review:
            "You are reviewing questions from the course \"\(course.title)\". Stay on these questions. Keep each "
                + "turn short enough to say out loud."
        }
    }
}

extension Verdict {
    /// How the teammate is told to describe the verdict.
    var spoken: String {
        switch self {
        case .correct: "right"
        case .partly: "partly right"
        case .wrong: "not right"
        }
    }
}
