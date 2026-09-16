import Foundation

/// Where the model and the voice servers are, and what to call you. Read from the same
/// settings.toml as humanoid-companion (`humanoid-teammate init` writes one), so both use one setup:
///
///     ~/.config/humanoid-companion/settings.toml      ($HUMANOID_CONFIG_DIR or $XDG_CONFIG_HOME move it)
///
/// An environment variable (HUMANOID_LLM_BASE_URL and friends) wins over the file, as in the companion.
/// An app opened from Finder does not see your shell's variables, so the file is the usual way.
/// The API key is only read from HUMANOID_LLM_API_KEY: keys do not belong in the file.
public struct Settings: Equatable {
    public var userName: String
    public var chatBaseURL: URL
    public var model: String
    public var apiKey: String?
    public var speechBaseURL: URL
    public var transcriptionBaseURL: URL

    public static let defaults = Settings(
        userName: "",
        chatBaseURL: URL(string: "http://127.0.0.1:11434/v1")!,
        model: "",
        apiKey: nil,
        speechBaseURL: URL(string: "http://127.0.0.1:8880/v1")!,
        transcriptionBaseURL: URL(string: "http://127.0.0.1:8000/v1")!
    )

    public static func configDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let explicit = environment["HUMANOID_CONFIG_DIR"], !explicit.isEmpty {
            return URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath)
        }
        let base = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".config")
        return URL(fileURLWithPath: (base as NSString).expandingTildeInPath).appendingPathComponent("humanoid-companion")
    }

    /// The settings from the file (if any) and the environment.
    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Settings {
        let file = configDirectory(environment: environment).appendingPathComponent("settings.toml")
        var table: Toml.Table = [:]
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                table = try Toml.parse(try String(contentsOf: file, encoding: .utf8))
            } catch {
                throw SettingsError(message: "\(file.path): \(error)")
            }
        }
        return try resolve(table: table, environment: environment)
    }

    static func resolve(table: Toml.Table, environment: [String: String]) throws -> Settings {
        func value(_ variable: String, _ section: String, _ key: String) -> String? {
            if let fromEnvironment = environment[variable]?.trimmingCharacters(in: .whitespaces), !fromEnvironment.isEmpty {
                return fromEnvironment
            }
            let fromFile = table[section]?.table?[key]?.string?.trimmingCharacters(in: .whitespaces)
            return fromFile?.isEmpty == false ? fromFile : nil
        }
        func url(_ variable: String, _ section: String, _ key: String, default fallback: URL) throws -> URL {
            guard let text = value(variable, section, key) else { return fallback }
            guard let parsed = URL(string: text.hasSuffix("/") ? String(text.dropLast()) : text), parsed.scheme != nil else {
                throw SettingsError(message: "\(section).\(key) is not a URL: \(text)")
            }
            return parsed
        }
        let defaults = Settings.defaults
        return Settings(
            userName: value("HUMANOID_USER_NAME", "user", "name") ?? "",
            chatBaseURL: try url("HUMANOID_LLM_BASE_URL", "llm", "base_url", default: defaults.chatBaseURL),
            model: value("HUMANOID_LLM_MODEL", "llm", "model") ?? "",
            apiKey: environment["HUMANOID_LLM_API_KEY"].flatMap { $0.isEmpty ? nil : $0 },
            speechBaseURL: try url("HUMANOID_TTS_BASE_URL", "voice", "tts_base_url", default: defaults.speechBaseURL),
            transcriptionBaseURL: try url("HUMANOID_STT_BASE_URL", "voice", "stt_base_url", default: defaults.transcriptionBaseURL)
        )
    }
}

extension Settings {
    /// The settings file to fill in: the same text `humanoid-teammate init` writes (a test holds them equal).
    public static let template = """
    # humanoid-companion settings: every value fills in the environment variable named next to it,
    # unless that variable is already set. Keep API keys out of this file (use HUMANOID_LLM_API_KEY).

    [user]
    name = ""                                      # HUMANOID_USER_NAME: the robot calls you by it
    name_be = ""                                   # HUMANOID_USER_NAME_BE: your name in Belarusian, for the goodbye

    [llm]
    base_url = "http://127.0.0.1:11434/v1"         # HUMANOID_LLM_BASE_URL: any OpenAI-compatible chat server
    model = ""                                     # HUMANOID_LLM_MODEL

    [voice]
    tts_base_url = "http://127.0.0.1:8880/v1"      # HUMANOID_TTS_BASE_URL: /audio/speech
    stt_base_url = "http://127.0.0.1:8000/v1"      # HUMANOID_STT_BASE_URL: /audio/transcriptions
    be_tts_url = "http://127.0.0.1:11810/v1"       # HUMANOID_BE_TTS_URL: the Belarusian goodbye
    voice = "af_heart"                             # HUMANOID_TTS_VOICE: the plain robot's voice

    [songs]
    # tempo = "~/songs"                            # a teammate's song library, used when --songs is not given

    """

    /// settings.toml in the settings folder, created from the template if it does not exist yet.
    public static func ensureFile(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        let folder = configDirectory(environment: environment)
        let file = folder.appendingPathComponent("settings.toml")
        if !FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("teammates"), withIntermediateDirectories: true)
            try template.write(to: file, atomically: true, encoding: .utf8)
        }
        return file
    }
}

public struct SettingsError: Error, CustomStringConvertible, Equatable {
    public let message: String
    public var description: String { message }
}
