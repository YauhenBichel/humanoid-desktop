import Foundation

public struct TeammateFileError: Error, Equatable, Sendable, CustomStringConvertible {
    public let file: URL
    public let message: String
    public var description: String { "\(file.path): \(message)" }
}

/// The teammates to choose from: the built-in ones, then your own files from `<settings folder>/teammates`.
public struct TeammateCatalog: Equatable, Sendable {
    public private(set) var teammates: [Teammate]
    /// Files that could not be used, each naming the file and the field; the other teammates still load.
    public private(set) var problems: [String]

    public static let builtIn = TeammateCatalog(teammates: [.byte, .tempo], problems: [])

    public func teammate(key: String) -> Teammate? {
        teammates.first { $0.key == key }
    }

    /// The built-in teammates and every `*.toml` in `directory`, in file name order. A file named after a
    /// built-in teammate changes that teammate.
    public static func load(directory: URL) -> TeammateCatalog {
        var catalog = builtIn
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files.filter({ $0.pathExtension == "toml" }).sorted(by: {
            $0.lastPathComponent < $1.lastPathComponent
        }) {
            do {
                catalog.add(try TeammateFile.load(file, builtIn: builtIn.teammates))
            } catch {
                catalog.problems.append(error.description)
            }
        }
        return catalog
    }

    private mutating func add(_ teammate: Teammate) {
        if let existing = teammates.firstIndex(where: { $0.key == teammate.key }) {
            teammates[existing] = teammate
        } else {
            teammates.append(teammate)
        }
    }
}

/// Reads one teammate file. Unknown fields (a clip-only `dances`, for example) are ignored.
public enum TeammateFile {
    public static func load(_ file: URL, builtIn: [Teammate] = TeammateCatalog.builtIn.teammates)
        throws(TeammateFileError)
        -> Teammate
    {
        func failure(_ message: String) -> TeammateFileError { TeammateFileError(file: file, message: message) }

        let key = file.deletingPathExtension().lastPathComponent
        guard key.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil else {
            throw failure("the file name must be lowercase letters, digits and hyphens")
        }
        let table: Toml.Table
        do {
            table = try Toml.parse(String(contentsOf: file, encoding: .utf8))
        } catch {
            throw failure("\(error)")
        }

        let baseKey = table["based_on"]?.string ?? (builtIn.contains { $0.key == key } ? key : "byte")
        guard var teammate = builtIn.first(where: { $0.key == baseKey }) else {
            throw failure("based_on must be one of \(builtIn.map(\.key).joined(separator: ", "))")
        }
        teammate.key = key
        teammate.name = table["name"]?.string ?? (baseKey == key ? teammate.name : key.capitalized)
        teammate.tagline = table["tagline"]?.string ?? teammate.tagline
        teammate.voice = table["voice"]?.string ?? teammate.voice
        teammate.role = table["role"]?.string ?? teammate.role
        if let word = table["accessory"]?.string {
            guard let accessory = Accessory(rawValue: word) else {
                throw failure("accessory must be one of \(Accessory.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            teammate.accessory = accessory
        }
        if let word = table["resting_expression"]?.string {
            guard let expression = FaceExpression(rawValue: word) else {
                let names = FaceExpression.allCases.map(\.rawValue).joined(separator: ", ")
                throw failure("resting_expression must be one of \(names)")
            }
            teammate.restingExpression = expression
        }
        let colours = table["colours"]?.table ?? [:]
        let fields: [(name: String, path: WritableKeyPath<Teammate.Colours, RGB>)] = [
            ("glow", \.glow), ("background", \.screen), ("caption", \.caption), ("trim", \.trim),
        ]
        for field in fields {
            guard let text = colours[field.name]?.string else { continue }
            guard let colour = RGB(hex: text) else {
                throw failure("colours.\(field.name): expected a colour like #78ffbe, got \(text)")
            }
            teammate.colours[keyPath: field.path] = colour
        }
        guard !teammate.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw failure("role must say what the teammate is for")
        }
        teammate.origin = .file(file)
        return teammate
    }
}
