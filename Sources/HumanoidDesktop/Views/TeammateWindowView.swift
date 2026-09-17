import SwiftUI
import TeammateKit

/// The speech bubble, the character, the message field (after a click on the character) and any notice.
/// A close button sits on the character (clearer on hover); right-clicking gives the menu bar item's choices.
struct TeammateWindowView: View {
    static let size = CGSize(width: 300, height: 430)

    @Bindable var session: TeammateSession
    let commands: TeammateCommands
    let shortcutName: String
    @FocusState private var isFieldFocused: Bool
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            if !session.bubble.isEmpty {
                SpeechBubble(text: session.bubble, colours: session.teammate.colours)
            }
            character
            if session.isChatOpen {
                MessageField(session: session, shortcutName: shortcutName, isFocused: $isFieldFocused)
            }
            if !session.notice.isEmpty {
                NoticeView(text: session.notice)
            }
        }
        .padding(8)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .bottom)
    }

    private var character: some View {
        // The close button is a sibling of the character, not an overlay inside its tap gesture, so a click on it
        // always closes instead of opening the message field. It is always there: hover tracking does not run
        // while another app is active, so a hover-only button could not be found.
        ZStack(alignment: .topTrailing) {
            CharacterView(
                teammate: session.teammate, expression: session.expression, voiceLevel: { session.voiceLevel }
            )
            .frame(width: 170, height: 200)
            .contentShape(Rectangle())
            .onTapGesture {
                session.isChatOpen.toggle()
                isFieldFocused = session.isChatOpen
            }
            .contextMenu { contextMenu }
            .help(AppText.characterHelp(session.teammate.name, shortcut: shortcutName))
            CloseButton(
                teammateName: session.teammate.name, shortcutName: shortcutName, isHighlighted: isHovering,
                action: commands.hideTeammate
            )
            .padding(2)
        }
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var contextMenu: some View {
        ForEach(session.catalog.teammates) { teammate in
            Toggle(
                AppText.teammateMenuItem(teammate),
                isOn: Binding(get: { teammate.key == session.teammate.key }, set: { _ in session.choose(teammate) }))
        }
        Divider()
        Button(AppText.hide(session.teammate.name), action: commands.hideTeammate)
        Button(AppText.forgetMemory(session.teammate.name), action: commands.forgetMemory)
        Button(AppText.openSettings, action: commands.openSettings)
        Button(AppText.reload, action: commands.reload)
        Divider()
        Button(AppText.quit, action: commands.quit)
    }
}

struct SpeechBubble: View {
    let text: String
    let colours: Teammate.Colours

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(colours.caption.color)
            .lineLimit(8)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14).fill(colours.screen.color.opacity(0.94)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(colours.glow.color.opacity(0.5), lineWidth: 1))
            .frame(maxWidth: 280)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

struct MessageField: View {
    @Bindable var session: TeammateSession
    let shortcutName: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            TextField(AppText.askPlaceholder(session.teammate.name), text: $session.draft)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .onSubmit { session.send(session.draft) }
                .onExitCommand { session.isChatOpen = false }
            Image(systemName: session.activity == .listening ? "waveform" : "mic")
                .foregroundStyle(session.teammate.colours.glow.color)
                .help(AppText.holdToTalkHelp(shortcutName))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor).opacity(0.95)))
        .frame(width: 260)
        .disabled(session.activity == .thinking || session.activity == .transcribing)
    }
}

struct NoticeView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor).opacity(0.9)))
            .frame(maxWidth: 280)
    }
}

struct CloseButton: View {
    let teammateName: String
    let shortcutName: String
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(isHighlighted ? 0.8 : 0.45))
                .frame(width: 28, height: 28)  // a comfortable target around the small symbol
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isHighlighted ? 1 : 0.6)
        .help(AppText.closeHelp(teammateName, shortcut: shortcutName))
        .accessibilityLabel(AppText.hide(teammateName))
    }
}
