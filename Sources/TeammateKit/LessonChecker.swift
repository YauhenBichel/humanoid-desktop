import Foundation

/// The decisions a lesson needs, made by the chat model with no persona and one narrow question each, so the
/// answers are strict and easy to check: does the person follow, and is their answer right?
struct LessonChecker: Sendable {
    enum Intent: String, CaseIterable, Sendable {
        /// They follow, agree or want to go on.
        case next
        /// They ask something, are confused or disagree.
        case help
    }

    struct Grade: Equatable, Sendable {
        /// Nil when the person did not answer: they asked for a hint or something else.
        var verdict: Verdict?
        /// What the answer lacks or gets wrong; empty when it is correct.
        var missing: String
    }

    static let notAnAnswer = "not_an_answer"

    let chat: any ChatCompleting

    /// What the person means after a point was taught; nil when the model gave no usable answer.
    func intent(of reply: String, after point: String) async -> Intent? {
        let instruction = """
            You read a learner's reply during a lesson. intent: "next" when they follow, agree or want to go on \
            (for example "ok", "got it", "makes sense", "next"); "help" when they ask a question, say they are \
            confused, or disagree. Answer only with the JSON object.
            """
        struct Answer: Decodable { let intent: String }
        let schema: JSONValue = [
            "type": "object", "additionalProperties": false, "required": ["intent"],
            "properties": ["intent": ["type": "string", "enum": .array(Intent.allCases.map { .string($0.rawValue) })]],
        ]
        let request = "The tutor just explained: \(point)\nLearner's reply: \(reply)"
        let answer: Answer? = await ask(instruction, request, schema: schema)
        return answer.flatMap { Intent(rawValue: $0.intent) }
    }

    /// The person's answer judged against the course's correct answer; nil when the model gave no usable answer.
    func grade(_ answer: String, to question: Course.Question) async -> Grade? {
        let instruction = """
            You check a learner's spoken answer to a quiz question against the correct answer. Informal wording and \
            small slips of speech are fine. verdict: "correct" when the answer has the key idea of the correct \
            answer; "partly" when it has part of the key idea but misses something important; "wrong" when it does \
            not have the key idea, describes something else or the opposite (even if that is true of something \
            else), or says they do not know; "not_an_answer" when the learner asks for a hint or asks something \
            else. missing: in one short sentence, what the answer lacks or gets wrong, or "" when it is correct. Be \
            strict and fair; do not reward effort. Answer only with the JSON object.
            """
        struct Answer: Decodable {
            let verdict: String
            let missing: String
        }
        let verdicts = Verdict.allCases.map(\.rawValue) + [Self.notAnAnswer]
        let schema: JSONValue = [
            "type": "object", "additionalProperties": false, "required": ["missing", "verdict"],
            "properties": [
                "verdict": ["type": "string", "enum": .array(verdicts.map { .string($0) })],
                "missing": ["type": "string"],
            ],
        ]
        let request = "Question: \(question.ask)\nCorrect answer: \(question.answer)\nLearner's answer: \(answer)"
        guard let result: Answer = await ask(instruction, request, schema: schema) else { return nil }
        if result.verdict == Self.notAnAnswer { return Grade(verdict: nil, missing: "") }
        guard let verdict = Verdict(rawValue: result.verdict) else { return nil }
        return Grade(verdict: verdict, missing: verdict == .correct ? "" : result.missing)
    }

    private func ask<Answer: Decodable>(_ instruction: String, _ request: String, schema: JSONValue) async -> Answer? {
        guard
            let raw = try? await chat.complete(
                [ChatMessage(.system, instruction), ChatMessage(.user, request)], schema: schema)
        else { return nil }
        return try? JSONDecoder().decode(Answer.self, from: Data(raw.utf8))
    }
}
