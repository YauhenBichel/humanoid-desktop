import Foundation
import Testing

@testable import TeammateKit

// MARK: - Fakes and a small course

/// Progress kept in a dictionary, shared between a test and the session.
final class ProgressShelf: ProgressStore, @unchecked Sendable {
    private let lock = NSLock()
    private var saved: [String: StudyProgress] = [:]

    func load(courseKey: String) throws -> StudyProgress {
        lock.lock()
        defer { lock.unlock() }
        return saved[courseKey] ?? StudyProgress(course: courseKey)
    }

    func save(_ progress: StudyProgress) throws {
        lock.lock()
        defer { lock.unlock() }
        saved[progress.course] = progress
    }

    subscript(key: String) -> StudyProgress? {
        lock.lock()
        defer { lock.unlock() }
        return saved[key]
    }
}

private let graphs = Course.Lesson(
    key: "graphs", title: "Graphs", goal: "Tell BFS from DFS.",
    points: ["BFS uses a queue.", "DFS uses a stack."],
    questions: [
        Course.Question(key: "q1", ask: "What does BFS use?", answer: "A queue."),
        Course.Question(key: "q2", ask: "What does DFS use?", answer: "A stack."),
    ])
private let sorting = Course.Lesson(
    key: "sorting", title: "Sorting", goal: "Pick a sort.", points: ["Merge sort is stable."],
    questions: [Course.Question(key: "q1", ask: "Is merge sort stable?", answer: "Yes.")])
let tinyCourse = Course(key: "tiny", title: "Tiny course", lessons: [graphs, sorting])

/// A tutor's model. As the checker: "why" asks for help, anything else goes on; "queue" and "stack" are right answers,
/// "hint" is no answer. As the teammate: says which job it was given.
let scriptedTutorChat = CannedChat { messages in
    let system = messages.first?.content ?? ""
    let last = messages.last?.content ?? ""
    if system.contains("You read a learner's reply") {
        return #"{"intent": "\#(last.contains("why") ? "help" : "next")"}"#
    }
    if system.contains("You check a learner's spoken answer") {
        let answer = last.components(separatedBy: "Learner's answer: ").last ?? ""
        let verdict =
            answer.contains("hint")
            ? "not_an_answer" : (answer.contains("queue") || answer.contains("stack")) ? "correct" : "wrong"
        return #"{"verdict": "\#(verdict)", "missing": "\#(verdict == "wrong" ? "It is a stack." : "")"}"#
    }
    let say =
        if let verdict = Verdict.allCases.first(where: { last.contains("The answer is \($0.spoken).") }) {
            "Judged \(verdict.rawValue)."
        } else if last.contains("did not answer the question") {
            "Here is a hint."
        } else if last.contains("is unsure") {
            "Let me help."
        } else if last.contains("Say this next point") || last.contains("questions come next") {
            "Moving on."
        } else {
            "Let's start."
        }
    return #"{"say": "\#(say)", "expression": "happy"}"#
}

// MARK: - Courses

@Suite struct CourseTests {
    @Test func theBuiltInCourseIsWholeAndCheckable() throws {
        let course = try #require(CourseCatalog.builtIn.course(key: "cs-foundations"))
        #expect(course.lessons.count == 8)
        #expect(course.lessons.allSatisfy { $0.questions.count == 3 && $0.points.count >= 3 })
        #expect(Teammate.byte.course == "cs-foundations" && Teammate.tempo.course == nil)
    }

    @Test func aBrokenCourseNamesItsProblem() {
        var twins = tinyCourse
        twins.lessons[1].key = "graphs"
        #expect(throws: CourseError(message: "two lessons have the same key")) { try twins.check() }
        var silent = tinyCourse
        silent.lessons[0].points = []
        #expect(throws: CourseError.self) { try silent.check() }
        #expect(throws: CourseError.self) { try Course.decode(Data(#"{"key": "x"}"#.utf8)) }
    }

