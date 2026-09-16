import Foundation
import Testing

@testable import TeammateKit

// MARK: - TOML

@Test func tomlReadsTheSettingsAndTeammateSubset() throws {
    let table = try Toml.parse(
        """
        # a comment
        name = "Nova" # trailing comment
        dances = false
        size = 1_000
        role = \"\"\"Your role: you
        tell # not a comment
        stories.\"\"\"
        literal = 'C:\\path'

        [colours]
        glow = "#9fd0ff"
        """)
    #expect(table["name"] == .string("Nova"))
    #expect(table["dances"] == .bool(false))
    #expect(table["size"] == .number(1000))
    #expect(table["role"]?.string == "Your role: you\ntell # not a comment\nstories.")
    #expect(table["literal"]?.string == "C:\\path")
    #expect(table["colours"]?.table?["glow"] == .string("#9fd0ff"))
}

@Test(arguments: ["name = ", "[colours", "name = \"unclosed", "a = [1, 2]", "x = 1\nx = 2", "role = \"\"\"never closed"])
func tomlRejectsWhatItDoesNotUnderstand(text: String) {
    #expect(throws: Toml.ParseError.self) { try Toml.parse(text) }
}

// MARK: - Settings

@Test func settingsComeFromTheFileAndTheEnvironmentWins() throws {
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
    let settings = try Settings.resolve(table: table, environment: ["HUMANOID_LLM_MODEL": "other", "HUMANOID_LLM_API_KEY": "k"])
    #expect(settings.userName == "Alex")
    #expect(settings.chatBaseURL.absoluteString == "http://127.0.0.1:9000/v1")
    #expect(settings.model == "other")
    #expect(settings.apiKey == "k")
    #expect(settings.speechBaseURL.absoluteString == "http://127.0.0.1:9000/v1")
    #expect(settings.transcriptionBaseURL == Settings.defaults.transcriptionBaseURL)
}

@Test func aMissingSettingsFileMeansDefaultsAndABrokenOneSaysWhere() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    #expect(try Settings.load(environment: ["HUMANOID_CONFIG_DIR": folder.path]) == .defaults)
    try "[llm\n".write(to: folder.appendingPathComponent("settings.toml"), atomically: true, encoding: .utf8)
    #expect(throws: SettingsError.self) { try Settings.load(environment: ["HUMANOID_CONFIG_DIR": folder.path]) }
    #expect(throws: SettingsError.self) {
        try Settings.resolve(table: ["llm": .table(["base_url": .string("not a url")])], environment: [:])
    }
}

// MARK: - Teammates

private func teammateFile(_ name: String, _ text: String) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent(name)
    try text.write(to: file, atomically: true, encoding: .utf8)
    return file
}

