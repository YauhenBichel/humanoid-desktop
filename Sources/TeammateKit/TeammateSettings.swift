import Foundation

/// Where the model and the voice servers are, and what to call you.
///
/// Read from the same `settings.toml` as humanoid-companion, so both use one setup. An environment variable
/// (`HUMANOID_LLM_BASE_URL` and friends) wins over the file, as in the companion; an app opened from Finder
/// does not see your shell's variables, so the file is the usual way. The API key is only ever read from
/// `HUMANOID_LLM_API_KEY`: keys do not belong in the file.
public struct TeammateSettings: Equatable, Sendable {
    public var userName: String
    /// The language the teammate answers in (`[user] language`); nil answers in the language the person uses.
    public var language: Language?
    public var chatBaseURL: URL
    public var model: String
    public var apiKey: String?
    public var speechBaseURL: URL
    public var transcriptionBaseURL: URL

    public static let defaults = TeammateSettings(
        userName: "",
        language: nil,
        chatBaseURL: URL(string: "http://127.0.0.1:11434/v1")!,
        model: "",
        apiKey: nil,
        speechBaseURL: URL(string: "http://127.0.0.1:8880/v1")!,
        transcriptionBaseURL: URL(string: "http://127.0.0.1:8000/v1")!
    )

    /// The settings from a parsed `settings.toml` and the environment.
    public init(table: Toml.Table, environment: [String: String]) throws(SettingsError) {
        func value(_ variable: String, _ section: String, _ key: String) -> String? {
            if let fromEnvironment = environment[variable]?.trimmingCharacters(in: .whitespaces),
                !fromEnvironment.isEmpty
            {
                return fromEnvironment
            }
            let fromFile = table[section]?.table?[key]?.string?.trimmingCharacters(in: .whitespaces)
            return fromFile?.isEmpty == false ? fromFile : nil
        }
        func url(_ variable: String, _ section: String, _ key: String, _ fallback: URL) throws(SettingsError) -> URL {
            guard let text = value(variable, section, key) else { return fallback }
            let trimmed = text.hasSuffix("/") ? String(text.dropLast()) : text
            guard let parsed = URL(string: trimmed), parsed.scheme != nil else {
                throw SettingsError(message: "\(section).\(key) is not a URL: \(text)")
            }
            return parsed
        }

        var language: Language?
        if let code = value("HUMANOID_LANGUAGE", "user", "language") {
            guard let parsed = Language(code: code) else {
                throw SettingsError(message: "user.language is not a language code such as \"de\": \(code)")
            }
            language = parsed
        }

        let defaults = Self.defaults
        self.init(
            userName: value("HUMANOID_USER_NAME", "user", "name") ?? "",
            language: language,
            chatBaseURL: try url("HUMANOID_LLM_BASE_URL", "llm", "base_url", defaults.chatBaseURL),
            model: value("HUMANOID_LLM_MODEL", "llm", "model") ?? "",
            apiKey: environment["HUMANOID_LLM_API_KEY"].flatMap { $0.isEmpty ? nil : $0 },
            speechBaseURL: try url("HUMANOID_TTS_BASE_URL", "voice", "tts_base_url", defaults.speechBaseURL),
            transcriptionBaseURL: try url(
                "HUMANOID_STT_BASE_URL", "voice", "stt_base_url", defaults.transcriptionBaseURL)
        )
    }

    public init(
        userName: String,
        language: Language?,
        chatBaseURL: URL,
        model: String,
        apiKey: String?,
        speechBaseURL: URL,
        transcriptionBaseURL: URL
    ) {
        self.userName = userName
        self.language = language
        self.chatBaseURL = chatBaseURL
        self.model = model
        self.apiKey = apiKey
        self.speechBaseURL = speechBaseURL
        self.transcriptionBaseURL = transcriptionBaseURL
    }
}

public struct SettingsError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}