    @Test func ownCoursesLoadBesideTheBuiltInOnesAndBrokenFilesAreReported() throws {
        let folder = temporaryFolder()
        try JSONEncoder().encode(tinyCourse).write(to: folder.appendingPathComponent("tiny.json"))
        try JSONEncoder().encode(tinyCourse).write(to: folder.appendingPathComponent("other-name.json"))
        try Data("{".utf8).write(to: folder.appendingPathComponent("broken.json"))
        let catalog = CourseCatalog.load(directory: folder)
        #expect(catalog.course(key: "tiny") == tinyCourse && catalog.course(key: "cs-foundations") != nil)
        #expect(catalog.problems.count == 2)
        #expect(catalog.problems.contains { $0.contains("other-name.json") && $0.contains("tiny.json") })
    }

    @Test func aTeammateFileNamesItsCourse() throws {
        let folder = temporaryFolder()
        let nova = folder.appendingPathComponent("nova.toml")
        try "course = \"tiny\"\n".write(to: nova, atomically: true, encoding: .utf8)
        #expect(try TeammateFile.load(nova).course == "tiny")
        let quiet = folder.appendingPathComponent("byte.toml")
        try "course = \"\"\n".write(to: quiet, atomically: true, encoding: .utf8)
        #expect(try TeammateFile.load(quiet).course == nil)
    }

    @Test func aTeammateWhoseCourseIsMissingIsReported() throws {
        let folder = temporaryFolder()
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("teammates"), withIntermediateDirectories: true)
        try "course = \"astronomy\"\n".write(
            to: folder.appendingPathComponent("teammates/nova.toml"), atomically: true, encoding: .utf8)
        let library = TeammateLibrary.load(environment: ["HUMANOID_CONFIG_DIR": folder.path])
        #expect(library.problems.contains("Nova: no course named astronomy"))
    }
}

// MARK: - Progress

@Suite struct StudyProgressTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let item = StudyItem(lesson: graphs, question: graphs.questions[0])

    @Test func rightAnswersComeBackLaterAndWrongOnesSoon() throws {
        var progress = StudyProgress(course: "tiny")
        progress.record(.correct, for: item, at: start)
        #expect(progress.questions["graphs/q1"]?.box == 1)
        #expect(progress.questions["graphs/q1"]?.due == start.addingTimeInterval(StudyProgress.day))
        progress.record(.correct, for: item, at: start)
        #expect(progress.questions["graphs/q1"]?.due == start.addingTimeInterval(3 * StudyProgress.day))
        progress.record(.partly, for: item, at: start)
        #expect(progress.questions["graphs/q1"]?.box == 2)
        #expect(progress.questions["graphs/q1"]?.due == start.addingTimeInterval(StudyProgress.day))
        progress.record(.wrong, for: item, at: start)
        let answered = try #require(progress.questions["graphs/q1"])
        #expect(answered.box == 0 && answered.due == start.addingTimeInterval(600) && answered.times == 4)
    }

    @Test func dueQuestionsComeLongestOverdueFirst() {
        var progress = StudyProgress(course: "tiny")
        progress.record(.wrong, for: StudyItem(lesson: graphs, question: graphs.questions[1]), at: start)
        progress.record(.wrong, for: item, at: start.addingTimeInterval(-60))
        progress.record(.correct, for: StudyItem(lesson: sorting, question: sorting.questions[0]), at: start)
        let due = progress.due(in: tinyCourse, at: start.addingTimeInterval(700))
        #expect(due.map(\.question.ask) == ["What does BFS use?", "What does DFS use?"])
        #expect(progress.due(in: tinyCourse, at: start).isEmpty)
    }

    @Test func theNextLessonAndThePromptFollowWhatWasFinished() throws {
        var progress = StudyProgress(course: "tiny")
        #expect(progress.nextLesson(in: tinyCourse) == graphs)
        #expect(progress.promptSection(course: tinyCourse, at: start) == nil)
        progress.finish(graphs, correct: 1, at: start)
        #expect(progress.nextLesson(in: tinyCourse) == sorting)
        let section = try #require(progress.promptSection(course: tinyCourse, at: start))
        #expect(section.contains("Graphs (1 of 2 right)") && section.contains("next lesson is \"Sorting\""))
    }

    @Test func aFileStoreKeepsProgressPrivate() throws {
        let store = FileProgressStore(folder: temporaryFolder().appendingPathComponent("progress"))
        #expect(try store.load(courseKey: "tiny") == StudyProgress(course: "tiny"))
        var progress = StudyProgress(course: "tiny")
        progress.record(.correct, for: item, at: start)
        try store.save(progress)
        #expect(try store.load(courseKey: "tiny") == progress)
        let file = store.folder.appendingPathComponent("tiny.json")
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
    }
}

