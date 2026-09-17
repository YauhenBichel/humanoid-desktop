import Foundation
import Testing

@testable import TeammateKit

/// Memory kept in a dictionary, shared between a test and the session.
final class MemoryShelf: MemoryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var memories: [String: TeammateMemory] = [:]
    var failing = false

    func load(teammateKey: String) throws -> TeammateMemory {
        lock.lock()
        defer { lock.unlock() }
        if failing { throw StoreError(description: "disk full") }
        return memories[teammateKey] ?? TeammateMemory()
    }

    func save(_ memory: TeammateMemory, teammateKey: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if failing { throw StoreError(description: "disk full") }
        memories[teammateKey] = memory
    }

    func erase(teammateKey: String) throws {
        lock.lock()
        defer { lock.unlock() }
        memories[teammateKey] = nil
    }

    subscript(key: String) -> TeammateMemory? {
        lock.lock()
        defer { lock.unlock() }
        return memories[key]
    }
}

@Suite struct TeammateMemoryTests {
    @Test func learnsShortNewFactsAndForgetsTheOldestBeyondTheLimit() {
        var memory = TeammateMemory()
        memory.learn([
            "  Prefers   Python examples ", "prefers python examples", "", String(repeating: "x", count: 500),
        ])
        #expect(memory.facts.count == 2 && memory.facts[0] == "Prefers Python examples")
        #expect(memory.facts[1].count == TeammateMemory.maximumFactLength)
        memory.learn((0..<40).map { "fact \($0)" })
        #expect(memory.facts.count == TeammateMemory.maximumFacts && memory.facts.last == "fact 39")
    }

    @Test func thePromptSectionListsFactsAndTheSummary() throws {
        #expect(TeammateMemory().promptSection(personName: "Alex") == nil)
        let memory = TeammateMemory(facts: ["Is learning graphs"], summary: "Talked about BFS.")
        let section = try #require(memory.promptSection(personName: "Alex"))
        #expect(section.contains("What you remember about Alex:\n- Is learning graphs"))
        #expect(section.contains("in short: Talked about BFS."))
    }

    @Test func aFileStoreKeepsMemoryPrivateAndRoundTrips() throws {
        let store = FileMemoryStore(folder: temporaryFolder().appendingPathComponent("memory"))
        #expect(try store.load(teammateKey: "byte") == TeammateMemory())
        let memory = TeammateMemory(
            facts: ["Is learning graphs"], summary: "BFS", recent: [ChatMessage(.user, "hi")],
            updated: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(memory, teammateKey: "byte")
        #expect(try store.load(teammateKey: "byte") == memory)
        let file = store.folder.appendingPathComponent("byte.json")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        try store.erase(teammateKey: "byte")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(throws: StoreError.self) { try store.save(memory, teammateKey: "../escape") }
    }

    @Test func aMemoryFromANewerVersionIsNotMisread() throws {
        let store = FileMemoryStore(folder: temporaryFolder())
        try #"{"version": 99, "facts": [], "summary": "", "recent": []}"#.write(
            to: store.folder.appendingPathComponent("byte.json"), atomically: true, encoding: .utf8)
        #expect(throws: StoreError.self) { try store.load(teammateKey: "byte") }
    }
}

@Suite struct ConversationMemoryTests {
    @Test func factsFromTheReplyAreRememberedAndOfferedNextTime() async {
        let prompts = Box<[ChatMessage]>()
        let chat = CannedChat { messages in
            prompts.value = messages
            return
                #"{"say": "Nice!", "expression": "happy", "remember": ["Is learning graphs", "Likes Python", "a", "b"]}"#
        }
        let conversation = Conversation(teammate: .byte, userName: "Alex", chat: chat)
        _ = await conversation.respond(to: "I'm learning graphs in Python")
        let memory = await conversation.memory
        #expect(memory.facts == ["Is learning graphs", "Likes Python", "a"])  // at most three per reply
        #expect(memory.recent.count == 2 && memory.updated != nil)

        let next = Conversation(teammate: .byte, userName: "Alex", memory: memory, chat: chat)
        _ = await next.respond(to: "What should I study next?")
        let system = prompts.value?.first?.content ?? ""
        #expect(system.contains("What you remember about Alex:\n- Is learning graphs"))
        #expect(system.contains("never note passwords") || system.contains("Never note passwords"))
        #expect(prompts.value?.count == 4)  // system, the two remembered messages, the new question
    }

