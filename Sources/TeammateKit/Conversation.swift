import Foundation

/// What the teammate says back, checked before it is shown or spoken.
public struct Reply: Equatable {
    public enum Source: String { case model, stopWord = "stop-word", fallback }

    public var say: String
    public var expression: FaceExpression
    public var source: Source = .model
    public var error: String = ""

    public static let maximumSpoken = 400  // characters: three short spoken sentences
}

/// Anything that answers a list of chat messages with a JSON string matching a schema. The real one is
/// ChatClient; tests pass a closure.
public protocol ChatCompleting {
    func complete(messages: [[String: String]], schema: [String: Any]) async throws -> String
}

public enum ReplyParsing {
    public static let stopWords: Set<String> = ["stop", "halt", "freeze", "estop", "e-stop", "quiet", "shush"]

    public static var schema: [String: Any] {
        [
            "type": "object", "additionalProperties": false, "required": ["say", "expression"],
            "properties": [
                "say": ["type": "string"],
                "expression": ["type": "string", "enum": FaceExpression.allCases.map(\.rawValue)],
            ],
        ]
    }

    public static func hasStopWord(_ text: String) -> Bool {
        let words = text.lowercased().split(whereSeparator: { !($0.isLetter || $0 == "-") }).map(String.init)
        return !stopWords.isDisjoint(with: words)
    }

    /// The model's JSON answer as a Reply. The spoken text is shortened at a sentence end; an unknown
    /// expression becomes neutral; an empty or non-JSON answer is an error.
    public static func parse(_ raw: String) throws -> Reply {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let say = object["say"] as? String, !say.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw TeammateError(message: "the model gave no spoken answer")
        }
        let expression = (object["expression"] as? String).flatMap(FaceExpression.init(rawValue:)) ?? .neutral
        return Reply(say: trimSpoken(say), expression: expression)
    }

    public static func trimSpoken(_ text: String, limit: Int = Reply.maximumSpoken) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard flat.count > limit else { return flat }
        let cut = String(flat.prefix(limit))
        let sentenceEnds = [". ", "! ", "? "].compactMap { cut.range(of: $0, options: .backwards)?.lowerBound }
        if let end = sentenceEnds.max(), cut.distance(from: cut.startIndex, to: end) > 40 {
            return String(cut[...end])
        }
        return (cut.split(separator: " ").dropLast().joined(separator: " ")) + "…"
    }
}

/// One conversation with a teammate: the persona, the recent messages, and safe answers when anything fails.
public final class Conversation {
    public static let maximumHistory = 12  // messages kept: six exchanges

    public private(set) var history: [[String: String]] = []
    public let teammate: Teammate
    private let userName: String
    private let chat: ChatCompleting

    public init(teammate: Teammate, userName: String, chat: ChatCompleting) {
        (self.teammate, self.userName, self.chat) = (teammate, userName, chat)
    }

    public func respond(to said: String) async -> Reply {
        let text = said.trimmingCharacters(in: .whitespacesAndNewlines)
        if ReplyParsing.hasStopWord(text) {
            return Reply(say: "Okay, I'll be quiet.", expression: .neutral, source: .stopWord)
        }
        guard !text.isEmpty else {
            return Reply(say: "Sorry, I did not catch that.", expression: .thinking, source: .fallback, error: "empty input")
        }
        let messages = [["role": "system", "content": teammate.persona(userName: userName)]] + history
            + [["role": "user", "content": text]]
        do {
            let reply = try ReplyParsing.parse(try await chat.complete(messages: messages, schema: ReplyParsing.schema))
            let remembered = try JSONSerialization.data(withJSONObject: ["say": reply.say, "expression": reply.expression.rawValue])
            history += [["role": "user", "content": text], ["role": "assistant", "content": String(decoding: remembered, as: UTF8.self)]]
            history = Array(history.suffix(Self.maximumHistory))
            return reply
        } catch {
            return Reply(say: "Sorry, I could not think of an answer just now.", expression: .sad, source: .fallback, error: "\(error)")
        }
    }
}
