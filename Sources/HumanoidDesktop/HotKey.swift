import Carbon.HIToolbox

/// A system-wide shortcut that reports both press and release, for hold-to-talk. Carbon's hot keys need
/// no Accessibility permission, unlike a global key monitor.
final class HotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPress: () -> Void
    private let onRelease: () -> Void

    /// Default: Option-Space.
    init(keyCode: Int = kVK_Space, modifiers: Int = optionKey, onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) { hotKey.onPress() } else { hotKey.onRelease() }
            return noErr
        }, events.count, &events, context, &handler)
        let identifier = EventHotKeyID(signature: OSType(0x484D_4E44), id: 1)  // "HMND"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), identifier, GetApplicationEventTarget(), 0, &hotKey)
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
