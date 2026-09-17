import Foundation

/// What a teammate remembers about the person between launches: short facts the person shared, a condensed
/// summary of earlier conversations, and the latest messages word for word.
///
/// Stored as JSON in `<settings folder>/memory/<teammate key>.json`, readable only by the person's account, in a
/// format humanoid-companion reads too. Nothing leaves the machine except inside the prompts sent to the chat
/// server the person configured. "Forget" deletes the file.
public struct TeammateMemory: Codable, Equatable, Sendable {
    public static let formatVersion = 1
    public static let maximumFacts = 30
    public static let maximumFactLength = 160
    public static let maximumRecentMessages = 12
    public static let maximumSummaryLength = 800

    public var version = formatVersion
    /// Newest last; the oldest go first when there are too many.
    public var facts: [String] = []
    public var summary = ""
    public var recent: [ChatMessage] = []
    public var updated: Date?

    public init(facts: [String] = [], summary: String = "", recent: [ChatMessage] = [], updated: Date? = nil) {
        self.facts = facts
        self.summary = summary
        self.recent = recent
        self.updated = updated
    }

    public var isEmpty: Bool { facts.isEmpty && summary.isEmpty && recent.isEmpty }

    /// Adds facts the model noted, trimmed, shortened and without repeating one it already knows.
    public mutating func learn(_ newFacts: [String]) {
        for fact in newFacts {
            let flat = fact.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !flat.isEmpty else { continue }
            let short = String(flat.prefix(Self.maximumFactLength))
            guard !facts.contains(where: { $0.caseInsensitiveCompare(short) == .orderedSame }) else { continue }
            facts.append(short)
        }
        facts = Array(facts.suffix(Self.maximumFacts))
    }

    /// The part of the system prompt that tells the model what it remembers, or nil when it remembers nothing.
    func promptSection(personName: String) -> String? {
        guard !facts.isEmpty || !summary.isEmpty else { return nil }
        var lines: [String] = []
        if !facts.isEmpty {
            lines.append("What you remember about \(personName):")
            lines += facts.map { "- \($0)" }
        }
        if !summary.isEmpty {
            lines.append("Your earlier conversations, in short: \(summary)")
        }
        lines.append("Use this naturally when it helps; do not recite it.")
        return lines.joined(separator: "\n")
    }
}

/// Keeps each teammate's memory.
public protocol MemoryStore: Sendable {
    func load(teammateKey: String) throws -> TeammateMemory
    func save(_ memory: TeammateMemory, teammateKey: String) throws
    func erase(teammateKey: String) throws
}

/// Memory as one JSON file per teammate, readable only by the owner of the account.
public struct FileMemoryStore: MemoryStore {
    private let files: PrivateJSONFiles

    public var folder: URL { files.folder }

    public init(folder: URL) {
        files = PrivateJSONFiles(folder: folder)
    }

    /// `<settings folder>/memory`.
    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> FileMemoryStore
    {
        FileMemoryStore(folder: TeammateLibrary.folder(environment: environment).appendingPathComponent("memory"))
    }

    public func load(teammateKey: String) throws -> TeammateMemory {
        guard let memory = try files.read(TeammateMemory.self, key: teammateKey) else { return TeammateMemory() }
        guard memory.version <= TeammateMemory.formatVersion else {
            throw StoreError(
                description:
                    "\(try files.url(for: teammateKey).path) was written by a newer version (\(memory.version))")
        }
        return memory
    }

    public func save(_ memory: TeammateMemory, teammateKey: String) throws {
        try files.write(memory, key: teammateKey)
    }

    public func erase(teammateKey: String) throws {
        try files.remove(key: teammateKey)
    }
}
