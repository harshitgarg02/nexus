import Carbon.HIToolbox

/// Global hotkeys via Carbon `RegisterEventHotKey` (no permission prompt).
/// Registrations are remembered so they can be suspended while a recorder captures keys
/// (a registered hotkey swallows the keypress before the app ever sees it).
enum Hotkey {
    private struct Reg { let keyCode: Int; let modifiers: Int; let handler: () -> Void }
    private static var regs: [UInt32: Reg] = [:]
    private static var refs: [UInt32: EventHotKeyRef] = [:]
    private static var installed = false
    private static var suspended = false

    static func register(id: UInt32, keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        install()
        unregister(id: id)
        regs[id] = Reg(keyCode: keyCode, modifiers: modifiers, handler: handler)
        if !suspended { activate(id) }
    }

    static func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        regs[id] = nil
    }

    static func suspend() {
        suspended = true
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    static func resume() {
        suspended = false
        for id in regs.keys where refs[id] == nil { activate(id) }
    }

    private static func activate(_ id: UInt32) {
        guard let r = regs[id] else { return }
        var ref: EventHotKeyRef?
        let hid = EventHotKeyID(signature: OSType(0x4E58_5553), id: id) // 'NXUS'
        let status = RegisterEventHotKey(UInt32(r.keyCode), UInt32(r.modifiers), hid, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Nexus: RegisterEventHotKey failed (\(status)) for id \(id)")
            return
        }
        refs[id] = ref
    }

    private static func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hid = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hid)
            Hotkey.regs[hid.id]?.handler()
            return noErr
        }, 1, &spec, nil, nil)
    }
}
