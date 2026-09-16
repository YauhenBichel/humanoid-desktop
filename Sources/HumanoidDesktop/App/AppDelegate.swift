import AppKit
import TeammateKit

/// The composition root: builds the session with its real services, then the window, the menu bar item and the
/// talk shortcut, and connects them. Nothing else creates platform objects.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let session = TeammateSession(
        player: AudioPlayer(), recorder: AudioRecorder(), choices: UserDefaultsChoiceStore())
    private var panel: TeammatePanel?
    private var statusMenu: StatusMenu?
    private var talkShortcut: GlobalHotKey?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)  // no Dock icon, also under `swift run`
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        reload()
        let windowActions = WindowActions(
            hide: { [weak self] in self?.panel?.hide() },
            openSettings: { [weak self] in self?.openSettings() },
            reload: { [weak self] in self?.reload() },
            quit: { NSApp.terminate(nil) })
        let panel = TeammatePanel(
            rootView: TeammateWindowView(session: session, actions: windowActions), size: TeammateWindowView.size)
        panel.show()
        self.panel = panel

        statusMenu = StatusMenu(
            session: session,
            actions: .init(
                isTeammateVisible: { [weak self] in self?.panel?.isVisible ?? false },
                toggleVisible: { [weak self] in self?.panel?.toggle() },
                typeMessage: { [weak self] in
                    self?.session.isChatOpen = true
                    self?.panel?.focus()
                },
                openSettings: windowActions.openSettings,
                reload: windowActions.reload,
                quit: windowActions.quit))

        do {
            talkShortcut = try GlobalHotKey(
                onPress: { [weak self] in self?.session.talkKeyPressed() },
                onRelease: { [weak self] in self?.session.talkKeyReleased() })
        } catch {
            NSLog("humanoid-desktop: %@", String(describing: error))
        }
    }

    private func reload() {
        session.configure(with: TeammateLibrary.load())
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
