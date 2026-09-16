import AppKit
import SwiftUI
import TeammateKit

/// humanoid-desktop: a teammate floating on the desktop, and a menu bar item to switch, hide or set it up.
/// No Dock icon (Info.plist LSUIElement, and the activation policy for `swift run`).
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = TeammateController()
    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var talkShortcut: HotKey?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = FloatingPanel(content: NSHostingView(rootView: TeammateWindowView(controller: controller)))
        panel.orderFrontRegardless()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "Humanoid teammate")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        talkShortcut = HotKey(onPress: { [weak self] in Task { @MainActor in self?.controller.startListening() } },
                              onRelease: { [weak self] in Task { @MainActor in self?.controller.stopListening() } })
    }

    // The menu is rebuilt each time it opens, so new teammate files show up after Reload.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for mate in controller.teammates {
            let item = NSMenuItem(title: "\(mate.name): \(mate.tagline)", action: #selector(chooseTeammate(_:)), keyEquivalent: "")
            item.representedObject = mate.key
            item.state = mate.key == controller.teammate.key ? .on : .off
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(item(panel.isVisible ? "Hide Teammate" : "Show Teammate", #selector(toggleVisible), key: "t"))
        menu.addItem(item("Type a Message", #selector(openChat), key: "m"))
        let talk = NSMenuItem(title: "Talk: hold ⌥Space", action: nil, keyEquivalent: "")
        talk.isEnabled = false
        menu.addItem(talk)
        menu.addItem(.separator())
        menu.addItem(item("Open Settings File…", #selector(openSettings), key: ","))
        menu.addItem(item("Reload Settings and Teammates", #selector(reload), key: "r"))
        menu.addItem(.separator())
        menu.addItem(item("Quit Humanoid Desktop", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func chooseTeammate(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let mate = controller.teammates.first(where: { $0.key == key }) else { return }
        controller.choose(mate)
        panel.orderFrontRegardless()
    }

    @objc private func toggleVisible() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    @objc private func openChat() {
        panel.orderFrontRegardless()
        controller.isChatOpen = true
        panel.makeKey()
        NSApp.activate()
    }

    @objc private func openSettings() { controller.openSettingsFolder() }
    @objc private func reload() { controller.reload() }
    @objc private func quit() { NSApp.terminate(nil) }
}