// MARK: - Tutor

@Suite struct TutorTests {
    private func tutor(_ plan: Tutor.Plan, chat: CannedChat = scriptedTutorChat) -> Tutor {
        Tutor(
            course: tinyCourse, plan: plan, progress: StudyProgress(course: "tiny"), persona: "You are Byte.",
            chat: chat, now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }

    @Test func aLessonTeachesEachPointThenAsksAndScores() async {
        let tutor = tutor(.lesson(graphs))
        #expect(await tutor.begin().say == "Let's start.")
        #expect(await tutor.step == .teaching(point: 0))
        _ = await tutor.respond(to: "why a queue?")
        #expect(await tutor.step == .teaching(point: 0))  // a question keeps the point
        _ = await tutor.respond(to: "got it")
        #expect(await tutor.step == .teaching(point: 1))
        #expect(await tutor.respond(to: "ok").say == "Moving on. Question 1 of 2: What does BFS use?")
        #expect(await tutor.step == .asking(question: 0))

        #expect(await tutor.respond(to: "a hint please").say.hasSuffix("Question 1 of 2: What does BFS use?"))
        #expect(await tutor.step == .asking(question: 0))
        #expect(await tutor.progress.questions.isEmpty)
        _ = await tutor.respond(to: "a queue")
        #expect(await tutor.step == .asking(question: 1))
        let last = await tutor.respond(to: "a heap?")
        #expect(await tutor.isFinished)
        #expect(last.say == "Judged wrong. Lesson Graphs done: 1 of 2 right.")
        let progress = await tutor.progress
        #expect(progress.lessons["graphs"]?.correct == 1 && progress.questions["graphs/q2"]?.last == .wrong)
    }

    @Test func onlyThePersonaFreeCheckerDecides() async {
        let prompts = Box<[[ChatMessage]]>()
        let chat = CannedChat { messages in
            prompts.value = (prompts.value ?? []) + [messages]
            return try scriptedTutorChat.answer(messages)
        }
        let tutor = tutor(.lesson(graphs), chat: chat)
        _ = await tutor.begin()
        _ = await tutor.respond(to: "ok")
        _ = await tutor.respond(to: "ok")
        _ = await tutor.respond(to: "a queue")
        let sent = prompts.value ?? []
        let checks = sent.filter { $0.first?.content.contains("a learner's") == true }
        #expect(sent.count == 7)
        #expect(checks.count == 3)  // begin; two points and an answer, each checked, then said
        #expect(checks.allSatisfy { !$0.contains { $0.content.contains("You are Byte.") } })
        #expect(checks.last?.last?.content.contains("Correct answer: A queue.") == true)
        let spokenBeforeAnswering = sent.filter { $0.first?.content.hasPrefix("You are Byte.") == true }.prefix(3)
        #expect(spokenBeforeAnswering.allSatisfy { !$0.contains { $0.content.contains("orrect answer") } })
        // Only the first message is a system message: routers may drop the others.
        #expect(sent.allSatisfy { $0.dropFirst().allSatisfy { $0.role != .system } })
    }

    @Test func stopWordsAndFailuresKeepTheLessonWhereItWas() async {
        let failing = CannedChat { _ in throw ServerError.status(url: nil, statusCode: 500, body: "") }
        let tutor = tutor(.lesson(graphs), chat: failing)
        #expect(await tutor.respond(to: "stop").source == .stopWord)
        let reply = await tutor.respond(to: "ok")
        #expect(reply.say == SessionPhrases.english.noAnswer)
        #expect(await tutor.step == .teaching(point: 0))
    }

    @Test func aReviewAsksOnlyTheDueQuestions() async {
        let due = [StudyItem(lesson: graphs, question: graphs.questions[1])]
        let review = tutor(.review(due))
        #expect(await review.step == .asking(question: 0))
        #expect(await review.begin().say == "Let's start. Question 1 of 1: What does DFS use?")
        #expect(await review.respond(to: "a stack").say == "Judged correct. Review done: 1 of 1 right.")
        #expect(await review.progress.lessons.isEmpty)

        let nothing = tutor(.review([]))
        #expect(await nothing.begin().say == SessionPhrases.english.nothingToReview)
        #expect(await nothing.isFinished)
    }
}

// MARK: - Session

@MainActor
@Suite struct SessionStudyTests {
    private func session(progress: ProgressShelf, chat: CannedChat = scriptedTutorChat) -> TeammateSession {
        let session = TeammateSession(
            player: FakePlayer(), recorder: FakeRecorder(), choices: MemoryChoices(), memories: MemoryShelf(),
            progressStore: progress
        ) { _ in
            .init(chat: chat, speech: FixedSpeech(), transcription: FixedTranscription())
        }
        let folder = temporaryFolder()
        let byteFile = folder.appendingPathComponent("byte.toml")
        try? "course = \"tiny\"\n".write(to: byteFile, atomically: true, encoding: .utf8)
        session.configure(
            with: TeammateLibrary(
                settings: .defaults, catalog: TeammateCatalog.load(directory: folder),
                courses: CourseCatalog.load(directory: coursesFolder()), problems: []))
        return session
    }

