import Carbon.HIToolbox
import OSLog

/// A system-wide shortcut. Carbon hot keys need no Accessibility permission.
final class GlobalHotKey {
    private static let logger = Logger(subsystem: "com.juancasanueva.youtubedownload", category: "GlobalHotKey")

    private let action: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )

        let identifier = EventHotKeyID(signature: OSType(0x5954_444C), id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )

        if handlerStatus != noErr || hotKeyStatus != noErr {
            Self.logger.error("Hot key unavailable: handler \(handlerStatus), registration \(hotKeyStatus)")
        }
    }
}
