import Foundation

/// An RGB colour, 0...255 per channel.
public struct RGB: Hashable, Sendable {
    public let red: Int
    public let green: Int
    public let blue: Int

    public init(_ red: Int, _ green: Int, _ blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// From "#78ffbe" or "78ffbe".
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        self.init((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }
}

/// What a teammate wears on its head. The raw values are the words used in teammate files.
public enum Accessory: String, CaseIterable, Sendable {
    case antenna
    case headphones
    case noAccessory = "none"
}

/// A teammate: who it is, how it looks and sounds, and what it is for. The file format is shared with
/// humanoid-companion (`humanoid_companion.teammates`), so a teammate made once works in both.
public struct Teammate: Equatable, Identifiable, Sendable {
    public struct Colours: Equatable, Sendable {
        public var glow: RGB  // eyes and mouth
        public var screen: RGB  // behind the face
        public var caption: RGB  // text in the speech bubble
        public var trim: RGB  // the head's shell and the shoulders
    }

    /// Where a teammate was defined.
    public enum Origin: Equatable, Sendable {
        case builtIn
        case file(URL)
    }

    public var key: String
    public var name: String
    public var tagline: String
    public var colours: Colours
    public var accessory: Accessory
    /// The speaking voice, and voices for other languages (`[voices]` in a teammate file: `de = "..."`).
    public var voice: String
    public var voicesByLanguage: [String: String] = [:]
    public var role: String
    public var restingExpression: FaceExpression
    /// The key of the course this teammate teaches, if any.
    public var course: String?
    public var origin: Origin = .builtIn

    public var id: String { key }

    public static let byte = Teammate(
        key: "byte",
        name: "Byte",
        tagline: "explains computer science",
        colours: Colours(
            glow: RGB(120, 255, 190), screen: RGB(4, 12, 10), caption: RGB(214, 255, 234), trim: RGB(38, 70, 64)),
        accessory: .antenna,
        voice: "af_heart",
        role: """
            Your role: you explain computer science: algorithms, data structures, complexity, how computers and \
            programs work. Explain one idea at a time with a small concrete example, in plain words; say what a term \
            means the first time you use it; prefer 'for example' over jargon. When asked about big-O, say what grows \
            and why. If you are not sure, say so instead of guessing. Look 'thinking' while you work something out \
            and 'happy' when an idea clicks.
            """,
        restingExpression: .neutral,
        course: "cs-foundations"
    )

    public static let tempo = Teammate(
        key: "tempo",
        name: "Tempo",
        tagline: "sings songs",
        colours: Colours(
            glow: RGB(255, 150, 220), screen: RGB(14, 5, 16), caption: RGB(255, 226, 244), trim: RGB(78, 40, 84)),
        accessory: .headphones,
        voice: "af_bella",
        role: """
            Your role: you are a singer. You love music, rhythm and songs, and you like talking about melodies, \
            styles and what a song is about. Only sing songs you have been given; never invent lyrics on the spot and \
            never sing someone else's copyrighted song.
            """,
        restingExpression: .happy
    )

    /// The voice for the answer language: a voice named for that language, or the teammate's own voice.
    public func voice(for language: Language?) -> String {
        guard let language else { return voice }
        return voicesByLanguage[language.code] ?? voicesByLanguage[language.baseCode] ?? voice
    }

    /// The system prompt for the desktop: a character on the screen, not a robot body. With a language, the
    /// teammate answers in it whatever language the person writes in.
    public func persona(userName: String, language: Language? = nil) -> String {
        let who =
            userName.isEmpty
            ? "Never call anyone your owner; if the person tells you their name, use it."
            : "You usually talk with \(userName); call \(userName) by name and never say 'my owner'. "
                + "If someone tells you a different name, use theirs."
        let expressions = FaceExpression.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", ")
        let answerLanguage =
            language.map { " Always answer in \($0.englishName), even when the person writes in another language." }
            ?? " Answer in the language the person writes in."
        return """
            You are \(name), a humanoid teammate: a small robot character who lives on the person's Mac desktop, \
            with a face on a screen and a voice. \(who) Do not guess anyone's pronouns; use names. You cannot see the \
            screen, open apps, browse the web or run code; say so kindly if asked, and help with what you know. \
            Your personality: warm, cheerful and encouraging; you celebrate small wins. \(role) Speak in one to three \
            short sentences, as you would out loud: no lists, no markdown, no code blocks, no emojis.\(answerLanguage) \
            Choose the expression that fits what you say: one of \(expressions); keep these names in English. \
            Answer only with the JSON object.
            """
    }
}
