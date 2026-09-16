import Foundation
import Testing

@testable import TeammateKit

@Suite struct TomlTests {
    @Test func readsTheSubsetThatSettingsAndTeammateFilesUse() throws {
        let table = try Toml.parse(
            """
            # a comment
            name = "Nova" # trailing comment
            dances = false
            size = 1_000
            quote = "say \\"hi\\" # not a comment"
            role = \"\"\"
            Your role: you
            tell # not a comment
            stories.\"\"\"
            literal = 'C:\\path'

            [colours]
            glow = "#9fd0ff"
            """)
        #expect(table["name"] == .string("Nova"))
        #expect(table["dances"] == .bool(false))
        #expect(table["size"] == .number(1000))
        #expect(table["quote"]?.string == "say \"hi\" # not a comment")
        #expect(table["role"]?.string == "Your role: you\ntell # not a comment\nstories.")
        #expect(table["literal"]?.string == "C:\\path")
        #expect(table["colours"]?.table?["glow"] == .string("#9fd0ff"))
    }

    @Test(arguments: [
        "name = ", "[colours", "name = \"unclosed", "a = [1, 2]", "x = 1\nx = 2", "role = \"\"\"never closed",
        "name = \"a\" b", "x = 1\n[x]",
    ])
    func rejectsWhatItDoesNotUnderstand(text: String) {
        #expect(throws: Toml.ParseError.self) { try Toml.parse(text) }
    }
}

@Suite struct SettingsTests {
    @Test func comeFromTheFileAndTheEnvironmentWins() throws {
        let table = try Toml.parse(
            """
            [user]
            name = "Alex"
            [llm]
            base_url = "http://127.0.0.1:9000/v1/"
            model = "qwen3:8b"
            [voice]
            tts_base_url = "http://127.0.0.1:9000/v1"
            """)
        let settings = try TeammateSettings(
            table: table, environment: ["HUMANOID_LLM_MODEL": "other", "HUMANOID_LLM_API_KEY": "k"])
        #expect(settings.userName == "Alex")
        #expect(settings.chatBaseURL.absoluteString == "http://127.0.0.1:9000/v1")
        #expect(settings.model == "other")
        #expect(settings.apiKey == "k")
        #expect(settings.speechBaseURL.absoluteString == "http://127.0.0.1:9000/v1")
        #expect(settings.transcriptionBaseURL == TeammateSettings.defaults.transcriptionBaseURL)
    }

    @Test func aMissingFileMeansDefaultsAndABrokenOneIsReportedWithItsPath() throws {
        let folder = temporaryFolder()
        #expect(try TeammateLibrary.loadSettings(environment: ["HUMANOID_CONFIG_DIR": folder.path]) == .defaults)
        try "[llm\n".write(to: folder.appendingPathComponent("settings.toml"), atomically: true, encoding: .utf8)
        let library = TeammateLibrary.load(environment: ["HUMANOID_CONFIG_DIR": folder.path])
        #expect(library.settings == .defaults)
        #expect(library.problems.count == 1 && library.problems[0].contains("settings.toml"))
        #expect(throws: SettingsError.self) {
            try TeammateSettings(table: ["llm": .table(["base_url": .string("not a url")])], environment: [:])
        }
    }

    @Test func theSettingsFileIsCreatedOnceAndNeverReplaced() throws {
        let environment = ["HUMANOID_CONFIG_DIR": temporaryFolder().path]
        let file = try TeammateLibrary.ensureSettingsFile(environment: environment)
        #expect(try String(contentsOf: file, encoding: .utf8) == TeammateLibrary.settingsTemplate)
        try "# mine\n".write(to: file, atomically: true, encoding: .utf8)
        _ = try TeammateLibrary.ensureSettingsFile(environment: environment)
        #expect(try String(contentsOf: file, encoding: .utf8) == "# mine\n")
    }
}

@Suite struct TeammateFileTests {
    @Test func startsFromABuiltInTeammateAndOverridesIt() throws {
        let file = try write(
            "nova.toml",
            """
            name = "Nova"
            based_on = "tempo"
            accessory = "none"
            dances = false
            role = "Your role: you tell short, true stories about space."
            [colours]
            glow = "#9fd0ff"
            """)
        let nova = try TeammateFile.load(file)
        #expect(nova.key == "nova" && nova.name == "Nova" && nova.accessory == .noAccessory)
        #expect(nova.voice == Teammate.tempo.voice && nova.colours.screen == Teammate.tempo.colours.screen)
        #expect(nova.colours.glow == RGB(159, 208, 255))
        #expect(nova.origin == .file(file))
        #expect(nova.persona(userName: "Alex").contains("stories about space"))
    }

    @Test(arguments: [
        ("accessory = \"hat\"", "accessory"), ("resting_expression = \"angry\"", "resting_expression"),
        ("based_on = \"nobody\"", "based_on"), ("[colours]\nglow = \"blue\"", "colours.glow"),
        ("role = \"  \"", "role"),
    ])
    func aWrongFileNamesTheFileAndTheField(content: String, field: String) throws {
        let file = try write("oops.toml", content)
        #expect {
            try TeammateFile.load(file)
        } throws: { error in
            let message = String(describing: error)
            return message.contains("oops.toml") && message.contains(field)
        }
    }

    @Test func theCatalogKeepsGoingPastABrokenFile() throws {
        let folder = try write("byte.toml", "name = \"Byte 2\"\n").deletingLastPathComponent()
        try "accessory = \"hat\"\n".write(
            to: folder.appendingPathComponent("zed.toml"), atomically: true, encoding: .utf8)
        let catalog = TeammateCatalog.load(directory: folder)
        #expect(catalog.teammates.map(\.key) == ["byte", "tempo"])
        #expect(catalog.teammate(key: "byte")?.name == "Byte 2")  // byte.toml changes Byte
        #expect(catalog.teammate(key: "byte")?.role == Teammate.byte.role)
        #expect(catalog.problems.count == 1 && catalog.problems[0].contains("zed.toml"))
    }
}

/// Files written by humanoid-companion itself: both apps must read the same files.
@Suite struct SharedFormatTests {
    private var fixtures: URL {
        get throws { try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)) }
    }

    @Test func theCompanionsSettingsTemplateIsOurs() throws {
        let companion = try String(contentsOf: fixtures.appendingPathComponent("settings.toml"), encoding: .utf8)
        #expect(TeammateLibrary.settingsTemplate == companion)
        let settings = try TeammateSettings(table: Toml.parse(companion), environment: [:])
        #expect(settings.speechBaseURL.absoluteString == "http://127.0.0.1:8880/v1")
    }

    @Test func aTeammateFileWrittenByTheCompanionLoads() throws {
        let nova = try TeammateFile.load(fixtures.appendingPathComponent("nova.toml"))
        #expect(
            nova.name == "Nova" && nova.accessory == .headphones && nova.colours.glow == Teammate.tempo.colours.glow)
        #expect(nova.role.hasPrefix("Your role: you are a singer."))
    }
}

func temporaryFolder() -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private func write(_ name: String, _ text: String) throws -> URL {
    let file = temporaryFolder().appendingPathComponent(name)
    try text.write(to: file, atomically: true, encoding: .utf8)
    return file
}
