import Foundation
import TeammateKit

/// Every piece of text the app shows, looked up in `Resources/<language>.lproj/Localizable.strings` by key, with
/// English as the fallback. Translating the app means adding one strings file; nothing else changes.
enum AppText {
    static func teammateMenuItem(_ teammate: Teammate) -> String {
        String(localized: "menu.teammate", defaultValue: "\(teammate.name): \(teammate.tagline)", bundle: .app)
    }

    static func hide(_ name: String) -> String {
        String(localized: "menu.hide", defaultValue: "Hide \(name)", bundle: .app)
    }

    static func show(_ name: String) -> String {
        String(localized: "menu.show", defaultValue: "Show \(name)", bundle: .app)
    }

    static var typeMessage: String {
        String(localized: "menu.typeMessage", defaultValue: "Type a Message", bundle: .app)
    }

    static func talkHint(_ shortcut: String) -> String {
        String(localized: "menu.talkHint", defaultValue: "Talk: hold \(shortcut)", bundle: .app)
    }

    static func forgetMemory(_ name: String) -> String {
        String(localized: "menu.forgetMemory", defaultValue: "Forget What \(name) Remembers…", bundle: .app)
    }

    static func forgetMemoryQuestion(_ name: String) -> String {
        String(localized: "alert.forgetMemory.title", defaultValue: "Forget what \(name) remembers?", bundle: .app)
    }

    static func forgetMemoryDetail(_ name: String) -> String {
        String(
            localized: "alert.forgetMemory.detail",
            defaultValue:
                "\(name) forgets the facts you shared and your earlier conversations. This cannot be undone.",
            bundle: .app)
    }

    static var forget: String { String(localized: "alert.forget", defaultValue: "Forget", bundle: .app) }
    static var cancel: String { String(localized: "alert.cancel", defaultValue: "Cancel", bundle: .app) }

    static var openSettings: String {
        String(localized: "menu.openSettings", defaultValue: "Open Settings File…", bundle: .app)
    }

    static var reload: String {
        String(localized: "menu.reload", defaultValue: "Reload Settings and Teammates", bundle: .app)
    }

    static var quit: String {
        String(localized: "menu.quit", defaultValue: "Quit Humanoid Desktop", bundle: .app)
    }

    static var statusItemDescription: String {
        String(localized: "statusItem.description", defaultValue: "Humanoid teammate", bundle: .app)
    }

    static func characterHelp(_ name: String, shortcut: String) -> String {
        String(
            localized: "window.characterHelp",
            defaultValue: "\(name): click to type, hold \(shortcut) to talk, right-click for more", bundle: .app)
    }

    static func askPlaceholder(_ name: String) -> String {
        String(localized: "window.askPlaceholder", defaultValue: "Ask \(name)…", bundle: .app)
    }

    static func holdToTalkHelp(_ shortcut: String) -> String {
        String(localized: "window.holdToTalkHelp", defaultValue: "Hold \(shortcut) to talk", bundle: .app)
    }

    static func closeHelp(_ name: String, shortcut: String) -> String {
        String(
            localized: "window.closeHelp",
            defaultValue: "Hide \(name) (⌘W or Esc). Show it again from the menu bar, or by holding \(shortcut).",
            bundle: .app)
    }

    static func characterAccessibility(_ name: String, expression: FaceExpression) -> String {
        String(
            localized: "character.accessibility", defaultValue: "\(name), looking \(expression.rawValue)",
            bundle: .app)
    }

    /// The session's phrases in the person's language, naming this app's shortcut and settings.
    static func sessionPhrases(shortcut: String) -> SessionPhrases {
        SessionPhrases(
            thinking: String(localized: "phrase.thinking", defaultValue: "…", bundle: .app),
            listening: String(localized: "phrase.listening", defaultValue: "I'm listening…", bundle: .app),
            holdToTalk: String(
                localized: "phrase.holdToTalk", defaultValue: "Hold \(shortcut) while you speak.", bundle: .app),
            stopping: String(localized: "phrase.stopping", defaultValue: "Okay, I'll be quiet.", bundle: .app),
            didNotCatchThat: String(
                localized: "phrase.didNotCatchThat", defaultValue: "Sorry, I did not catch that.", bundle: .app),
            noAnswer: String(
                localized: "phrase.noAnswer", defaultValue: "Sorry, I could not think of an answer just now.",
                bundle: .app),
            couldNotHear: String(
                localized: "phrase.couldNotHear", defaultValue: "Sorry, I could not hear that.", bundle: .app),
            microphoneOff: String(
                localized: "phrase.microphoneOff",
                defaultValue: "Microphone access is off: System Settings > Privacy & Security > Microphone.",
                bundle: .app),
            greeting: { userName, teammate in
                userName.isEmpty
                    ? String(
                        localized: "phrase.greeting",
                        defaultValue: "Hi! I'm \(teammate.name): I \(teammate.tagline).", bundle: .app)
                    : String(
                        localized: "phrase.greetingNamed",
                        defaultValue: "Hi, \(userName)! I'm \(teammate.name): I \(teammate.tagline).", bundle: .app)
            },
            chatServerFailed: { server, reason in
                String(
                    localized: "phrase.chatServerFailed",
                    defaultValue: "No answer from the chat server at \(server): \(reason)", bundle: .app)
            },
            speechServerFailed: { server in
                String(
                    localized: "phrase.speechServerFailed",
                    defaultValue: "No voice: the speech server at \(server) did not answer.", bundle: .app)
            },
            transcriptionServerFailed: { server, reason in
                String(
                    localized: "phrase.transcriptionServerFailed",
                    defaultValue: "No transcription from \(server): \(reason)", bundle: .app)
            },
            microphoneFailed: { reason in
                String(
                    localized: "phrase.microphoneFailed", defaultValue: "Could not start the microphone: \(reason)",
                    bundle: .app)
            },
            forgotten: { teammate in
                String(
                    localized: "phrase.forgotten",
                    defaultValue: "Done: I forgot everything I remembered. I'm \(teammate.name), nice to meet you!",
                    bundle: .app)
            },
            memoryFailed: { reason in
                String(
                    localized: "phrase.memoryFailed", defaultValue: "Could not keep what I remember: \(reason)",
                    bundle: .app)
            }
        )
    }
}
