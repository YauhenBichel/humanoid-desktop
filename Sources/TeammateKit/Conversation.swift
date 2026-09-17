import Foundation

/// What the teammate says back, checked before it is shown or spoken.
public struct Reply: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case model
        case stopWord
        case failure(String)  // why there is no answer from the model
    }

    public var say: String
    public var expression: FaceExpression
    public var source: Source
    /// Facts the model noted to remember about the person (at most three per reply).
    public var remember: [String]

    public init(say: String, expression: FaceExpression, source: Source = .model, remember: [String] = []) {
        self.say = say
        self.expression = expression
        self.source = source
        self.remember = remember
    }
}

/// Turns the model's answer into a Reply, and holds the rules a reply must follow.
public enum ReplyRules {
    public static let maximumSpokenCharacters = 400  // three short spoken sentences
    public static let maximumFactsPerReply = 3
    public static let schema: JSONValue = [
        "type": "object",
        "additionalProperties": false,
        "required": ["say", "expression", "remember"],
        "properties": [
            "say": ["type": "string"],
            "expression": ["type": "string", "enum": .array(FaceExpression.allCases.map { .string($0.rawValue) })],
            "remember": ["type": "array", "items": ["type": "string"]],
        ],
    ]

    /// What the model is told about the `remember` field. Without the example, a local model left the list empty
    /// even for "I'm preparing for an interview in November and prefer Python".
    public static let rememberInstruction = """
        Before you finish, fill "remember": the facts from the person's latest message that will still matter in a \
        later conversation (what they study or build, goals and deadlines, languages and tools they prefer, their \
        level). Write each as a short third-person note. Example: for "I'm new to Rust and I have an exam on \
        Friday" remember ["Is new to Rust", "Has an exam on Friday"]. At most three. Never note passwords, keys, \
        addresses, health or money details. Use an empty list when the message tells you nothing lasting about \
        them, such as a plain question.
        """

    public struct UnusableAnswer: Error, Equatable, Sendable, CustomStringConvertible {
        public let description: String
    }

    private struct Payload: Decodable {
        let say: String
        let expression: String?
        let remember: [String]?
    }

    /// English stop words always count; so do those of the answer language.
    public static func containsStopWord(_ text: String, language: Language? = nil) -> Bool {
        let words = text.lowercased().split { !($0.isLetter || $0 == "-") }.map(String.init)
        return !(language ?? .english).stopWords.isDisjoint(with: words)
    }

    /// The spoken text is shortened at a sentence end, and an unknown expression becomes neutral.
    public static func reply(fromModelAnswer answer: String) throws(UnusableAnswer) -> Reply {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(answer.utf8)),
            !payload.say.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw UnusableAnswer(description: "the model gave no spoken answer")
        }
        let expression = payload.expression.flatMap(FaceExpression.init(rawValue:)) ?? .neutral
        let facts = (payload.remember ?? []).prefix(maximumFactsPerReply).map { $0 }
        return Reply(say: trimmedForSpeech(payload.say), expression: expression, remember: facts)
    }

    public static func trimmedForSpeech(_ text: String, limit: Int = maximumSpokenCharacters) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard flat.count > limit else { return flat }
        let cut = String(flat.prefix(limit))
        let sentenceEnds = [". ", "! ", "? "].compactMap { cut.range(of: $0, options: .backwards)?.lowerBound }
        if let end = sentenceEnds.max(), cut.distance(from: cut.startIndex, to: end) > 40 {
            return String(cut[...end])
        }
        return cut.split(separator: " ").dropLast().joined(separator: " ") + "…"
    }
}

public struct ChatMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case system, user, assistant }

    public let role: Role
    public let content: String

    public init(_ role: Role, _ content: String) {
        self.role = role
        self.content = content
    }
}