@Test func aTeammateFileStartsFromABuiltInAndOverridesIt() throws {
    let file = try teammateFile(
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
    let nova = try Teammate.load(file: file)
    #expect(nova.key == "nova" && nova.name == "Nova" && nova.accessory == Accessory.none)
    #expect(nova.voice == Teammate.tempo.voice && nova.background == Teammate.tempo.background)
    #expect(nova.glow == RGB(159, 208, 255))
    #expect(nova.persona(userName: "Alex").contains("stories about space"))
}

@Test(arguments: [
    ("accessory = \"hat\"", "accessory"), ("resting_expression = \"angry\"", "resting_expression"),
    ("based_on = \"nobody\"", "based_on"), ("[colours]\nglow = \"blue\"", "colours.glow"), ("role = \"  \"", "role"),
])
func aWrongTeammateFileNamesTheFileAndTheField(content: String, field: String) throws {
    let file = try teammateFile("oops.toml", content)
    do {
        _ = try Teammate.load(file: file)
        Issue.record("expected an error for \(field)")
    } catch let error as TeammateError {
        #expect(error.message.contains("oops.toml") && error.message.contains(field))
    }
}

@Test func allTeammatesKeepGoingPastABrokenFile() throws {
    let good = try teammateFile("byte.toml", "name = \"Byte 2\"\n")
    let folder = good.deletingLastPathComponent()
    try "accessory = \"hat\"\n".write(to: folder.appendingPathComponent("zed.toml"), atomically: true, encoding: .utf8)
    let (teammates, problems) = Teammate.all(directory: folder)
    #expect(teammates.map(\.key) == ["byte", "tempo"])
    #expect(teammates[0].name == "Byte 2" && teammates[0].role == Teammate.byte.role)  // byte.toml changes Byte
    #expect(problems.count == 1 && problems[0].contains("zed.toml"))
}

@Test func thePersonaNamesThePersonAndNeverSaysOwner() {
    let persona = Teammate.byte.persona(userName: "Alex")
    #expect(persona.hasPrefix("You are Byte, a humanoid teammate"))
    #expect(persona.contains("call Alex by name") && persona.contains("computer science"))
    #expect(!Teammate.tempo.persona(userName: "").contains("Alex"))
    #expect(persona.hasSuffix("Answer only with the JSON object."))
}

// MARK: - Conversation

private struct FakeChat: ChatCompleting {
    let answer: @Sendable ([[String: String]]) throws -> String
    func complete(messages: [[String: String]], schema: [String: Any]) async throws -> String { try answer(messages) }
}

@Test func aReplyIsCheckedAndRemembered() async {
    let chat = FakeChat { _ in #"{"say": "A stack is last in, first out.", "expression": "happy"}"# }
    let conversation = Conversation(teammate: .byte, userName: "Alex", chat: chat)
    let reply = await conversation.respond(to: "what is a stack?")
    #expect(reply == Reply(say: "A stack is last in, first out.", expression: .happy))
    #expect(conversation.history.count == 2 && conversation.history[0]["content"] == "what is a stack?")
}

@Test func historyIsBounded() async {
    let conversation = Conversation(teammate: .byte, userName: "", chat: FakeChat { _ in #"{"say": "Sure.", "expression": "neutral"}"# })
    for index in 0..<10 { _ = await conversation.respond(to: "question \(index)") }
    #expect(conversation.history.count == Conversation.maximumHistory)
    #expect(conversation.history[conversation.history.count - 2]["content"] == "question 9")
}

@Test(arguments: ["stop", "Please be quiet", "halt!"])
func stopWordsNeverReachTheModel(said: String) async {
    let conversation = Conversation(teammate: .tempo, userName: "", chat: FakeChat { _ in
        Issue.record("the model must not be asked")
        return ""
    })
    #expect(await conversation.respond(to: said).source == .stopWord)
}

@Test(arguments: ["not json", #"{"say": ""}"#, #"["hi"]"#])
func unusableAnswersGetAnApology(raw: String) async {
    let reply = await Conversation(teammate: .byte, userName: "", chat: FakeChat { _ in raw }).respond(to: "hello")
    #expect(reply.source == .fallback && reply.expression == .sad && !reply.error.isEmpty)
}

@Test func anUnknownExpressionBecomesNeutralAndLongSpeechIsCutAtASentence() throws {
    #expect(try ReplyParsing.parse(#"{"say": "Hi", "expression": "furious"}"#).expression == .neutral)
    let long = String(repeating: "This sentence is here. ", count: 40)
    let cut = ReplyParsing.trimSpoken(long)
    #expect(cut.count <= Reply.maximumSpoken && cut.hasSuffix("."))
}

// MARK: - Clients

@Test func theChatRequestAsksForTheSchemaAndTheModel() throws {
    var settings = Settings.defaults
    settings.model = "qwen3:8b"
    let request = try ChatClient(settings: settings).request(messages: [["role": "user", "content": "hi"]], schema: ReplyParsing.schema)
    #expect(request.url?.absoluteString == "http://127.0.0.1:11434/v1/chat/completions")
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    #expect(body["model"] as? String == "qwen3:8b")
    let format = body["response_format"] as! [String: Any]
    #expect(format["type"] as? String == "json_schema")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func speechAndTranscriptionRequestsUseTheOpenAIWire() throws {
    let client = SpeechClient(settings: .defaults)
    let speech = try client.speechRequest(text: "Hello", voice: "af_heart")
    #expect(speech.url?.absoluteString == "http://127.0.0.1:8880/v1/audio/speech")
    let body = try JSONSerialization.jsonObject(with: speech.httpBody!) as! [String: String]
    #expect(body == ["model": "tts-1", "input": "Hello", "voice": "af_heart", "response_format": "wav"])
    let transcription = client.transcriptionRequest(wav: Data([1, 2, 3]), boundary: "B")
    #expect(transcription.url?.absoluteString == "http://127.0.0.1:8000/v1/audio/transcriptions")
    let text = String(decoding: transcription.httpBody!, as: UTF8.self)
    #expect(text.contains("name=\"model\"\r\n\r\nwhisper-1") && text.contains("filename=\"speech.wav\"") && text.hasSuffix("--B--\r\n"))
}

@Test func everyExpressionHasItsOwnShape() {
    let shapes = FaceExpression.allCases.map(\.shape)
    for (index, shape) in shapes.enumerated() {
        #expect(!shapes[(index + 1)...].contains(shape))
    }
}

// MARK: - The same files as humanoid-companion

@Test func filesWrittenByHumanoidCompanionLoad() throws {
    let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    let settingsTable = try Toml.parse(try String(contentsOf: fixtures.appendingPathComponent("settings.toml"), encoding: .utf8))
    #expect(try Settings.resolve(table: settingsTable, environment: [:]).speechBaseURL.absoluteString == "http://127.0.0.1:8880/v1")
    let nova = try Teammate.load(file: fixtures.appendingPathComponent("nova.toml"))
    #expect(nova.name == "Nova" && nova.accessory == .headphones && nova.glow == Teammate.tempo.glow)
    #expect(nova.role.hasPrefix("Your role: you are a singer."))
}

@Test func theSettingsTemplateIsTheCompanionsAndIsCreatedOnce() throws {
    let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    #expect(Settings.template == (try String(contentsOf: fixtures.appendingPathComponent("settings.toml"), encoding: .utf8)))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let file = try Settings.ensureFile(environment: ["HUMANOID_CONFIG_DIR": folder.path])
    try "# mine\n".write(to: file, atomically: true, encoding: .utf8)
    _ = try Settings.ensureFile(environment: ["HUMANOID_CONFIG_DIR": folder.path])
    #expect(try String(contentsOf: file, encoding: .utf8) == "# mine\n")  // an existing file is never replaced
}
