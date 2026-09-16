import Carbon.HIToolbox

/// The hold-to-talk shortcut: a system-wide key combination that reports both press and release. Carbon hot keys
/// need no Accessibility permission, unlike a global key monitor.
@MainActor
final class TalkShortcut {
    struct Combination: Sendable {
        let keyCode: Int
        let carbonModifiers: Int
        /// How the combination is written in menus and messages.
        let displayName: String

        static let optionSpace = Combination(keyCode: kVK_Space, carbonModifiers: optionKey, displayName: "⌥Space")
    }

    struct Unavailable: Error, CustomStringConvertible {
        let combination: Combination
        let status: OSStatus
        var description: String {
            "\(combination.displayName) is taken by another app (status \(status)); typing still works"
        }
    }

    let combination: Combination
    private let onPress: @MainActor () -> Void
    private let onRelease: @MainActor () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Registers the combination; throws when another app already owns it.
    init(
        _ combination: Combination,
        onPress: @escaping @MainActor () -> Void,
        onRelease: @escaping @MainActor () -> Void
    ) throws {
        self.combination = combination
        self.onPress = onPress
        self.onRelease = onRelease
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return noErr }
                let isPress = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                // Carbon delivers hot key events on the main thread.
                MainActor.assumeIsolated {
                    let shortcut = Unmanaged<TalkShortcut>.fromOpaque(context).takeUnretainedValue()
                    isPress ? shortcut.onPress() : shortcut.onRelease()
                }
                return noErr
            }, events.count, &events, context, &handler)
        let identifier = EventHotKeyID(signature: OSType(0x484D_4E44), id: 1)  // "HMND"
        let status = RegisterEventHotKey(
            UInt32(combination.keyCode), UInt32(combination.carbonModifiers), identifier, GetApplicationEventTarget(),
            0, &hotKey)
        guard status == noErr else {
            if let handler { RemoveEventHandler(handler) }
            throw Unavailable(combination: combination, status: status)
        }
    }
}
