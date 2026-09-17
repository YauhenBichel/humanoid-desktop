import AppKit
import TeammateKit

/// The composition root: builds the session with its real services and phrases, then the window, the menu bar
/// item and the talk shortcut, and connects them. Nothing else creates platform objects.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let talkCombination = TalkShortcut.Combination.optionSpace

    private let session = TeammateSession(
        player: AudioPlayer(), recorder: AudioRecorder(), choices: UserDefaultsChoiceStore(),
        memories: FileMemoryStore.standard(),
        phrases: AppText.sessionPhrases(shortcut: AppDelegate.talkCombination.displayName))
    private var panel: TeammatePanel?
    private var statusMenu: StatusMenu?
    private var talkShortcut: TalkShortcut?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)  // no Dock icon, also under `swift run`
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        reload()
        let commands = TeammateCommands(
            isTeammateVisible: { [weak self] in self?.panel?.isVisible ?? false },
            toggleTeammate: { [weak self] in self?.panel?.toggle() },
            hideTeammate: { [weak self] in self?.panel?.hide() },
            typeMessage: { [weak self] in
                self?.session.isChatOpen = true
                self?.panel?.focus()
            },
            forgetMemory: { [weak self] in self?.confirmForgetting() },
            openSettings: { [weak self] in self?.openSettings() },
            reload: { [weak self] in self?.reload() },
            quit: { NSApp.terminate(nil) })
        let shortcutName = Self.talkCombination.displayName
        let panel = TeammatePanel(
            rootView: TeammateWindowView(session: session, commands: commands, shortcutName: shortcutName),
            size: TeammateWindowView.size)
        panel.show()
        self.panel = panel
        statusMenu = StatusMenu(session: session, commands: commands, shortcutName: shortcutName)

        do {
            talkShortcut = try TalkShortcut(
                Self.talkCombination,
                onPress: { [weak self] in
                    self?.panel?.show()  // talking to a hidden teammate brings it back
                    self?.session.talkKeyPressed()
                },
                onRelease: { [weak self] in self?.session.talkKeyReleased() })
        } catch {
            NSLog("humanoid-desktop: %@", String(describing: error))
        }
    }

    private func reload() {
        session.configure(with: TeammateLibrary.load())
    }

    /// Forgetting cannot be undone, so it asks first.
    private func confirmForgetting() {
        let name = session.teammate.name
        let alert = NSAlert()
        alert.messageText = AppText.forgetMemoryQuestion(name)
        alert.informativeText = AppText.forgetMemoryDetail(name)
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppText.forget)
        alert.addButton(withTitle: AppText.cancel)
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            session.forgetMemory()
        }
    }

    /// Creates the settings file if needed and shows it in Finder.
    private func openSettings() {
        do {
            NSWorkspace.shared.activateFileViewerSelecting([try TeammateLibrary.ensureSettingsFile()])
        } catch {
            NSLog("humanoid-desktop: could not create the settings file: %@", String(describing: error))
        }
    }
}
