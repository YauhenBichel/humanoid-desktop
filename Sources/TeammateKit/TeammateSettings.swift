import Foundation

/// Where the model and the voice servers are, and what to call you.
///
/// Read from the same `settings.toml` as humanoid-companion, so both use one setup. An environment variable
/// (`HUMANOID_LLM_BASE_URL` and friends) wins over the file, as in the companion; an app opened from Finder
/// does not see your shell's variables, so the file is the usual way. The API key is only ever read from
/// `HUMANOID_LLM_API_KEY`: keys do not belong in the file.
public struct TeammateSettings: Equatable, Sendable {
    public var userName: String
    public var chatBaseURL: URL
    public var model: String
    public var apiKey: String?
    public var speechBaseURL: URL
    public var transcriptionBaseURL: URL

    public static let defaults = TeammateSettings(
        userName: "",
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

        let defaults = Self.defaults
        self.init(
            userName: value("HUMANOID_USER_NAME", "user", "name") ?? "",
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
        chatBaseURL: URL,
        model: String,
        apiKey: String?,
        speechBaseURL: URL,
        transcriptionBaseURL: URL
    ) {
        self.userName = userName
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

/// The settings folder shared with humanoid-companion, and everything read from it.
///
///     ~/.config/humanoid-companion/settings.toml      ($HUMANOID_CONFIG_DIR or $XDG_CONFIG_HOME move it)
///     ~/.config/humanoid-companion/teammates/*.toml
public struct TeammateLibrary: Sendable {
    public let settings: TeammateSettings
    public let catalog: TeammateCatalog
    /// A broken settings file or teammate file, said plainly; the rest still works.
    public let problems: [String]

    public static func folder(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let explicit = environment["HUMANOID_CONFIG_DIR"], !explicit.isEmpty {
            return URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath)
        }
        let base =
            environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".config")
        return URL(fileURLWithPath: (base as NSString).expandingTildeInPath)
            .appendingPathComponent("humanoid-companion")
    }

    public static func settingsFile(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        folder(environment: environment).appendingPathComponent("settings.toml")
    }

    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment) -> TeammateLibrary {
        let catalog = TeammateCatalog.load(
            directory: folder(environment: environment).appendingPathComponent("teammates"))
        do {
            let settings = try loadSettings(environment: environment)
            return TeammateLibrary(settings: settings, catalog: catalog, problems: catalog.problems)
        } catch {
            return TeammateLibrary(
                settings: .defaults, catalog: catalog, problems: [error.description] + catalog.problems)
        }
    }

    public static func loadSettings(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws(SettingsError) -> TeammateSettings {
        let file = settingsFile(environment: environment)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return try TeammateSettings(table: [:], environment: environment)
        }
        do {
            let table = try Toml.parse(String(contentsOf: file, encoding: .utf8))
            return try TeammateSettings(table: table, environment: environment)
        } catch let error as SettingsError {
            throw error
        } catch {
            throw SettingsError(message: "\(file.path): \(error)")
        }
    }

    /// `settings.toml`, created from the template (and the teammates folder with it) if it does not exist yet.
    public static func ensureSettingsFile(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        let file = settingsFile(environment: environment)
        if !FileManager.default.fileExists(atPath: file.path) {
            let teammates = folder(environment: environment).appendingPathComponent("teammates")
            try FileManager.default.createDirectory(at: teammates, withIntermediateDirectories: true)
            try settingsTemplate.write(to: file, atomically: true, encoding: .utf8)
        }
        return file
    }

    /// The same text `humanoid-teammate init` writes; a test holds the two equal.
    public static let settingsTemplate = """
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
}
