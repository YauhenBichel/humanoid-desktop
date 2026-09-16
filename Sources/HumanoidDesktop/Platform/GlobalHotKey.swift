import Carbon.HIToolbox

/// A system-wide shortcut that reports both press and release, for hold-to-talk. Carbon hot keys need no
/// Accessibility permission, unlike a global key monitor.
@MainActor
final class GlobalHotKey {
    struct Unavailable: Error, CustomStringConvertible {
        let status: OSStatus
        var description: String { "⌥Space is taken by another app (status \(status)): typing still works" }
    }

    private let onPress: @MainActor () -> Void
    private let onRelease: @MainActor () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Registers Option-Space; throws when another app already owns it.
    init(onPress: @escaping @MainActor () -> Void, onRelease: @escaping @MainActor () -> Void) throws {
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
                    let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                    isPress ? hotKey.onPress() : hotKey.onRelease()
                }
                return noErr
            }, events.count, &events, context, &handler)
        let identifier = EventHotKeyID(signature: OSType(0x484D_4E44), id: 1)  // "HMND"
        let status = RegisterEventHotKey(
            UInt32(kVK_Space), UInt32(optionKey), identifier, GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else {
            if let handler { RemoveEventHandler(handler) }
            throw Unavailable(status: status)
        }
    }
}
