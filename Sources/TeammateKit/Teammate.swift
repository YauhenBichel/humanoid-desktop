import Foundation

/// An RGB colour, 0...255 per channel.
public struct RGB: Equatable, Hashable {
    public let red: Int, green: Int, blue: Int

    public init(_ red: Int, _ green: Int, _ blue: Int) {
        (self.red, self.green, self.blue) = (red, green, blue)
    }

    /// "#78ffbe" or "78ffbe".
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        self.init((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }
}

public enum Accessory: String, CaseIterable {
    case antenna, headphones, none
}

/// A teammate: who it is, how it looks and sounds, and what it is for. The same file format as
/// humanoid-companion's teammates (humanoid_companion.teammates), so a teammate you make once works in
/// both: `<settings folder>/teammates/<key>.toml`.
public struct Teammate: Equatable, Identifiable {
    public var id: String { key }
    public var key: String
    public var name: String
    public var tagline: String
    public var glow: RGB  // eyes and mouth
    public var background: RGB  // the head's screen
    public var caption: RGB  // text in the bubble
    public var trim: RGB  // the head's shell and shoulders
    public var accessory: Accessory
    public var voice: String
    public var role: String
    public var restingExpression: FaceExpression
    public var source: String = "built in"

    public static let byte = Teammate(
        key: "byte", name: "Byte", tagline: "explains computer science",
        glow: RGB(120, 255, 190), background: RGB(4, 12, 10), caption: RGB(214, 255, 234), trim: RGB(38, 70, 64),
        accessory: .antenna, voice: "af_heart",
        role: "Your role: you explain computer science: algorithms, data structures, complexity, how computers and "
            + "programs work. Explain one idea at a time with a small concrete example, in plain words; say what a "
            + "term means the first time you use it; prefer 'for example' over jargon. When asked about big-O, say "
            + "what grows and why. If you are not sure, say so instead of guessing. Look 'thinking' while you work "
            + "something out and 'happy' when an idea clicks.",
        restingExpression: .neutral
    )

    public static let tempo = Teammate(
        key: "tempo", name: "Tempo", tagline: "sings songs",
        glow: RGB(255, 150, 220), background: RGB(14, 5, 16), caption: RGB(255, 226, 244), trim: RGB(78, 40, 84),
        accessory: .headphones, voice: "af_bella",
        role: "Your role: you are a singer. You love music, rhythm and songs, and you like talking about melodies, "
            + "styles and what a song is about. Only sing songs you have been given; never invent lyrics on the spot "
            + "and never sing someone else's copyrighted song.",
        restingExpression: .happy
    )

    public static let builtIn: [Teammate] = [.byte, .tempo]

    /// The persona for the desktop: a character on the screen, not a robot body.
    public func persona(userName: String) -> String {
        let who = userName.isEmpty
            ? "Never call anyone your owner; if the person tells you their name, use it. "
            : "You usually talk with \(userName); call \(userName) by name and never say 'my owner'. "
                + "If someone tells you a different name, use theirs. "
        let expressions = FaceExpression.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", ")
        return "You are \(name), a humanoid teammate: a small robot character who lives on the person's Mac desktop, "
            + "with a face on a screen and a voice. " + who
            + "Do not guess anyone's pronouns; use names. You cannot see the screen, open apps, browse the web or "
            + "run code; say so kindly if asked, and help with what you know. "
            + "Your personality: warm, cheerful and encouraging; you celebrate small wins. "
            + role + " "
            + "Speak in one to three short sentences, as you would out loud: no lists, no markdown, no code blocks, "
            + "no emojis. Choose the expression that fits what you say: one of \(expressions). "
            + "Answer only with the JSON object."
    }
}

public struct TeammateError: Error, CustomStringConvertible, Equatable {
    public let message: String
    public var description: String { message }
}

extension Teammate {
    /// A teammate from its TOML file; the file name is the key. Unknown fields (a clip-only `dances`, for
    /// example) are ignored; wrong values name the file and the field.
    public static func load(file: URL, builtIn: [Teammate] = Teammate.builtIn) throws -> Teammate {
        let key = file.deletingPathExtension().lastPathComponent
        func fail(_ message: String) -> TeammateError { TeammateError(message: "\(file.path): \(message)") }
        guard key.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil else {
            throw fail("the file name must be lowercase letters, digits and hyphens")
        }
        let table: Toml.Table
        do {
            table = try Toml.parse(try String(contentsOf: file, encoding: .utf8))
        } catch {
            throw fail("\(error)")
        }
        let byKey = Dictionary(uniqueKeysWithValues: builtIn.map { ($0.key, $0) })
        let baseKey = table["based_on"]?.string ?? (byKey[key] != nil ? key : "byte")
        guard var teammate = byKey[baseKey] else {
            throw fail("based_on must be one of \(builtIn.map(\.key).joined(separator: ", "))")
        }
        let startsFromItself = baseKey == key
        teammate.key = key
        teammate.name = table["name"]?.string ?? (startsFromItself ? teammate.name : key.capitalized)
        teammate.tagline = table["tagline"]?.string ?? teammate.tagline
        teammate.voice = table["voice"]?.string ?? teammate.voice
        teammate.role = table["role"]?.string ?? teammate.role
        if let accessory = table["accessory"]?.string {
            guard let parsed = Accessory(rawValue: accessory) else {
                throw fail("accessory must be one of \(Accessory.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            teammate.accessory = parsed
        }
        if let resting = table["resting_expression"]?.string {
            guard let parsed = FaceExpression(rawValue: resting) else {
                throw fail("resting_expression must be one of \(FaceExpression.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            teammate.restingExpression = parsed
        }
        let colours = table["colours"]?.table ?? [:]
        for (field, path) in [("glow", \Teammate.glow), ("background", \.background), ("caption", \.caption), ("trim", \.trim)] {
            guard let text = colours[field]?.string else { continue }
            guard let colour = RGB(hex: text) else { throw fail("colours.\(field): expected a colour like #78ffbe, got \(text)") }
            teammate[keyPath: path] = colour
        }
        guard !teammate.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw fail("role must say what the teammate is for")
        }
        teammate.source = file.path
        return teammate
    }

    /// The built-in teammates, then your own from `<settings folder>/teammates/*.toml`, in name order.
    /// A broken file is reported, not fatal: the other teammates still load.
    public static func all(directory: URL) -> (teammates: [Teammate], problems: [String]) {
        var teammates = builtIn
        var problems: [String] = []
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files.filter({ $0.pathExtension == "toml" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let teammate = try load(file: file)
                if let existing = teammates.firstIndex(where: { $0.key == teammate.key }) {
                    teammates[existing] = teammate
                } else {
                    teammates.append(teammate)
                }
            } catch {
                problems.append("\(error)")
            }
        }
        return (teammates, problems)
    }
}
