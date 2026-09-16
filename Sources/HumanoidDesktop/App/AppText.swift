import Foundation
import TeammateKit

/// Every piece of text the app shows, looked up in `Resources/<language>.lproj/Localizable.strings` by key, with
/// English as the fallback. Translating the app means adding one strings file; nothing else changes.
enum AppText {
    static func teammateMenuItem(_ teammate: Teammate) -> String {
        String(localized: "menu.teammate", defaultValue: "\(teammate.name): \(teammate.tagline)", bundle: .module)
    }

    static func hide(_ name: String) -> String {
        String(localized: "menu.hide", defaultValue: "Hide \(name)", bundle: .module)
    }

    static func show(_ name: String) -> String {
        String(localized: "menu.show", defaultValue: "Show \(name)", bundle: .module)
    }

    static var typeMessage: String {
        String(localized: "menu.typeMessage", defaultValue: "Type a Message", bundle: .module)
    }

    static func talkHint(_ shortcut: String) -> String {
        String(localized: "menu.talkHint", defaultValue: "Talk: hold \(shortcut)", bundle: .module)
    }

    static var openSettings: String {
        String(localized: "menu.openSettings", defaultValue: "Open Settings File…", bundle: .module)
    }

    static var reload: String {
        String(localized: "menu.reload", defaultValue: "Reload Settings and Teammates", bundle: .module)
    }

    static var quit: String {
        String(localized: "menu.quit", defaultValue: "Quit Humanoid Desktop", bundle: .module)
    }

    static var statusItemDescription: String {
        String(localized: "statusItem.description", defaultValue: "Humanoid teammate", bundle: .module)
    }

    static func characterHelp(_ name: String, shortcut: String) -> String {
        String(
            localized: "window.characterHelp",
            defaultValue: "\(name): click to type, hold \(shortcut) to talk, right-click for more", bundle: .module)
    }

    static func askPlaceholder(_ name: String) -> String {
        String(localized: "window.askPlaceholder", defaultValue: "Ask \(name)…", bundle: .module)
    }

    static func holdToTalkHelp(_ shortcut: String) -> String {
        String(localized: "window.holdToTalkHelp", defaultValue: "Hold \(shortcut) to talk", bundle: .module)
    }

    static func closeHelp(_ name: String, shortcut: String) -> String {
        String(
            localized: "window.closeHelp",
            defaultValue: "Hide \(name) (⌘W or Esc). Show it again from the menu bar, or by holding \(shortcut).",
            bundle: .module)
    }

    static func characterAccessibility(_ name: String, expression: FaceExpression) -> String {
        String(
            localized: "character.accessibility", defaultValue: "\(name), looking \(expression.rawValue)",
            bundle: .module)
    }

    /// The session's phrases in the person's language, naming this app's shortcut and settings.
    static func sessionPhrases(shortcut: String) -> SessionPhrases {
        SessionPhrases(
            thinking: String(localized: "phrase.thinking", defaultValue: "…", bundle: .module),
            listening: String(localized: "phrase.listening", defaultValue: "I'm listening…", bundle: .module),
            holdToTalk: String(
                localized: "phrase.holdToTalk", defaultValue: "Hold \(shortcut) while you speak.", bundle: .module),
            stopping: String(localized: "phrase.stopping", defaultValue: "Okay, I'll be quiet.", bundle: .module),
            didNotCatchThat: String(
                localized: "phrase.didNotCatchThat", defaultValue: "Sorry, I did not catch that.", bundle: .module),
            noAnswer: String(
                localized: "phrase.noAnswer", defaultValue: "Sorry, I could not think of an answer just now.",
                bundle: .module),
            couldNotHear: String(
                localized: "phrase.couldNotHear", defaultValue: "Sorry, I could not hear that.", bundle: .module),
            microphoneOff: String(
                localized: "phrase.microphoneOff",
                defaultValue: "Microphone access is off: System Settings > Privacy & Security > Microphone.",
                bundle: .module),
            greeting: { userName, teammate in
                userName.isEmpty
                    ? String(
                        localized: "phrase.greeting",
                        defaultValue: "Hi! I'm \(teammate.name): I \(teammate.tagline).", bundle: .module)
                    : String(
                        localized: "phrase.greetingNamed",
                        defaultValue: "Hi, \(userName)! I'm \(teammate.name): I \(teammate.tagline).", bundle: .module)
            },
            chatServerFailed: { server, reason in
                String(
                    localized: "phrase.chatServerFailed",
                    defaultValue: "No answer from the chat server at \(server): \(reason)", bundle: .module)
            },
            speechServerFailed: { server in
                String(
                    localized: "phrase.speechServerFailed",
                    defaultValue: "No voice: the speech server at \(server) did not answer.", bundle: .module)
            },
            transcriptionServerFailed: { server, reason in
                String(
                    localized: "phrase.transcriptionServerFailed",
                    defaultValue: "No transcription from \(server): \(reason)", bundle: .module)
            },
            microphoneFailed: { reason in
                String(
                    localized: "phrase.microphoneFailed", defaultValue: "Could not start the microphone: \(reason)",
                    bundle: .module)
            }
        )
    }
}
