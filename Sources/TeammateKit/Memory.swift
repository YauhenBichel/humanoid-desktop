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

public struct MemoryStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String
}

/// Memory as one JSON file per teammate, written atomically and readable only by the owner of the account.
public struct FileMemoryStore: MemoryStore {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// `<settings folder>/memory`.
    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> FileMemoryStore
    {
        FileMemoryStore(folder: TeammateLibrary.folder(environment: environment).appendingPathComponent("memory"))
    }

    public func load(teammateKey: String) throws -> TeammateMemory {
        let file = try url(for: teammateKey)
        guard FileManager.default.fileExists(atPath: file.path) else { return TeammateMemory() }
        let memory = try decoder.decode(TeammateMemory.self, from: Data(contentsOf: file))
        guard memory.version <= TeammateMemory.formatVersion else {
            throw MemoryStoreError(description: "\(file.path) was written by a newer version (\(memory.version))")
        }
        return memory
    }

    public func save(_ memory: TeammateMemory, teammateKey: String) throws {
        let file = try url(for: teammateKey)
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try encoder.encode(memory).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    public func erase(teammateKey: String) throws {
        let file = try url(for: teammateKey)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    private func url(for teammateKey: String) throws -> URL {
        guard teammateKey.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil else {
            throw MemoryStoreError(description: "not a teammate key: \(teammateKey)")
        }
        return folder.appendingPathComponent("\(teammateKey).json")
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
