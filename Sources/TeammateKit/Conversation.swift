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

    public init(say: String, expression: FaceExpression, source: Source = .model) {
        self.say = say
        self.expression = expression
        self.source = source
    }
}

/// Turns the model's answer into a Reply, and holds the rules a reply must follow.
public enum ReplyRules {
    public static let maximumSpokenCharacters = 400  // three short spoken sentences
    public static let schema: JSONValue = [
        "type": "object",
        "additionalProperties": false,
        "required": ["say", "expression"],
        "properties": [
            "say": ["type": "string"],
            "expression": ["type": "string", "enum": .array(FaceExpression.allCases.map { .string($0.rawValue) })],
        ],
    ]

    public struct UnusableAnswer: Error, Equatable, Sendable, CustomStringConvertible {
        public let description: String
    }

    private struct Payload: Decodable {
        let say: String
        let expression: String?
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
        return Reply(say: trimmedForSpeech(payload.say), expression: expression)
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

/// One conversation with one teammate: the persona, the recent messages, and a safe answer when anything fails.
public actor Conversation {
    public static let maximumHistory = 12  // messages kept: six exchanges

    public let teammate: Teammate
    public private(set) var history: [ChatMessage] = []
    private let userName: String
    private let chat: any ChatCompleting

    private let language: Language?
    private let phrases: SessionPhrases

    public init(
        teammate: Teammate,
        userName: String,
        language: Language? = nil,
        phrases: SessionPhrases = .english,
        chat: any ChatCompleting
    ) {
        self.teammate = teammate
        self.userName = userName
        self.language = language
        self.phrases = phrases
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
        let persona = teammate.persona(userName: userName, language: language)
        let messages = [ChatMessage(.system, persona)] + history + [ChatMessage(.user, text)]
        do {
            let reply = try ReplyRules.reply(
                fromModelAnswer: try await chat.complete(messages, schema: ReplyRules.schema))
            remember(said: text, reply: reply)
            return reply
        } catch {
            return Reply(say: phrases.noAnswer, expression: .sad, source: .failure(String(describing: error)))
        }
    }

    private func remember(said: String, reply: Reply) {
        let answer = #"{"say": \#(jsonString(reply.say)), "expression": "\#(reply.expression.rawValue)"}"#
        history += [ChatMessage(.user, said), ChatMessage(.assistant, answer)]
        history = Array(history.suffix(Self.maximumHistory))
    }

    private func jsonString(_ text: String) -> String {
        String(decoding: (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8), as: UTF8.self)
    }
}
