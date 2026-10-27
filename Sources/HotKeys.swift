import Carbon

/// System-wide shortcuts via Carbon's RegisterEventHotKey (needs no Accessibility permission).
enum HotKeys {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var installed = false

    /// `keyCode` is a kVK_ value; `modifiers` combines controlKey, optionKey, cmdKey, shiftKey.
    static func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        installHandlerIfNeeded()
        let id = UInt32(handlers.count + 1)
        handlers[id] = action
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5049_534C), id: id) // "PISL"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }

    private static func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKeys.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