    private func coursesFolder() -> URL {
        let folder = temporaryFolder()
        try? JSONEncoder().encode(tinyCourse).write(to: folder.appendingPathComponent("tiny.json"))
        return folder
    }

    private func settle(_ session: TeammateSession, until done: () -> Bool) async {
        for _ in 0..<400 where !done() || session.activity != .idle {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func aWholeLessonIsTaughtShownAndSaved() async {
        let shelf = ProgressShelf()
        let session = session(progress: shelf)
        #expect(session.course == tinyCourse)
        session.startLesson()
        await settle(session) { session.study != nil }
        #expect(session.study == .init(lessonTitle: "Graphs", question: nil, questionCount: 2))
        for said in ["ok", "ok"] {
            session.send(said)
            await settle(session) { session.bubble.hasPrefix("Moving on.") }
        }
        #expect(session.study?.question == 1)
        session.send("a queue")
        await settle(session) { session.study?.question == 2 }
        #expect(shelf["tiny"]?.questions["graphs/q1"]?.last == .correct)
        session.send("a stack")
        await settle(session) { session.study == nil }
        #expect(shelf["tiny"]?.lessons["graphs"]?.correct == 2)
        #expect(session.bubble.hasSuffix("Lesson Graphs done: 2 of 2 right."))
        #expect(session.progress?.nextLesson(in: tinyCourse) == sorting)
    }

    @Test func afterALessonTheTeammateKnowsHowItWent() async {
        let shelf = ProgressShelf()
        var finished = StudyProgress(course: "tiny")
        finished.finish(graphs, correct: 2, at: Date())
        try? shelf.save(finished)
        let prompts = Box<String>()
        let chat = CannedChat { messages in
            prompts.value = messages.first?.content
            return #"{"say": "Hi.", "expression": "happy", "remember": []}"#
        }
        let session = session(progress: shelf, chat: chat)
        session.send("hello")
        await settle(session) { session.bubble == "Hi." }
        #expect(prompts.value?.contains("Graphs (2 of 2 right)") == true)
    }

    @Test func endingALessonReturnsToTalking() async {
        let session = session(progress: ProgressShelf())
        session.startLesson()
        await settle(session) { session.study != nil }
        session.endStudy()
        #expect(session.study == nil && session.bubble == SessionPhrases.english.studyEnded)
    }

    @Test func aFinishedCourseSaysSoAndATeammateWithoutOneHasNoLessons() {
        let shelf = ProgressShelf()
        var done = StudyProgress(course: "tiny")
        done.finish(graphs, correct: 2, at: Date())
        done.finish(sorting, correct: 1, at: Date())
        try? shelf.save(done)
        let session = session(progress: shelf)
        session.startLesson()
        #expect(session.bubble == SessionPhrases.english.courseFinished("Tiny course"))
        session.choose(.tempo)
        #expect(session.course == nil && session.progress == nil)
        session.startLesson()
        #expect(session.study == nil)
    }
}
