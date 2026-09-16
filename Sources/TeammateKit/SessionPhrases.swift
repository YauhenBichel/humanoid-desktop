/// Everything the teammate shows or says that does not come from the model: greetings, apologies, notices.
///
/// The English defaults keep TeammateKit free of platform resources. An app passes its own, localized for the
/// person's system language and naming its own shortcut and settings (the macOS app uses its String Catalog).
public struct SessionPhrases: Sendable {
    public var thinking: String
    public var listening: String
    public var holdToTalk: String
    public var stopping: String
    public var didNotCatchThat: String
    public var noAnswer: String
    public var couldNotHear: String
    public var microphoneOff: String
    public var greeting: @Sendable (_ userName: String, _ teammate: Teammate) -> String
    public var chatServerFailed: @Sendable (_ server: String, _ reason: String) -> String
    public var speechServerFailed: @Sendable (_ server: String) -> String
    public var transcriptionServerFailed: @Sendable (_ server: String, _ reason: String) -> String
    public var microphoneFailed: @Sendable (_ reason: String) -> String

    public init(
        thinking: String,
        listening: String,
        holdToTalk: String,
        stopping: String,
        didNotCatchThat: String,
        noAnswer: String,
        couldNotHear: String,
        microphoneOff: String,
        greeting: @escaping @Sendable (_ userName: String, _ teammate: Teammate) -> String,
        chatServerFailed: @escaping @Sendable (_ server: String, _ reason: String) -> String,
        speechServerFailed: @escaping @Sendable (_ server: String) -> String,
        transcriptionServerFailed: @escaping @Sendable (_ server: String, _ reason: String) -> String,
        microphoneFailed: @escaping @Sendable (_ reason: String) -> String
    ) {
        self.thinking = thinking
        self.listening = listening
        self.holdToTalk = holdToTalk
        self.stopping = stopping
        self.didNotCatchThat = didNotCatchThat
        self.noAnswer = noAnswer
        self.couldNotHear = couldNotHear
        self.microphoneOff = microphoneOff
        self.greeting = greeting
        self.chatServerFailed = chatServerFailed
        self.speechServerFailed = speechServerFailed
        self.transcriptionServerFailed = transcriptionServerFailed
        self.microphoneFailed = microphoneFailed
    }

    public static let english = SessionPhrases(
        thinking: "…",
        listening: "I'm listening…",
        holdToTalk: "Hold the talk shortcut while you speak.",
        stopping: "Okay, I'll be quiet.",
        didNotCatchThat: "Sorry, I did not catch that.",
        noAnswer: "Sorry, I could not think of an answer just now.",
        couldNotHear: "Sorry, I could not hear that.",
        microphoneOff: "Microphone access is off. Allow it in your system's privacy settings.",
        greeting: { userName, teammate in
            "Hi\(userName.isEmpty ? "" : ", \(userName)")! I'm \(teammate.name): I \(teammate.tagline)."
        },
        chatServerFailed: { server, reason in "No answer from the chat server at \(server): \(reason)" },
        speechServerFailed: { server in "No voice: the speech server at \(server) did not answer." },
        transcriptionServerFailed: { server, reason in "No transcription from \(server): \(reason)" },
        microphoneFailed: { reason in "Could not start the microphone: \(reason)" }
    )
}
