import AppKit
import SwiftUI
import TeammateKit

/// A borderless, transparent window that floats above other apps on every Space, dragged by its
/// background. It can take keyboard focus for the chat field without stealing the app switcher.
final class FloatingPanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 430), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        contentView = content
        setFrameAutosaveName("TeammatePanel")  // the teammate stays where you put it
        if !setFrameUsingName("TeammatePanel"), let screen = NSScreen.main?.visibleFrame {
            setFrameOrigin(NSPoint(x: screen.maxX - frame.width - 24, y: screen.minY + 24))
        }
    }

    override var canBecomeKey: Bool { true }
}

/// The bubble above the character, the character, and (after a click on it) the message field.
struct TeammateWindowView: View {
    @ObservedObject var controller: TeammateController
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let mate = controller.teammate
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            if !controller.bubble.isEmpty {
                Text(controller.bubble)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(mate.caption.color)
                    .multilineTextAlignment(.leading)
                    .lineLimit(8)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 14).fill(mate.background.color.opacity(0.94)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(mate.glow.color.opacity(0.5), lineWidth: 1))
                    .frame(maxWidth: 280)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            CharacterView(teammate: mate, expression: controller.expression, loudness: { controller.mouthLevel })
                .frame(width: 170, height: 200)
                .contentShape(Rectangle())
                .onTapGesture {
                    controller.isChatOpen.toggle()
                    fieldFocused = controller.isChatOpen
                }
                .help("\(mate.name): click to type, hold ⌥Space to talk")
            if controller.isChatOpen {
                HStack(spacing: 6) {
                    TextField("Ask \(mate.name)…", text: $controller.draft)
                        .textFieldStyle(.plain)
                        .focused($fieldFocused)
                        .onSubmit { controller.send(controller.draft) }
                        .onExitCommand { controller.isChatOpen = false }
                    Image(systemName: controller.isListening ? "waveform" : "mic")
                        .foregroundColor(mate.glow.color)
                        .help("Hold ⌥Space to talk")
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor).opacity(0.95)))
                .frame(width: 260)
                .disabled(controller.isBusy)
            }
            if !controller.status.isEmpty {
                Text(controller.status)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor).opacity(0.9)))
                    .frame(maxWidth: 280)
            }
        }
        .padding(8)
        .frame(width: 300, height: 430, alignment: .bottom)
    }
}
