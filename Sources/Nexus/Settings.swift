import AppKit
import Carbon.HIToolbox

enum HotkeyAction: String, CaseIterable, Codable {
    case overlay, clipboard, snippets, totp

    var title: String {
        switch self {
        case .overlay: return "Open Nexus"
        case .clipboard: return "Clipboard History"
        case .snippets: return "Snippets"
        case .totp: return "2FA Codes"
        }
    }

    var hotkeyID: UInt32 { UInt32(HotkeyAction.allCases.firstIndex(of: self)! + 1) }

    var defaultBinding: KeyBinding {
        switch self {
        case .overlay: return KeyBinding(keyCode: kVK_Space, modifiers: optionKey, label: "Space")
        case .clipboard: return KeyBinding(keyCode: kVK_ANSI_V, modifiers: cmdKey | shiftKey, label: "V")
        case .snippets: return KeyBinding(keyCode: kVK_ANSI_S, modifiers: cmdKey | shiftKey, label: "S")
        case .totp: return KeyBinding(keyCode: kVK_ANSI_V, modifiers: controlKey, label: "V")
        }
    }
}

/// `keyCode == -1` means "no shortcut".
struct KeyBinding: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int // Carbon modifier mask
    var label: String

    static let none = KeyBinding(keyCode: -1, modifiers: 0, label: "")
    var isNone: Bool { keyCode < 0 }

    var display: String {
        if isNone { return "Not set" }
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + label
    }

    static func carbonModifiers(_ f: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if f.contains(.command) { m |= cmdKey }
        if f.contains(.shift) { m |= shiftKey }
        if f.contains(.option) { m |= optionKey }
        if f.contains(.control) { m |= controlKey }
        return m
    }

    static func label(for event: NSEvent) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
            kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "PgUp", kVK_PageDown: "PgDn",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let s = special[Int(event.keyCode)] { return s }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }

    var isFunctionKey: Bool {
        [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12].contains(keyCode)
    }
}

struct SettingsData: Codable {
    var hotkeys: [String: KeyBinding] = [:]
    var clipboardTextDays = 365   // 0 = keep forever
    var clipboardImageDays = 30   // 0 = keep forever
    var pasteFormattedByDefault = false
    var secretClearSeconds = 30
    var overlayTintAlpha = 0.45 // dark layer over the blur; higher = more opaque/darker
    var currencyEnabled = false // off by default: the only feature that uses the network
    var caffeinateKeepDisplay = true
    var portsConfirmKillall = true
    var portsHideRoot = false
    var totpAlgorithm = "SHA1"
    var totpDigits = 6
    var totpPeriod = 30
    var totpClearSeconds = 30
    var totpRequireAuthToCopy = false
    var totpShowNextCode = true
    var clipboardExcludedApps = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.apple.keychainaccess", "com.apple.Passwords", "com.lastpass.LastPass", "org.keepassxc.keepassxc",
    ]

    init() {}

    // decodeIfPresent so settings files written by older builds keep loading (and keep their hotkeys).
    init(from decoder: Decoder) throws {
        let d = SettingsData()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotkeys = try c.decodeIfPresent([String: KeyBinding].self, forKey: .hotkeys) ?? d.hotkeys
        clipboardTextDays = try c.decodeIfPresent(Int.self, forKey: .clipboardTextDays) ?? d.clipboardTextDays
        clipboardImageDays = try c.decodeIfPresent(Int.self, forKey: .clipboardImageDays) ?? d.clipboardImageDays
        pasteFormattedByDefault = try c.decodeIfPresent(Bool.self, forKey: .pasteFormattedByDefault) ?? d.pasteFormattedByDefault
        secretClearSeconds = try c.decodeIfPresent(Int.self, forKey: .secretClearSeconds) ?? d.secretClearSeconds
        overlayTintAlpha = try c.decodeIfPresent(Double.self, forKey: .overlayTintAlpha) ?? d.overlayTintAlpha
        currencyEnabled = try c.decodeIfPresent(Bool.self, forKey: .currencyEnabled) ?? d.currencyEnabled
        caffeinateKeepDisplay = try c.decodeIfPresent(Bool.self, forKey: .caffeinateKeepDisplay) ?? d.caffeinateKeepDisplay
        portsConfirmKillall = try c.decodeIfPresent(Bool.self, forKey: .portsConfirmKillall) ?? d.portsConfirmKillall
        portsHideRoot = try c.decodeIfPresent(Bool.self, forKey: .portsHideRoot) ?? d.portsHideRoot
        totpAlgorithm = try c.decodeIfPresent(String.self, forKey: .totpAlgorithm) ?? d.totpAlgorithm
        totpDigits = try c.decodeIfPresent(Int.self, forKey: .totpDigits) ?? d.totpDigits
        totpPeriod = try c.decodeIfPresent(Int.self, forKey: .totpPeriod) ?? d.totpPeriod
        totpClearSeconds = try c.decodeIfPresent(Int.self, forKey: .totpClearSeconds) ?? d.totpClearSeconds
        totpRequireAuthToCopy = try c.decodeIfPresent(Bool.self, forKey: .totpRequireAuthToCopy) ?? d.totpRequireAuthToCopy
        totpShowNextCode = try c.decodeIfPresent(Bool.self, forKey: .totpShowNextCode) ?? d.totpShowNextCode
        clipboardExcludedApps = try c.decodeIfPresent([String].self, forKey: .clipboardExcludedApps) ?? d.clipboardExcludedApps
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    static let hotkeysChanged = Notification.Name("NexusHotkeysChanged")

    @Published private(set) var data = SettingsData()

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nexus")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }()

    private init() {
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(SettingsData.self, from: d) { data = s }
    }

    func binding(_ a: HotkeyAction) -> KeyBinding { data.hotkeys[a.rawValue] ?? a.defaultBinding }

    func set(_ a: HotkeyAction, _ b: KeyBinding?) {
        if let b { data.hotkeys[a.rawValue] = b } else { data.hotkeys[a.rawValue] = nil } // nil = reset to default
        save()
        NotificationCenter.default.post(name: Self.hotkeysChanged, object: nil)
    }

    func update(_ change: (inout SettingsData) -> Void) {
        objectWillChange.send()
        change(&data)
        save()
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(data).write(to: url, options: .atomic)
    }

    /// Human-readable warning if `b` clashes with another Nexus action or a macOS shortcut.
    func conflict(_ b: KeyBinding, for action: HotkeyAction) -> String? {
        guard !b.isNone else { return nil }
        for other in HotkeyAction.allCases where other != action {
            let ob = binding(other)
            if ob.keyCode == b.keyCode && ob.modifiers == b.modifiers { return "Already used by \(other.title)." }
        }
        if Self.systemReserved(b) { return "This is a macOS system shortcut and may not fire." }
        return nil
    }

    private static func systemReserved(_ b: KeyBinding) -> Bool {
        var out: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&out) == noErr, let list = out?.takeRetainedValue() as? [[String: Any]] else { return false }
        for e in list {
            guard (e[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let code = e[kHISymbolicHotKeyCode as String] as? Int, code == b.keyCode,
                  let mods = e[kHISymbolicHotKeyModifiers as String] as? Int else { continue }
            // value is a CGEventFlags-style mask
            var cg = 0
            if b.modifiers & cmdKey != 0 { cg |= 0x100000 }
            if b.modifiers & shiftKey != 0 { cg |= 0x20000 }
            if b.modifiers & optionKey != 0 { cg |= 0x80000 }
            if b.modifiers & controlKey != 0 { cg |= 0x40000 }
            if mods & 0x1F0000 == cg { return true }
        }
        return false
    }
}
