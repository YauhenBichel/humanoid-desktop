import AppKit
import SwiftUI

/// A borderless, transparent window floating above other apps on every Space, dragged by its background. It
/// can take keyboard focus for the message field without appearing in the Dock or the app switcher.
final class FloatingPanel: NSPanel {
    private static let frameName = "TeammatePanel"

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
}

/// Shows, hides and focuses the teammate's window.
@MainActor
final class TeammatePanel {
    private let panel: FloatingPanel

    init(rootView: some View, size: CGSize) {
        panel = FloatingPanel(contentView: NSHostingView(rootView: rootView), size: size)
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
