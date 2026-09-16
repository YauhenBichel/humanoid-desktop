import Foundation

/// The language the teammate answers in, from `[user] language` (an ISO 639-1 code such as "de") or
/// `HUMANOID_LANGUAGE`. Without one, the model answers in the language the person writes in.
public struct Language: Hashable, Sendable {
    public let code: String

    public static let english = Language(normalizedCode: "en")

    /// Stop words in languages the teammate knows, besides English (which always works). Only words that mean
    /// "stop" or "be quiet" and little else, so an ordinary sentence does not silence the teammate.
    private static let stopWordsByLanguage: [String: Set<String>] = [
        "en": ["stop", "halt", "freeze", "estop", "e-stop", "quiet", "shush"],
        "de": ["stopp", "ruhe", "aufhören"],
        "fr": ["arrête", "arrêtez", "silence", "stop"],
        "es": ["detente", "silencio", "alto"],
        "it": ["fermati", "basta", "silenzio"],
        "pl": ["stop", "cisza", "przestań"],
        "uk": ["стоп", "досить", "тихо"],
        "be": ["стоп", "хопіць", "ціха"],
        "ru": ["стоп", "хватит", "тихо"],
    ]

    /// From a code such as "de" or "pt-BR"; nil when the text is not a language code.
    public init?(code: String) {
        let normalized = code.trimmingCharacters(in: .whitespaces).lowercased()
        guard normalized.range(of: "^[a-z]{2,3}(-[a-z0-9]{2,8})?$", options: .regularExpression) != nil else {
            return nil
        }
        self.init(normalizedCode: normalized)
    }

    private init(normalizedCode: String) {
        self.code = normalizedCode
    }

    /// "de-at" answers "de".
    public var baseCode: String { String(code.prefix { $0 != "-" }) }

    /// The language's name in English, for the model's instructions ("German").
    public var englishName: String {
        Locale(identifier: "en").localizedString(forLanguageCode: baseCode) ?? code
    }

    public var stopWords: Set<String> {
        Self.stopWordsByLanguage["en", default: []].union(Self.stopWordsByLanguage[baseCode, default: []])
    }
}
