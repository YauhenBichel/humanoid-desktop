import AppKit
import TeammateKit

/// The menu bar item. Its menu is rebuilt each time it opens, so teammates added since the last Reload appear.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let session: TeammateSession
    private let commands: TeammateCommands
    private let shortcutName: String
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init(session: TeammateSession, commands: TeammateCommands, shortcutName: String) {
        self.session = session
        self.commands = commands
        self.shortcutName = shortcutName
        super.init()
        item.button?.image = NSImage(
            systemSymbolName: "face.smiling", accessibilityDescription: AppText.statusItemDescription)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for teammate in session.catalog.teammates {
            let entry = ActionMenuItem(title: AppText.teammateMenuItem(teammate)) { [session] in
                session.choose(teammate)
            }
            entry.state = teammate.key == session.teammate.key ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let name = session.teammate.name
        let visibility = commands.isTeammateVisible() ? AppText.hide(name) : AppText.show(name)
        menu.addItem(ActionMenuItem(title: visibility, key: "t", action: commands.toggleTeammate))
        menu.addItem(ActionMenuItem(title: AppText.typeMessage, key: "m", action: commands.typeMessage))
        let talkHint = NSMenuItem(title: AppText.talkHint(shortcutName), action: nil, keyEquivalent: "")
        talkHint.isEnabled = false
        menu.addItem(talkHint)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: AppText.forgetMemory(name), action: commands.forgetMemory))
        menu.addItem(ActionMenuItem(title: AppText.openSettings, key: ",", action: commands.openSettings))
        menu.addItem(ActionMenuItem(title: AppText.reload, key: "r", action: commands.reload))
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: AppText.quit, key: "q", action: commands.quit))
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
