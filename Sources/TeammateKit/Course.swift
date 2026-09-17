import Foundation

/// A course a teammate teaches: lessons taught point by point, each ending with short questions the person answers
/// out loud. A course is a JSON file, so humanoid-companion and people writing their own can read it:
///
///     <settings folder>/courses/<course key>.json
///
/// A teammate teaches the course its file names (`course = "cs-foundations"`); Byte teaches the built-in one.
public struct Course: Codable, Equatable, Sendable, Identifiable {
    public struct Lesson: Codable, Equatable, Sendable, Identifiable {
        public var key: String
        public var title: String
        /// What the person can do after the lesson, in one sentence.
        public var goal: String
        /// Taught in order, one spoken turn each.
        public var points: [String]
        public var questions: [Question]

        public var id: String { key }
    }

    public struct Question: Codable, Equatable, Sendable {
        public var key: String
        public var ask: String
        /// The correct answer, used to judge what the person said and to explain a miss.
        public var answer: String
    }

    public static let maximumQuestionsPerLesson = 10

    public var key: String
    public var title: String
    public var lessons: [Lesson]

    public var id: String { key }

    public func lesson(key: String) -> Lesson? {
        lessons.first { $0.key == key }
    }

    /// Decodes and checks a course, naming the first problem.
    public static func decode(_ data: Data) throws(CourseError) -> Course {
        let course: Course
        do {
            course = try JSONDecoder().decode(Course.self, from: data)
        } catch {
            throw CourseError(message: "not a course: \(error)")
        }
        try course.check()
        return course
    }

    func check() throws(CourseError) {
        func blank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard PrivateJSONFiles.isKey(key) else {
            throw CourseError(message: "key must be lowercase letters, digits and hyphens")
        }
        guard !blank(title) else { throw CourseError(message: "the course needs a title") }
        guard !lessons.isEmpty else { throw CourseError(message: "the course needs at least one lesson") }
        guard Set(lessons.map(\.key)).count == lessons.count else {
            throw CourseError(message: "two lessons have the same key")
        }
        for lesson in lessons {
            let place = "lesson \(lesson.key)"
            guard PrivateJSONFiles.isKey(lesson.key) else {
                throw CourseError(message: "\(place): key must be lowercase letters, digits and hyphens")
            }
            guard !blank(lesson.title), !blank(lesson.goal) else {
                throw CourseError(message: "\(place): needs a title and a goal")
            }
            guard !lesson.points.isEmpty, !lesson.points.contains(where: blank) else {
                throw CourseError(message: "\(place): needs at least one point, and no empty ones")
            }
            guard (1...Self.maximumQuestionsPerLesson).contains(lesson.questions.count) else {
                throw CourseError(message: "\(place): needs 1 to \(Self.maximumQuestionsPerLesson) questions")
            }
            guard Set(lesson.questions.map(\.key)).count == lesson.questions.count else {
                throw CourseError(message: "\(place): two questions have the same key")
            }
            for question in lesson.questions {
                guard PrivateJSONFiles.isKey(question.key), !blank(question.ask), !blank(question.answer) else {
                    throw CourseError(message: "\(place), question \(question.key): needs a key, ask and answer")
                }
            }
        }
    }
}

public struct CourseError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

/// The courses teammates can teach: the built-in ones, then your own files from `<settings folder>/courses`.
public struct CourseCatalog: Equatable, Sendable {
    public private(set) var courses: [Course]
    /// Files that could not be used, each naming the file and the problem; the other courses still load.
    public private(set) var problems: [String]

    public static let builtIn = CourseCatalog(courses: [Course.bundled("cs-foundations")], problems: [])

    public func course(key: String) -> Course? {
        courses.first { $0.key == key }
    }

    /// The built-in courses and every `*.json` in `directory`. A file's name is its course's key, and a file named
    /// after a built-in course replaces it.
    public static func load(directory: URL) -> CourseCatalog {
        var catalog = builtIn
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: {
            $0.lastPathComponent < $1.lastPathComponent
        }) {
            do {
                let course = try Course.decode(Data(contentsOf: file))
                guard course.key == file.deletingPathExtension().lastPathComponent else {
                    throw CourseError(message: "the file name must be the course key, \(course.key).json")
                }
                catalog.add(course)
            } catch {
                catalog.problems.append("\(file.path): \(error)")
            }
        }
        return catalog
    }

    private mutating func add(_ course: Course) {
        if let existing = courses.firstIndex(where: { $0.key == course.key }) {
            courses[existing] = course
        } else {
            courses.append(course)
        }
    }
}

extension Course {
    /// A course shipped inside TeammateKit. Its tests decode every bundled course, so a broken one never ships.
    static func bundled(_ key: String) -> Course {
        guard let file = Bundle.teammateKit.url(forResource: key, withExtension: "json", subdirectory: "Courses"),
            let data = try? Data(contentsOf: file)
        else {
            preconditionFailure("TeammateKit is missing its course \(key).json")
        }
        do {
            return try decode(data)
        } catch {
            preconditionFailure("TeammateKit's course \(key).json is broken: \(error)")
        }
    }
}
