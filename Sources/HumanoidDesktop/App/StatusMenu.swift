import AppKit
import TeammateKit

/// The menu bar item. Its menu is rebuilt each time it opens, so teammates added since the last Reload appear.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    struct Actions {
        var isTeammateVisible: () -> Bool
        var toggleVisible: () -> Void
        var typeMessage: () -> Void
        var openSettings: () -> Void
        var reload: () -> Void
        var quit: () -> Void
    }

    private let session: TeammateSession
    private let actions: Actions
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init(session: TeammateSession, actions: Actions) {
        self.session = session
        self.actions = actions
        super.init()
        item.button?.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "Humanoid teammate")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for teammate in session.catalog.teammates {
            let entry = ActionMenuItem(title: "\(teammate.name): \(teammate.tagline)") { [session] in
                session.choose(teammate)
            }
            entry.state = teammate.key == session.teammate.key ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let visibility = actions.isTeammateVisible() ? "Hide" : "Show"
        menu.addItem(
            ActionMenuItem(title: "\(visibility) \(session.teammate.name)", key: "t", action: actions.toggleVisible))
        menu.addItem(ActionMenuItem(title: "Type a Message", key: "m", action: actions.typeMessage))
        let talk = NSMenuItem(title: "Talk: hold ⌥Space", action: nil, keyEquivalent: "")
        talk.isEnabled = false
        menu.addItem(talk)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Open Settings File…", key: ",", action: actions.openSettings))
        menu.addItem(ActionMenuItem(title: "Reload Settings and Teammates", key: "r", action: actions.reload))
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Quit Humanoid Desktop", key: "q", action: actions.quit))
    }
}

/// A menu item that runs a closure, instead of a selector on a target.
private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, key: String = "", action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("menu items are built in code")
    }

    @objc private func run() { handler() }
}
