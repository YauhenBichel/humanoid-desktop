import Foundation

/// How an answer to a question was judged.
public enum Verdict: String, Codable, CaseIterable, Sendable {
    case correct, partly, wrong
}

/// A question to ask, with the lesson it belongs to.
public struct StudyItem: Equatable, Sendable {
    public let lesson: Course.Lesson
    public let question: Course.Question
}

/// What the person has learned in one course: finished lessons, and when each question they answered comes back.
///
/// Questions come back on a Leitner schedule: a wrong answer returns in ten minutes and goes back to the first box;
/// a right one moves a box further, so it returns after a day, then 3, 7 and 21 days; a partly right one stays in
/// its box and returns tomorrow. Stored as `<settings folder>/progress/<course key>.json`, shared by every teammate
/// that teaches the course, because the progress is the person's.
public struct StudyProgress: Codable, Equatable, Sendable {
    public struct Answered: Codable, Equatable, Sendable {
        public var box: Int
        public var due: Date
        public var last: Verdict
        public var times: Int
    }

    public struct Finished: Codable, Equatable, Sendable {
        public var date: Date
        public var correct: Int
        public var total: Int
    }

    public static let formatVersion = 1
    static let day: TimeInterval = 24 * 60 * 60
    /// How long until a question comes back, by box.
    static let intervals: [TimeInterval] = [10 * 60, day, 3 * day, 7 * day, 21 * day]
    public static let reviewSize = 5

    public var version = formatVersion
    public var course: String
    /// By `<lesson key>/<question key>`.
    public var questions: [String: Answered] = [:]
    /// By lesson key; the latest time the lesson was finished.
    public var lessons: [String: Finished] = [:]

    public init(course: String) {
        self.course = course
    }

    public mutating func record(_ verdict: Verdict, for item: StudyItem, at now: Date) {
        let id = Self.id(item)
        let previous = questions[id]
        let box =
            switch verdict {
            case .correct: min((previous?.box ?? 0) + 1, Self.intervals.count - 1)
            case .partly: previous?.box ?? 0
            case .wrong: 0
            }
        let wait = verdict == .partly ? Self.day : Self.intervals[box]
        questions[id] = Answered(
            box: box, due: now.addingTimeInterval(wait), last: verdict, times: (previous?.times ?? 0) + 1)
    }

    public mutating func finish(_ lesson: Course.Lesson, correct: Int, at now: Date) {
        lessons[lesson.key] = Finished(date: now, correct: correct, total: lesson.questions.count)
    }

    /// The first lesson not finished yet, or nil when every lesson is.
    public func nextLesson(in course: Course) -> Course.Lesson? {
        course.lessons.first { lessons[$0.key] == nil }
    }

    /// Questions already answered that are due again, the longest overdue first.
    public func due(in course: Course, at now: Date, limit: Int = reviewSize) -> [StudyItem] {
        let items = course.lessons.flatMap { lesson in
            lesson.questions.map { StudyItem(lesson: lesson, question: $0) }
        }
        return
            items
            .compactMap { item in questions[Self.id(item)].map { (item, $0.due) } }
            .filter { $0.1 <= now }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// The part of the chat prompt that tells the teammate how the person is doing, or nil before the first lesson.
    public func promptSection(course: Course, at now: Date) -> String? {
        let finished = course.lessons.compactMap { lesson in
            lessons[lesson.key].map { "\(lesson.title) (\($0.correct) of \($0.total) right)" }
        }
        guard !finished.isEmpty else { return nil }
        var lines = [
            "Lessons from your course \"\(course.title)\" finished together: \(finished.joined(separator: "; "))."
        ]
        if let next = nextLesson(in: course) {
            lines.append("The next lesson is \"\(next.title)\".")
        }
        let dueCount = due(in: course, at: now, limit: .max).count
        if dueCount > 0 {
            lines.append("\(dueCount) questions are due for review; you may suggest a review when it fits.")
        }
        return lines.joined(separator: " ")
    }

    static func id(_ item: StudyItem) -> String { "\(item.lesson.key)/\(item.question.key)" }
}

/// Keeps what the person has learned, per course.
public protocol ProgressStore: Sendable {
    func load(courseKey: String) throws -> StudyProgress
    func save(_ progress: StudyProgress) throws
}

/// Progress as one JSON file per course, readable only by the owner of the account.
public struct FileProgressStore: ProgressStore {
    private let files: PrivateJSONFiles

    public var folder: URL { files.folder }

    public init(folder: URL) {
        files = PrivateJSONFiles(folder: folder)
    }

    /// `<settings folder>/progress`.
    public static func standard(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> FileProgressStore {
        FileProgressStore(folder: TeammateLibrary.folder(environment: environment).appendingPathComponent("progress"))
    }

    public func load(courseKey: String) throws -> StudyProgress {
        guard let progress = try files.read(StudyProgress.self, key: courseKey) else {
            return StudyProgress(course: courseKey)
        }
        guard progress.version <= StudyProgress.formatVersion else {
            throw StoreError(
                description:
                    "\(try files.url(for: courseKey).path) was written by a newer version (\(progress.version))")
        }
        return progress
    }

    public func save(_ progress: StudyProgress) throws {
        try files.write(progress, key: progress.course)
    }
}
