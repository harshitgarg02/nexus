import SwiftUI
import ServiceManagement
import ApplicationServices
import NexusCore

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general = "General", hotkeys = "Hotkeys", clipboard = "Clipboard", snippets = "Snippets"
    case twoFA = "2FA", caffeinate = "Caffeinate", ports = "Ports", calculator = "Calculator"
    case extensions = "Extensions", permissions = "Permissions", advanced = "Advanced", about = "About"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .hotkeys: return "keyboard"
        case .clipboard: return "doc.on.clipboard"
        case .snippets: return "text.quote"
        case .twoFA: return "lock.shield"
        case .caffeinate: return "cup.and.saucer"
        case .ports: return "network"
        case .calculator: return "equal.square"
        case .extensions: return "puzzlepiece.extension"
        case .permissions: return "hand.raised"
        case .advanced: return "wrench.and.screwdriver"
        case .about: return "info.circle"
        }
    }
}

final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Nexus Settings"
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @State private var selection: SettingsCategory = .hotkeys

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selection) { c in
                Label(c.rawValue, systemImage: c.icon).tag(c)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
        } detail: {
            Group {
                switch selection {
                case .general: GeneralPane()
                case .hotkeys: HotkeysPane()
                case .clipboard: ClipboardPane()
                case .snippets: SnippetsPane()
                case .twoFA: TwoFAPane()
                case .permissions: PermissionsPane()
                case .advanced: AdvancedPane()
                case .caffeinate: CaffeinatePane()
                case .calculator: CalculatorPane()
                case .extensions: ExtensionsPane()
                case .ports: PortsPane()
                case .about: AboutPane()
                default: PlaceholderPane(category: selection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(selection.rawValue)
        }
        .frame(minWidth: 700, minHeight: 440)
    }
}

struct HotkeysPane: View {
    @ObservedObject private var settings = Settings.shared
    @State private var warnings: [HotkeyAction: String] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(action.title)
                            Spacer()
                            HotkeyRecorder(binding: settings.binding(action)) { b in
                                settings.set(action, b)
                                warnings[action] = settings.conflict(settings.binding(action), for: action)
                            }
                            .frame(width: 170, height: 28)
                            Button("Reset") { settings.set(action, nil); warnings[action] = nil }
                                .disabled(settings.data.hotkeys[action.rawValue] == nil)
                        }
                        if let w = warnings[action] {
                            Text(w).font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            } footer: {
                Text("Click a shortcut, then press the new combination. ⎋ cancels, ⌫ clears. Clipboard, Snippets and 2FA shortcuts take effect when those modules are added.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct GeneralPane: View {
    @ObservedObject private var settings = Settings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        error = nil
                    } catch {
                        self.error = "Couldn't change login item: \(error.localizedDescription). Install to /Applications first (make install)."
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            Section("Appearance") {
                LabeledContent("Background darkness") {
                    HStack {
                        Slider(value: Binding(get: { settings.data.overlayTintAlpha },
                                              set: { v in settings.update { $0.overlayTintAlpha = v } }), in: 0...0.9)
                            .frame(width: 220)
                        Text("\(Int(settings.data.overlayTintAlpha * 100))%").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Text("Raise it if the overlay looks washed out over light windows. Applies live next time you open Nexus.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutPane: View {
    var body: some View {
        Form {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
            LabeledContent("Bundle", value: Bundle.main.bundleIdentifier ?? "—")
            LabeledContent("Settings file", value: "~/Library/Application Support/Nexus/settings.json")
        }
        .formStyle(.grouped)
    }
}

struct PlaceholderPane: View {
    let category: SettingsCategory
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: category.icon).font(.system(size: 32)).foregroundStyle(.secondary)
            Text("\(category.rawValue) settings arrive with that module.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ClipboardPane: View {
    @ObservedObject private var settings = Settings.shared
    @State private var confirmClear = false

    private static let textOptions: [(String, Int)] = [("30 days", 30), ("90 days", 90), ("6 months", 180), ("1 year", 365), ("Forever", 0)]
    private static let imageOptions: [(String, Int)] = [("7 days", 7), ("30 days", 30), ("90 days", 90), ("1 year", 365), ("Forever", 0)]

    var body: some View {
        Form {
            Section("Retention") {
                Picker("Text, links, files", selection: bind(\.clipboardTextDays)) {
                    ForEach(Self.textOptions, id: \.1) { Text($0.0).tag($0.1) }
                }
                Picker("Images", selection: bind(\.clipboardImageDays)) {
                    ForEach(Self.imageOptions, id: \.1) { Text($0.0).tag($0.1) }
                }
                Text("Pinned items are never deleted. Cleanup runs at launch and hourly.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Paste") {
                Picker("Default paste mode", selection: bind(\.pasteFormattedByDefault)) {
                    Text("Plain text").tag(false)
                    Text("Formatted").tag(true)
                }
                Text("The other mode is in the ⌘K menu.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Ignored apps (bundle IDs, one per line)") {
                TextEditor(text: Binding(
                    get: { settings.data.clipboardExcludedApps.joined(separator: "\n") },
                    set: { v in settings.update { $0.clipboardExcludedApps = v.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } } }))
                    .font(.system(size: 12, design: .monospaced)).frame(height: 90)
                Text("Concealed/transient clipboard content (password managers) is always skipped.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Clear Clipboard History…", role: .destructive) { confirmClear = true }
                    .confirmationDialog("Delete all unpinned clipboard history?", isPresented: $confirmClear) {
                        Button("Delete", role: .destructive) { ClipboardService.shared.clearAll() }
                    }
            }
        }
        .formStyle(.grouped)
    }

    private func bind<T>(_ kp: WritableKeyPath<SettingsData, T>) -> Binding<T> {
        Binding(get: { settings.data[keyPath: kp] }, set: { v in settings.update { $0[keyPath: kp] = v }; ClipboardService.shared.purge() })
    }
}

struct SnippetsPane: View {
    @ObservedObject private var settings = Settings.shared
    private static let options = [10, 30, 60, 120]

    var body: some View {
        Form {
            Section("Secret snippets") {
                Picker("Clear clipboard after pasting a secret", selection: Binding(
                    get: { settings.data.secretClearSeconds },
                    set: { v in settings.update { $0.secretClearSeconds = v } })) {
                    ForEach(Self.options, id: \.self) { Text("\($0) seconds").tag($0) }
                }
                Text("Editing, revealing or deleting a secret asks for Touch ID or your Mac password. Values are stored in the Keychain, never in the snippet database.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Placeholders") {
                Text("{clipboard}  {date}  {time}  {datetime}").font(.system(size: 12, design: .monospaced))
            }
            Section("Backup") {
                HStack {
                    Button("Export Snippets…") { SnippetTransferUI.export() }
                    Button("Import Snippets…") { SnippetTransferUI.importFile() }
                }
                Text("JSON file. Secret snippets are never exported (their values stay in the Keychain). Importing never overwrites: identical snippets are skipped and name clashes are added as “… (imported)”.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct TwoFAPane: View {
    @ObservedObject private var settings = Settings.shared

    private func bind<T>(_ kp: WritableKeyPath<SettingsData, T>) -> Binding<T> {
        Binding(get: { settings.data[keyPath: kp] }, set: { v in settings.update { $0[keyPath: kp] = v } })
    }

    var body: some View {
        Form {
            Section("Defaults for new entries") {
                Picker("Algorithm", selection: bind(\.totpAlgorithm)) {
                    ForEach(TOTPAlgorithm.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }
                Picker("Digits", selection: bind(\.totpDigits)) { ForEach(6...8, id: \.self) { Text("\($0)").tag($0) } }
                Picker("Period", selection: bind(\.totpPeriod)) { ForEach([15, 30, 60], id: \.self) { Text("\($0) seconds").tag($0) } }
                Text("A pasted otpauth:// link or QR code overrides these.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Codes") {
                Picker("Clear clipboard after copying", selection: bind(\.totpClearSeconds)) {
                    ForEach([10, 30, 60, 120], id: \.self) { Text("\($0) seconds").tag($0) }
                }
                Toggle("Show the next code in the last 5 seconds", isOn: bind(\.totpShowNextCode))
                Toggle("Require Touch ID / Mac password to copy a code", isOn: bind(\.totpRequireAuthToCopy))
                Text("Editing or deleting an entry always asks for your login.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct CaffeinatePane: View {
    @ObservedObject private var settings = Settings.shared
    var body: some View {
        Form {
            Toggle("Also keep the display awake", isOn: Binding(
                get: { settings.data.caffeinateKeepDisplay }, set: { v in settings.update { $0.caffeinateKeepDisplay = v } }))
            Text("Applies the next time you start Caffeinate. The ⌥Space command starts it indefinitely; ⌘K on it offers timed options.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct PortsPane: View {
    @ObservedObject private var settings = Settings.shared
    var body: some View {
        Form {
            Toggle("Confirm before Killall", isOn: Binding(
                get: { settings.data.portsConfirmKillall }, set: { v in settings.update { $0.portsConfirmKillall = v } }))
            Toggle("Hide processes owned by root", isOn: Binding(
                get: { settings.data.portsHideRoot }, set: { v in settings.update { $0.portsHideRoot = v } }))
            Text("Killing a process you don't own fails with an error. Nexus never escalates privileges.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct PermissionsPane: View {
    @State private var accessibility = AXIsProcessTrusted()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Circle().fill(accessibility ? Color.green : Color.orange).frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility").font(.system(size: 13, weight: .medium))
                        Text(accessibility ? "Granted. Nexus can paste into other apps."
                                           : "Not granted. Needed to paste into other apps (Clipboard, Snippets, 2FA). Without it, items are only copied.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !accessibility {
                        Button("Request") {
                            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
                        }
                    }
                    Button("Open System Settings") { Self.open("Privacy_Accessibility") }
                }
            }
            Section {
                notNeeded("Input Monitoring", "Global hotkeys use the system's hotkey API, which needs no permission.")
                notNeeded("Screen Recording", "Nexus doesn't capture the screen.")
            }
            Section("Where Nexus is running from") {
                Text(Bundle.main.bundlePath).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                Text("Permissions are tied to the app's signature, so they should survive rebuilds signed with the same identity. If Accessibility stops working after a rebuild, remove Nexus from the list in System Settings and add it again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(tick) { _ in accessibility = AXIsProcessTrusted() }
    }

    private func notNeeded(_ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Color.gray).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text("Not required. " + detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private static func open(_ pane: String) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(u) }
    }
}

struct AdvancedPane: View {
    @State private var stats = LatencyMeter.stats()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Overlay open latency (hotkey → drawn, this session)") {
                if let s = stats {
                    LabeledContent("Last", value: String(format: "%.1f ms", s.last))
                    LabeledContent("Average", value: String(format: "%.1f ms", s.mean))
                    LabeledContent("95th percentile", value: String(format: "%.1f ms", s.p95))
                    LabeledContent("Worst", value: String(format: "%.1f ms", s.max))
                    LabeledContent("Samples", value: "\(s.count)")
                } else {
                    Text("Open Nexus with your hotkey a few times, then check back.").foregroundStyle(.secondary)
                }
                Button("Reset") { LatencyMeter.reset(); stats = nil }
                Text("Target: under 50 ms. Measured on the CPU side, so window-server compositing adds a few ms.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Data") {
                Button("Reveal Data Folder in Finder") {
                    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Nexus")
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                }
                Text("Clipboard history, snippets, 2FA entries and settings. Secret values are in the Keychain, not here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(tick) { _ in stats = LatencyMeter.stats() }
    }
}

struct CalculatorPane: View {
    @ObservedObject private var settings = Settings.shared
    @State private var status = Self.statusText()
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Currency conversion") {
                Toggle("Enable currency conversion", isOn: Binding(
                    get: { settings.data.currencyEnabled },
                    set: { v in
                        settings.update { $0.currencyEnabled = v }
                        if v { CurrencyService.shared.refreshIfNeeded(force: true) }
                        status = Self.statusText()
                    }))
                if settings.data.currencyEnabled {
                    LabeledContent("Rates", value: status)
                    Button("Refresh Now") { CurrencyService.shared.refreshIfNeeded(force: true) }
                }
                Text("Off by default. When on, Nexus downloads daily exchange rates from open.er-api.com (a plain request that sends nothing about you) and caches them. Try “100 usd to inr” or “$50 in eur”.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Also built in") {
                Text("Math, units, dates and times, time zones, epoch timestamps, and named dates like “days until christmas”. Eid and Ramadan dates are approximate because they follow the moon.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Developer tools (type in the launcher)") {
                Text("""
                uuid · objectid · ulid · nanoid · password 20 · hex 32 · random 1 100
                base64 text · unbase64 … · urlencode text · urldecode …
                sha256 text · md5 · sha1 · sha512 · hash text
                packb {"a":1} · unpackb <hex or base64>  (MessagePack)
                jwt <token> (or just paste one) · #ff5733 / rgb(…) / hsl(…)
                camel / pascal / snake / kebab / constant text · case text

                netinfo (local IPs, gateway, DNS) · http 404 · base 255 · lorem 3 · cron */5 * * * * · regex /[0-9]+/ text   (each is also a command)

                Clipboard transforms are commands (type "json", "sort", "dedupe", "escape"…):
                Format/Minify JSON · Sort/Reverse/Dedupe/Trim lines · UPPER/lower/Title case
                Escape/Unescape · Join/Split commas · Text statistics · Copy as plain text
                """)
                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                Text("Everything runs on your Mac. JWTs are decoded, never verified or sent anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(tick) { _ in status = Self.statusText() }
        .onReceive(NotificationCenter.default.publisher(for: CurrencyService.updatedNotification)) { _ in status = Self.statusText() }
    }

    private static func statusText() -> String {
        let svc = CurrencyService.shared
        guard let r = svc.rates else { return svc.lastError.map { "Not downloaded yet (\($0))" } ?? "Downloading…" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        let age = f.localizedString(for: r.updated, relativeTo: Date())
        return "\(r.rates.count) currencies, updated \(age)" + (svc.lastError != nil ? " (refresh failed)" : "")
    }
}

struct ExtensionsPane: View {
    @State private var scripts = ScriptIndex.shared.scripts
    @State private var blocked = ScriptIndex.shared.notExecutable
    @State private var note: String?

    var body: some View {
        Form {
            Section("Script commands") {
                Text("Any file in this folder with a @nexus.title header becomes a command in ⌥Space.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(ScriptIndex.shared.folder.path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button("Open Folder") { NSWorkspace.shared.open(ScriptIndex.shared.folder) }
                    Button("Add Example Script") {
                        note = ScriptIndex.shared.createExample() != nil ? "Created \(ScriptIndex.exampleName)." : "Couldn't create the example."
                        refresh()
                    }
                    Button("Reload") { ScriptIndex.shared.reload(); refresh() }
                }
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Detected (\(scripts.count))") {
                if scripts.isEmpty { Text("None yet.").foregroundStyle(.secondary) }
                ForEach(scripts) { s in
                    HStack {
                        Image(systemName: ScriptView.symbol(s.icon)).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.title)
                            Text((s.path as NSString).lastPathComponent + " · output: \(s.mode.rawValue)" + (s.argument != nil ? " · takes an argument" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if blocked.contains(s.path) { Text("not executable").font(.caption).foregroundStyle(.orange) }
                    }
                }
            }
            Section("Header format") {
                Text("""
                #!/bin/bash
                # @nexus.title Say Hello
                # @nexus.description What it does
                # @nexus.icon hand.wave        (SF Symbol)
                # @nexus.mode output           (output | clipboard | paste | silent)
                # @nexus.keywords hi, greet
                # @nexus.argument Your name    (optional; passed as $1)
                """)
                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                Text("Scripts run with your permissions and a 30 second limit, so only keep scripts you trust in this folder. Files need to be executable (chmod +x).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { ScriptIndex.shared.reload(); refresh() }
    }

    private func refresh() {
        scripts = ScriptIndex.shared.scripts
        blocked = ScriptIndex.shared.notExecutable
    }
}
