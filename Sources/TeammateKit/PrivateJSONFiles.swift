import Foundation

/// One folder of JSON files that only the account's owner can read: the folder is 0700, each file 0600 and written
/// atomically, and each file is named by a checked key, so a key can never point outside the folder.
struct PrivateJSONFiles: Sendable {
    let folder: URL

    static let keyPattern = "^[a-z0-9][a-z0-9-]*$"

    static func isKey(_ text: String) -> Bool {
        text.range(of: keyPattern, options: .regularExpression) != nil
    }

    /// The decoded file, or nil when there is none yet.
    func read<Value: Decodable>(_ type: Value.Type, key: String) throws -> Value? {
        let file = try url(for: key)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: file))
    }

    func write(_ value: some Encodable, key: String) throws {
        let file = try url(for: key)
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func remove(key: String) throws {
        let file = try url(for: key)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    func url(for key: String) throws(StoreError) -> URL {
        guard Self.isKey(key) else { throw StoreError(description: "not a usable file key: \(key)") }
        return folder.appendingPathComponent("\(key).json")
    }
}

/// A memory or progress file that could not be read or written.
public struct StoreError: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String
}
