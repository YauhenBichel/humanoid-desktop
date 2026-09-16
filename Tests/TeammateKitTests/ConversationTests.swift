import Foundation
import Testing

@testable import TeammateKit

/// A chat server that always gives the same answer, or fails.
struct CannedChat: ChatCompleting {
    let answer: @Sendable ([ChatMessage]) throws -> String

    init(_ answer: @escaping @Sendable ([ChatMessage]) throws -> String) {
        self.answer = answer
    }

    init(say: String, expression: String = "happy") {
        self.answer = { _ in #"{"say": "\#(say)", "expression": "\#(expression)"}"# }
    }

    func complete(_ messages: [ChatMessage], schema: JSONValue) async throws -> String {
        try answer(messages)
    }
}

@Suite struct ConversationTests {
    @Test func aReplyIsCheckedAndRemembered() async {
        let conversation = Conversation(
            teammate: .byte, userName: "Alex", chat: CannedChat(say: "A stack is last in, first out."))
        let reply = await conversation.respond(to: "what is a stack?")
        #expect(reply == Reply(say: "A stack is last in, first out.", expression: .happy))
        let history = await conversation.history
        #expect(history.map(\.role) == [.user, .assistant] && history[0].content == "what is a stack?")
    }

    @Test func theModelSeesThePersonaThenTheHistory() async {
        let seen = Box<[ChatMessage]>()
        let conversation = Conversation(
            teammate: .tempo, userName: "",
            chat: CannedChat { messages in
                seen.value = messages
                return #"{"say": "Sure.", "expression": "neutral"}"#
            })
        _ = await conversation.respond(to: "first")
        _ = await conversation.respond(to: "second")
        #expect(seen.value?.map(\.role) == [.system, .user, .assistant, .user])
        #expect(seen.value?.first?.content.hasPrefix("You are Tempo, a humanoid teammate") == true)
    }

    @Test func historyIsBounded() async {
        let conversation = Conversation(teammate: .byte, userName: "", chat: CannedChat(say: "Sure."))
        for index in 0..<10 { _ = await conversation.respond(to: "question \(index)") }
        let history = await conversation.history
        #expect(history.count == Conversation.maximumHistory && history[history.count - 2].content == "question 9")
    }

    @Test(arguments: ["stop", "Please be quiet", "halt!"])
    func stopWordsNeverReachTheModel(said: String) async {
        let conversation = Conversation(
            teammate: .tempo, userName: "",
            chat: CannedChat { _ in
                Issue.record("the model must not be asked")
                return ""
            })
        #expect(await conversation.respond(to: said).source == .stopWord)
    }

    @Test(arguments: ["not json", #"{"say": ""}"#, #"["hi"]"#])
    func unusableAnswersGetAnApology(answer: String) async {
        let reply = await Conversation(teammate: .byte, userName: "", chat: CannedChat { _ in answer }).respond(
            to: "hello")
        #expect(reply.expression == .sad)
        guard case .failure = reply.source else {
            Issue.record("expected a failure, got \(reply.source)")
            return
        }
    }

    @Test func anUnknownExpressionBecomesNeutralAndLongSpeechIsCutAtASentence() throws {
        #expect(
            try ReplyRules.reply(fromModelAnswer: #"{"say": "Hi", "expression": "furious"}"#).expression == .neutral)
        let cut = ReplyRules.trimmedForSpeech(String(repeating: "This sentence is here. ", count: 40))
        #expect(cut.count <= ReplyRules.maximumSpokenCharacters && cut.hasSuffix("."))
    }

    @Test func thePersonaNamesThePersonAndNeverSaysOwner() {
        let persona = Teammate.byte.persona(userName: "Alex")
        #expect(persona.hasPrefix("You are Byte, a humanoid teammate"))
        #expect(persona.contains("call Alex by name") && persona.contains("computer science"))
        #expect(!Teammate.tempo.persona(userName: "").contains("Alex"))
        #expect(persona.hasSuffix("Answer only with the JSON object."))
    }
}

/// A mutable value shared with a @Sendable closure in a test.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?

    var value: Value? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            stored = newValue
        }
    }
}
