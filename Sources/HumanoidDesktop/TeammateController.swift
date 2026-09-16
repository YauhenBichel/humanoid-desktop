import AppKit
import Foundation
import TeammateKit

/// The teammate's state and what it does: answer a message, speak, listen while the shortcut is held.
/// The views only show this state; the menu bar item and the shortcut call its methods.
@MainActor
final class TeammateController: ObservableObject {
    @Published private(set) var teammates: [Teammate] = Teammate.builtIn
    @Published private(set) var teammate: Teammate = .byte
    @Published private(set) var expression: FaceExpression = .neutral
    @Published private(set) var bubble = ""  // what the teammate said last
    @Published private(set) var status = ""  // a problem worth showing: a server that does not answer, a broken file
    @Published private(set) var isBusy = false
    @Published private(set) var isListening = false
    @Published var isChatOpen = false
    @Published var draft = ""

    /// The voice's loudness 0...1; read by the character on every frame, so it is not @Published.
    private(set) var mouthLevel = 0.0

    private var settings = Settings.defaults
    private var conversation: Conversation?
    private let player = VoicePlayer()
    private let recorder = VoiceRecorder()
    private static let chosenTeammateKey = "teammate"

    init() {
        reload()
    }

    /// Read settings.toml and the teammate files again (menu: Reload Settings).
    func reload() {
        var problems: [String] = []
        do {
            settings = try Settings.load()
        } catch {
            settings = .defaults
            problems.append("\(error)")
        }
        let loaded = Teammate.all(directory: Settings.configDirectory().appendingPathComponent("teammates"))
        teammates = loaded.teammates
        problems += loaded.problems
        let chosen = UserDefaults.standard.string(forKey: Self.chosenTeammateKey)
        choose(teammates.first(where: { $0.key == chosen }) ?? teammates.first(where: { $0.key == teammate.key }) ?? .byte)
        status = problems.joined(separator: "\n")
    }

    func choose(_ newTeammate: Teammate) {
        player.stop()
        teammate = newTeammate
        UserDefaults.standard.set(newTeammate.key, forKey: Self.chosenTeammateKey)
        conversation = Conversation(teammate: newTeammate, userName: settings.userName, chat: ChatClient(settings: settings))
        expression = newTeammate.restingExpression
        bubble = "Hi\(settings.userName.isEmpty ? "" : ", \(settings.userName)")! I'm \(newTeammate.name): I \(newTeammate.tagline)."
    }

    func send(_ text: String) {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty, !isBusy, let conversation else { return }
        draft = ""
        isBusy = true
        expression = .thinking
        bubble = "…"
        player.stop()
        Task {
            let reply = await conversation.respond(to: said)
            expression = reply.expression
            bubble = reply.say
            status = reply.source == .fallback && !reply.error.isEmpty
                ? "No answer from the chat server at \(settings.chatBaseURL.absoluteString): \(reply.error)" : ""
            if reply.source != .stopWord {
                await speak(reply.say)
            }
            isBusy = false
        }
    }

    private func speak(_ text: String) async {
        do {
            let wav = try await SpeechClient(settings: settings).speak(text, voice: teammate.voice)
            try player.play(wav, level: { [weak self] level in self?.mouthLevel = level }, finished: {})
        } catch {
            // Without a speech server the teammate still answers, in the bubble only.
            status = "No voice: the speech server at \(settings.speechBaseURL.absoluteString) did not answer."
        }
    }

    // MARK: hold to talk

    func startListening() {
        guard !isListening, !isBusy else { return }
        Task {
            guard await VoiceRecorder.requestPermission() else {
                status = "Microphone access is off: System Settings > Privacy & Security > Microphone."
                return
            }
            do {
                player.stop()
                try recorder.start()
                isListening = true
                expression = .listening
                bubble = "I'm listening…"
            } catch {
                status = "Could not start the microphone: \(error)"
            }
        }
    }

    func stopListening() {
        guard isListening else { return }
        isListening = false
        guard let wav = recorder.stop() else {
            expression = teammate.restingExpression
            bubble = "Hold ⌥Space while you speak."
            return
        }
        isBusy = true
        expression = .thinking
        bubble = "…"
        Task {
            do {
                let heard = try await SpeechClient(settings: settings).transcribe(wav: wav)
                isBusy = false
                draft = heard
                send(heard)
            } catch {
                isBusy = false
                expression = .sad
                bubble = "Sorry, I could not hear that."
                status = "No transcription from \(settings.transcriptionBaseURL.absoluteString): \(error)"
            }
        }
    }

    // MARK: menu actions

    func openSettingsFolder() {
        do {
            let file = try Settings.ensureFile()
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } catch {
            status = "Could not create the settings file: \(error)"
        }
    }
}
