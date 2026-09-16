import Foundation
import Testing

@testable import TeammateKit

@Suite struct LanguageTests {
    @Test(arguments: ["de", "DE", " pt-BR ", "fil"])
    func acceptsLanguageCodes(code: String) {
        #expect(Language(code: code) != nil)
    }

    @Test(arguments: ["", "german", "d", "de_DE", "12"])
    func rejectsWhatIsNotALanguageCode(code: String) {
        #expect(Language(code: code) == nil)
    }

    @Test func namesTheLanguageInEnglishForTheModel() throws {
        #expect(try #require(Language(code: "de")).englishName == "German")
        #expect(try #require(Language(code: "pt-br")).baseCode == "pt")
    }

    @Test func englishStopWordsAlwaysWorkAndTheAnswerLanguageAddsItsOwn() throws {
        let belarusian = try #require(Language(code: "be"))
        #expect(ReplyRules.containsStopWord("Хопіць, калі ласка", language: belarusian))
        #expect(ReplyRules.containsStopWord("stop please", language: belarusian))
        #expect(!ReplyRules.containsStopWord("Хопіць, калі ласка"))  // not a stop word in English
        #expect(!ReplyRules.containsStopWord("Wie ruhig ist der See?", language: Language(code: "de")))
    }

    @Test func thePersonaAsksForTheAnswerLanguage() throws {
        let german = Teammate.byte.persona(userName: "Alex", language: Language(code: "de"))
        #expect(german.contains("Always answer in German"))
        #expect(german.contains("keep these names in English"))
        #expect(Teammate.byte.persona(userName: "Alex").contains("Answer in the language the person writes in."))
    }

    @Test func aTeammateSpeaksWithTheVoiceForTheAnswerLanguage() throws {
        var byte = Teammate.byte
        byte.voicesByLanguage = ["es": "ef_dora"]
        #expect(byte.voice(for: Language(code: "es")) == "ef_dora")
        #expect(byte.voice(for: Language(code: "es-mx")) == "ef_dora")
        #expect(byte.voice(for: Language(code: "fr")) == "af_heart")
        #expect(byte.voice(for: nil) == "af_heart")
    }

    @Test func voicesAndTheLanguageComeFromTheFiles() throws {
        let folder = temporaryFolder()
        let file = folder.appendingPathComponent("lingo.toml")
        try "[voices]\nes = \"ef_dora\"\nfr = \"ff_siwis\"\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(try TeammateFile.load(file).voicesByLanguage == ["es": "ef_dora", "fr": "ff_siwis"])

        let settings = try TeammateSettings(table: ["user": .table(["language": .string("es")])], environment: [:])
        #expect(settings.language?.code == "es")
        #expect(throws: SettingsError.self) {
            try TeammateSettings(table: ["user": .table(["language": .string("Spanish")])], environment: [:])
        }
        let fromEnvironment = try TeammateSettings(table: [:], environment: ["HUMANOID_LANGUAGE": "uk"])
        #expect(fromEnvironment.language?.code == "uk")
    }
}

@Suite struct SettingsFolderTests {
    private let home = URL(fileURLWithPath: "/home/alex", isDirectory: true)

    @Test func followsEachSystemsConvention() {
        let unix = TeammateLibrary.folder(environment: [:], platform: .unixLike, homeDirectory: home)
        #expect(unix.path == "/home/alex/.config/humanoid-companion")
        let xdg = TeammateLibrary.folder(
            environment: ["XDG_CONFIG_HOME": "/cfg"], platform: .unixLike, homeDirectory: home)
        #expect(xdg.path == "/cfg/humanoid-companion")
        let windows = TeammateLibrary.folder(
            environment: ["APPDATA": "/appdata"], platform: .windows, homeDirectory: home)
        #expect(windows.path == "/appdata/humanoid-companion")
        let windowsFallback = TeammateLibrary.folder(environment: [:], platform: .windows, homeDirectory: home)
        #expect(windowsFallback.path == "/home/alex/AppData/Roaming/humanoid-companion")
    }

    @Test func anExplicitFolderWinsEverywhere() {
        for platform in [TeammateLibrary.Platform.unixLike, .windows] {
            let folder = TeammateLibrary.folder(
                environment: ["HUMANOID_CONFIG_DIR": "~/teammates-config", "APPDATA": "/appdata"], platform: platform,
                homeDirectory: home)
            #expect(folder.path == "/home/alex/teammates-config")
        }
    }
}

@MainActor
@Suite struct PhrasesTests {
    @Test func theSessionUsesThePhrasesItIsGiven() async {
        var phrases = SessionPhrases.english
        phrases.greeting = { _, teammate in "Прывітанне! Я \(teammate.name)." }
        phrases.stopping = "Добра, маўчу."
        let session = TeammateSession(
            player: FakePlayer(), recorder: FakeRecorder(), choices: MemoryChoices(), phrases: phrases
        ) { _ in
            .init(chat: CannedChat(say: "Hi"), speech: FixedSpeech(), transcription: FixedTranscription())
        }
        session.configure(with: TeammateLibrary(settings: .defaults, catalog: .builtIn, problems: []))
        #expect(session.bubble == "Прывітанне! Я Byte.")
        session.send("stop")
        for _ in 0..<100 where session.bubble != "Добра, маўчу." { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(session.bubble == "Добра, маўчу.")
    }
}
