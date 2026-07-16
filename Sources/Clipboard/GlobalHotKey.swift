import AppKit
import Carbon.HIToolbox

/// A system-wide hotkey via Carbon's `RegisterEventHotKey`.
///
/// Carbon is chosen deliberately over `NSEvent.addGlobalMonitorForEvents`:
/// the global monitor requires Accessibility permission just to observe keys,
/// while `RegisterEventHotKey` needs no permission at all and delivers the key
/// even when another app is frontmost. It's ~60 lines, so no dependency needed.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x434C_4950), id: 1)  // 'CLIP'

    var onFire: (() -> Void)?

    /// - Returns: nil if the hotkey is already claimed by another app.
    init?(keyCode: UInt32, modifiers: UInt32) {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()

            var firedID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &firedID
            )
            guard status == noErr, firedID.id == hotKey.hotKeyID.id else {
                return OSStatus(eventNotHandledErr)
            }

            hotKey.onFire?()
            return noErr
        }

        var handlerRef: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installStatus == noErr else { return nil }
        eventHandler = handlerRef

        var ref: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard registerStatus == noErr, let ref else {
            if let eventHandler { RemoveEventHandler(eventHandler) }
            return nil
        }
        hotKeyRef = ref
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
