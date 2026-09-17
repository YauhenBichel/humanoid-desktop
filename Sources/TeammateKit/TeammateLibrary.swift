import Foundation

/// The settings folder shared with humanoid-companion, and everything read from it.
///
///     <settings folder>/settings.toml
///     <settings folder>/teammates/*.toml
///     <settings folder>/courses/*.json
///
/// The folder is `$HUMANOID_CONFIG_DIR` if set; otherwise `%APPDATA%\\humanoid-companion` on Windows, and
/// `$XDG_CONFIG_HOME/humanoid-companion` or `~/.config/humanoid-companion` on macOS, Linux and other systems.
public struct TeammateLibrary: Sendable {
    public let settings: TeammateSettings
    public let catalog: TeammateCatalog
    public let courses: CourseCatalog
    /// A broken settings, teammate or course file, said plainly; the rest still works.
    public let problems: [String]

    public init(
        settings: TeammateSettings, catalog: TeammateCatalog, courses: CourseCatalog = .builtIn, problems: [String]
    ) {
        self.settings = settings
        self.catalog = catalog
        self.courses = courses
        self.problems = problems
    }

    public enum Platform: Sendable {
        case windows, unixLike

        #if os(Windows)
            public static let current = Platform.windows
        #else
            public static let current = Platform.unixLike
        #endif
    }

    public static func folder(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        platform: Platform = .current,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        func directory(_ variable: String) -> URL? {
            guard let path = environment[variable], !path.isEmpty else { return nil }
            let expanded = path.hasPrefix("~/") ? homeDirectory.path + path.dropFirst() : path
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        if let explicit = directory("HUMANOID_CONFIG_DIR") { return explicit }
        let base =
            switch platform {
            case .windows:
                directory("APPDATA") ?? homeDirectory.appendingPathComponent("AppData/Roaming", isDirectory: true)
            case .unixLike:
                directory("XDG_CONFIG_HOME") ?? homeDirectory.appendingPathComponent(".config", isDirectory: true)
            }
        return base.appendingPathComponent("humanoid-companion", isDirectory: true)
    }

    public static func settingsFile(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        folder(environment: environment).appendingPathComponent("settings.toml")
    }

    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment) -> TeammateLibrary {
        let folder = folder(environment: environment)
        let catalog = TeammateCatalog.load(directory: folder.appendingPathComponent("teammates"))
        let courses = CourseCatalog.load(directory: folder.appendingPathComponent("courses"))
        let missingCourses = catalog.teammates.compactMap { teammate in
            teammate.course.flatMap { courses.course(key: $0) == nil ? "\(teammate.name): no course named \($0)" : nil }
        }
        let problems = catalog.problems + courses.problems + missingCourses
        do {
            let settings = try loadSettings(environment: environment)
            return TeammateLibrary(settings: settings, catalog: catalog, courses: courses, problems: problems)
        } catch {
            return TeammateLibrary(
                settings: .defaults, catalog: catalog, courses: courses, problems: [error.description] + problems)
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