    @Test func olderMessagesAreFoldedIntoTheSummary() async {
        let chat = CannedChat { messages in
            if messages.first?.content.contains("short summary of earlier conversations") == true {
                return #"{"summary": "Alex practised BFS and DFS."}"#
            }
            return #"{"say": "Sure.", "expression": "neutral", "remember": []}"#
        }
        let conversation = Conversation(teammate: .byte, userName: "Alex", chat: chat)
        for index in 0..<7 { _ = await conversation.respond(to: "question \(index)") }
        let memory = await conversation.memory
        #expect(memory.summary == "Alex practised BFS and DFS.")
        #expect(memory.recent.count <= Conversation.maximumHistory)
        #expect(
            memory.recent.last?.role == .assistant && memory.recent[memory.recent.count - 2].content == "question 6")
    }

    @Test func aSummaryFailureDropsOldMessagesInsteadOfGrowingForever() async {
        let chat = CannedChat { messages in
            if messages.first?.content.contains("short summary") == true { throw ServerError.notHTTP(url: nil) }
            return #"{"say": "Sure.", "expression": "neutral", "remember": []}"#
        }
        let conversation = Conversation(teammate: .byte, userName: "", chat: chat)
        for index in 0..<10 { _ = await conversation.respond(to: "question \(index)") }
        let memory = await conversation.memory
        #expect(memory.summary.isEmpty && memory.recent.count <= Conversation.maximumHistory)
    }
}

@MainActor
@Suite struct SessionMemoryTests {
    private func session(chat: CannedChat, memories: MemoryShelf) -> TeammateSession {
        let session = TeammateSession(
            player: FakePlayer(), recorder: FakeRecorder(), choices: MemoryChoices(), memories: memories
        ) { _ in
            .init(chat: chat, speech: FixedSpeech(), transcription: FixedTranscription())
        }
        session.configure(with: TeammateLibrary(settings: .defaults, catalog: .builtIn, problems: []))
        return session
    }

    @Test func eachAnsweredMessageIsKeptAndComesBackWithTheTeammate() async {
        let memories = MemoryShelf()
        let chat = CannedChat { _ in #"{"say": "Got it.", "expression": "happy", "remember": ["Is learning graphs"]}"# }
        let first = session(chat: chat, memories: memories)
        first.send("I'm learning graphs")
        for _ in 0..<200 where memories["byte"] == nil { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(memories["byte"]?.facts == ["Is learning graphs"])

        let later = session(chat: chat, memories: memories)  // a new launch
        later.send("hello again")
        for _ in 0..<200 where memories["byte"]?.recent.count != 4 { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(memories["byte"]?.recent.count == 4)
    }

    @Test func forgettingErasesTheMemoryAndSaysSo() async {
        let memories = MemoryShelf()
        try? memories.save(TeammateMemory(facts: ["Likes Python"]), teammateKey: "byte")
        let session = session(chat: CannedChat(say: "Hi"), memories: memories)
        session.forgetMemory()
        #expect(memories["byte"] == nil)
        #expect(session.bubble == SessionPhrases.english.forgotten(.byte))
    }

    @Test func aStoreThatCannotBeReadIsReportedAndTheTeammateStillWorks() {
        let memories = MemoryShelf()
        memories.failing = true
        let session = session(chat: CannedChat(say: "Hi"), memories: memories)
        #expect(session.notice.contains("disk full") && session.teammate == .byte)
    }
}
