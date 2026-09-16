import AppKit
import SwiftUI

/// A borderless, transparent window floating above other apps on every Space, dragged by its background. It
/// can take keyboard focus for the message field without appearing in the Dock or the app switcher.
final class FloatingPanel: NSPanel {
    private static let frameName = "TeammatePanel"
    /// ⌘W or Esc (when nothing inside handled it).
    var onClose: () -> Void = {}

    init(contentView: NSView, size: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        self.contentView = contentView
        setFrameAutosaveName(Self.frameName)  // the teammate stays where you put it
        if !setFrameUsingName(Self.frameName), let visible = NSScreen.main?.visibleFrame {
            setFrameOrigin(NSPoint(x: visible.maxX - size.width - 24, y: visible.minY + 24))
        }
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onClose()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers == "w" {
            onClose()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Hosts the SwiftUI content so that the first click on the floating teammate acts (on the close button, the
/// character, the message field) instead of only bringing the window forward, while another app is active.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Shows, hides and focuses the teammate's window.
@MainActor
final class TeammatePanel {
    private let panel: FloatingPanel

    init(rootView: some View, size: CGSize) {
        panel = FloatingPanel(contentView: FirstClickHostingView(rootView: rootView), size: size)
        panel.onClose = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { panel.isVisible }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
    func toggle() { isVisible ? hide() : show() }

    /// Bring the window forward with the keyboard in it, for typing a message.
    func focus() {
        show()
        panel.makeKey()
        NSApp.activate()
    }
}