/// One conversation with one teammate: the persona, what it remembers, the latest messages, and a safe answer when
/// anything fails. Remembering is part of the conversation; saving the memory is the session's job.
public actor Conversation {
    /// Messages kept word for word; older ones are folded into the memory's summary.
    public static let maximumHistory = TeammateMemory.maximumRecentMessages

    public let teammate: Teammate
    public private(set) var memory: TeammateMemory
    private let userName: String
    private let language: Language?
    private let phrases: SessionPhrases
    private let chat: any ChatCompleting

    public var history: [ChatMessage] { memory.recent }

    public init(
        teammate: Teammate,
        userName: String,
        language: Language? = nil,
        phrases: SessionPhrases = .english,
        memory: TeammateMemory = TeammateMemory(),
        chat: any ChatCompleting
    ) {
        self.teammate = teammate
        self.userName = userName
        self.language = language
        self.phrases = phrases
        self.memory = memory
        self.chat = chat
    }

    public func respond(to said: String) async -> Reply {
        let text = said.trimmingCharacters(in: .whitespacesAndNewlines)
        if ReplyRules.containsStopWord(text, language: language) {
            return Reply(say: phrases.stopping, expression: .neutral, source: .stopWord)
        }
        guard !text.isEmpty else {
            return Reply(say: phrases.didNotCatchThat, expression: .thinking, source: .failure("empty input"))
        }
        let messages = [ChatMessage(.system, systemPrompt)] + memory.recent + [ChatMessage(.user, text)]
        do {
            let reply = try ReplyRules.reply(
                fromModelAnswer: try await chat.complete(messages, schema: ReplyRules.schema))
            await remember(said: text, reply: reply)
            return reply
        } catch {
            return Reply(say: phrases.noAnswer, expression: .sad, source: .failure(String(describing: error)))
        }
    }

    var systemPrompt: String {
        let person = userName.isEmpty ? "the person" : userName
        return [
            teammate.persona(userName: userName, language: language),
            memory.promptSection(personName: person),
            ReplyRules.rememberInstruction,
        ].compactMap { $0 }.joined(separator: "\n\n")
    }

    private func remember(said: String, reply: Reply) async {
        memory.learn(reply.remember)
        let answer = #"{"say": \#(jsonString(reply.say)), "expression": "\#(reply.expression.rawValue)"}"#
        memory.recent += [ChatMessage(.user, said), ChatMessage(.assistant, answer)]
        memory.updated = Date()
        if memory.recent.count > Self.maximumHistory {
            await foldOldestMessagesIntoSummary()
        }
    }

    /// Keeps the latest messages word for word and asks the model to fold the older half into the summary. If
    /// that fails, the older messages are dropped: a lost detail is better than a prompt that grows forever.
    private func foldOldestMessagesIntoSummary() async {
        let keep = Self.maximumHistory / 2
        let older = Array(memory.recent.dropLast(keep))
        memory.recent = Array(memory.recent.suffix(keep))
        let transcript = older.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n")
        let instruction = """
            You keep a short summary of earlier conversations between \(teammate.name), a humanoid teammate, and \
            \(userName.isEmpty ? "the person" : userName). Update the summary with the new messages. Keep what \
            helps later conversations: the person's goals, what was explained or practised, open questions. At \
            most \(TeammateMemory.maximumSummaryLength - 200) characters. Never keep passwords, keys, addresses, \
            health or money details. Answer only with the JSON object.
            """
        let request =
            "Current summary: \(memory.summary.isEmpty ? "(none)" : memory.summary)\n\nNew messages:\n\(transcript)"
        let schema: JSONValue = [
            "type": "object", "additionalProperties": false, "required": ["summary"],
            "properties": ["summary": ["type": "string"]],
        ]
        struct Answer: Decodable { let summary: String }
        guard
            let raw = try? await chat.complete(
                [ChatMessage(.system, instruction), ChatMessage(.user, request)], schema: schema),
            let answer = try? JSONDecoder().decode(Answer.self, from: Data(raw.utf8))
        else { return }
        let flat = answer.summary.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        memory.summary = String(flat.prefix(TeammateMemory.maximumSummaryLength))
    }

    private func jsonString(_ text: String) -> String {
        String(decoding: (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8), as: UTF8.self)
    }
}
