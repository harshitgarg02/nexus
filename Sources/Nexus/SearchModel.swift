import AppKit
import NexusCore

struct ActionItem: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    var destructive = false
    /// Keep the overlay open after running (pin, delete…).
    var keepsOpen = false
    let run: () -> Void

    init(title: String, symbol: String, destructive: Bool = false, keepsOpen: Bool = false, run: @escaping () -> Void) {
        self.title = title; self.symbol = symbol; self.destructive = destructive; self.keepsOpen = keepsOpen; self.run = run
    }
}

struct ResultItem: Identifiable {
    let id: String
    let section: String
    let title: String
    let subtitle: String
    let accessory: String
    let primaryLabel: String
    let isCalc: Bool
    let icon: NSImage?
    var symbol: String? = nil
    /// Command rows navigate inside the overlay instead of dismissing it.
    var keepsOpen = false
    var extra: [ActionItem] = []
    let run: () -> Void
}

enum NavKey { case up, down, enter, escape }

final class SearchModel: ObservableObject {
    enum Mode { case root, clipboard, snippets, totp, ports, apps, script, transform, regex, diff, qr, docker }

    @Published var query = "" { didSet { update() } }
    @Published private(set) var results: [ResultItem] = []
    @Published var selection = 0
    @Published var focusTick = 0
    @Published var mode = Mode.root
    @Published var actionsOpen = false
    @Published var actionSelection = 0
    let clipboard = ClipboardModel()
    let snippets = SnippetsModel()
    let totp = TOTPModel()
    let ports = PortsModel()
    let apps = RunningAppsModel()
    let script = ScriptModel()
    let transform = TransformModel()
    let regex = RegexModel()
    let diff = DiffModel()
    let qr = QRModel()
    let docker = DockerModel()
    var dismiss: () -> Void = {}
    /// True when a hotkey opened a module directly: ⎋ then closes instead of going back to root.
    private var openedDirectly = false

    private var iconCache: [String: NSImage] = [:]

    init() {
        clipboard.dismiss = { [weak self] in self?.dismiss() }
        snippets.dismiss = { [weak self] in self?.dismiss() }
        totp.dismiss = { [weak self] in self?.dismiss() }
        ports.dismiss = { [weak self] in self?.dismiss() }
        script.dismiss = { [weak self] in self?.dismiss() }
        transform.dismiss = { [weak self] in self?.dismiss() }
        regex.dismiss = { [weak self] in self?.dismiss() }
        diff.dismiss = { [weak self] in self?.dismiss() }
        qr.dismiss = { [weak self] in self?.dismiss() }
        docker.dismiss = { [weak self] in self?.dismiss() }
        NotificationCenter.default.addObserver(forName: OverlayController.toggleActionsNotification, object: nil, queue: .main) { [weak self] _ in
            self?.toggleActions()
        }
        // fresh rates arrived: redo the current calculation
        NotificationCenter.default.addObserver(forName: CurrencyService.updatedNotification, object: nil, queue: .main) { [weak self] _ in
            if self?.mode == .root { self?.update() }
        }
        NotificationCenter.default.addObserver(forName: OverlayController.newItemNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.mode == .snippets, self.snippets.editor == nil { self.actionsOpen = false; self.snippets.beginNew() }
            if self.mode == .totp, self.totp.editor == nil { self.actionsOpen = false; self.totp.beginNew() }
        }
    }

    func reset(start: Mode = .root) {
        actionsOpen = false
        switch start {
        case .clipboard: openClipboard(direct: true)
        case .snippets: openSnippets(direct: true)
        case .totp: openTOTP(direct: true)
        case .ports: openPorts(direct: true)
        case .apps: openApps(direct: true, force: false)
        case .script, .transform, .regex, .diff, .qr, .docker: break // only reachable from a root row
        case .root:
            mode = .root
            query = ""
            selection = 0
            update()
            focusTick += 1
        }
    }

    func openSnippets(direct: Bool, newSnippet: Bool = false, kind: SnippetKind = .text) {
        openedDirectly = direct
        mode = .snippets
        actionsOpen = false
        snippets.open()
        if newSnippet { snippets.beginNew(kind: kind) }
    }

    func openDiff() { openedDirectly = false; mode = .diff; actionsOpen = false; diff.open() }
    func openQR() { openedDirectly = false; mode = .qr; actionsOpen = false; qr.open() }
    func openDocker() { openedDirectly = false; mode = .docker; actionsOpen = false; docker.open() }

    func openRegex() {
        openedDirectly = false
        mode = .regex
        actionsOpen = false
        regex.open()
    }

    func openTransform(_ t: TextTransform) {
        openedDirectly = false
        mode = .transform
        actionsOpen = false
        transform.open(t)
    }

    func openScript(_ info: ScriptInfo) {
        openedDirectly = false
        mode = .script
        actionsOpen = false
        script.open(info)
    }

    func openApps(direct: Bool, force: Bool) {
        openedDirectly = direct
        mode = .apps
        actionsOpen = false
        apps.open(force: force)
    }

    func openPorts(direct: Bool) {
        openedDirectly = direct
        mode = .ports
        actionsOpen = false
        ports.open()
    }

    func openTOTP(direct: Bool, newEntry: Bool = false) {
        openedDirectly = direct
        mode = .totp
        actionsOpen = false
        totp.open()
        if newEntry { totp.beginNew() }
    }

    func openClipboard(direct: Bool) {
        openedDirectly = direct
        mode = .clipboard
        actionsOpen = false
        clipboard.open()
    }

    /// Bumps every screen's focus counter so its text field takes the cursor.
    func refocus() {
        focusTick += 1; clipboard.focusTick += 1; snippets.focusTick += 1; totp.focusTick += 1; ports.focusTick += 1
        apps.focusTick += 1; docker.focusTick += 1; qr.focusTick += 1; regex.focusTick += 1; script.focusTick += 1
    }

    func back() {
        mode = .root
        query = ""
        selection = 0
        update()
        focusTick += 1
    }

    // MARK: keys

    func key(_ k: NavKey) {
        if actionsOpen { return actionKey(k) }
        switch (mode, k) {
        case (.root, .up): move(-1)
        case (.root, .down): move(1)
        case (.root, .enter): runSelected()
        case (.root, .escape): dismiss()
        case (.clipboard, .up): clipboard.move(-1)
        case (.clipboard, .down): clipboard.move(1)
        case (.clipboard, .enter): clipboard.paste()
        case (.clipboard, .escape): openedDirectly ? dismiss() : back()
        case (.snippets, _) where snippets.editor != nil:
            if k == .escape { snippets.cancelEditor() }
        case (.snippets, .up): snippets.move(-1)
        case (.snippets, .down): snippets.move(1)
        case (.snippets, .enter): snippets.paste()
        case (.snippets, .escape): openedDirectly ? dismiss() : back()
        case (.totp, _) where totp.editor != nil:
            if k == .escape { totp.cancelEditor() }
        case (.totp, .up): totp.move(-1)
        case (.totp, .down): totp.move(1)
        case (.totp, .enter): totp.copy()
        case (.totp, .escape): openedDirectly ? dismiss() : back()
        case (.diff, .enter): diff.submit()
        case (.diff, .escape): back()
        case (.diff, _): break
        case (.qr, .escape): back()
        case (.qr, _): break // ↵ is handled by the text field
        case (.docker, .up): docker.move(-1)
        case (.docker, .down): docker.move(1)
        case (.docker, .enter): docker.submit()
        case (.docker, .escape): if !docker.closeLogs() { back() }
        case (.regex, .escape): back()
        case (.regex, _): break // ↵ belongs to the text editor; ⌘↵ copies
        case (.transform, .enter): transform.submit()
        case (.transform, .escape): back()
        case (.transform, _): break
        case (.script, .enter): script.submit()
        case (.script, .escape): back()
        case (.script, _): break
        case (.apps, .up): apps.move(-1)
        case (.apps, .down): apps.move(1)
        case (.apps, .enter): apps.primary()
        case (.apps, .escape): openedDirectly ? dismiss() : back()
        case (.ports, .up): ports.move(-1)
        case (.ports, .down): ports.move(1)
        case (.ports, .enter): ports.copySelectedPort()
        case (.ports, .escape): openedDirectly ? dismiss() : back()
        }
    }

    private func actionKey(_ k: NavKey) {
        let acts = actions
        switch k {
        case .up: actionSelection = (actionSelection - 1 + max(acts.count, 1)) % max(acts.count, 1)
        case .down: actionSelection = (actionSelection + 1) % max(acts.count, 1)
        case .escape: actionsOpen = false
        case .enter:
            guard acts.indices.contains(actionSelection) else { return }
            let a = acts[actionSelection]
            actionsOpen = false
            if !a.keepsOpen { dismiss() }
            a.run()
        }
    }

    func toggleActions() {
        guard !actions.isEmpty else { return }
        actionSelection = 0
        actionsOpen.toggle()
    }

    var actions: [ActionItem] {
        switch mode {
        case .clipboard: return clipboard.actions
        case .snippets: return snippets.editor == nil ? snippets.actions : []
        case .totp: return totp.editor == nil ? totp.actions : []
        case .ports: return ports.actions
        case .apps: return apps.actions
        case .script: return script.actions
        case .transform: return transform.actions
        case .regex: return regex.actions
        case .diff: return diff.actions
        case .qr: return qr.actions
        case .docker: return docker.actions
        case .root:
            guard results.indices.contains(selection) else { return [] }
            let r = results[selection]
            return [ActionItem(title: r.primaryLabel, symbol: "return", keepsOpen: r.keepsOpen, run: r.run)] + r.extra
        }
    }

    // MARK: root

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    func runSelected() {
        guard results.indices.contains(selection) else { return }
        let item = results[selection]
        if !item.keepsOpen { dismiss() }
        item.run()
    }

    private func icon(for app: AppEntry) -> NSImage {
        if let i = iconCache[app.url.path] { return i }
        let i = NSWorkspace.shared.icon(forFile: app.url.path)
        iconCache[app.url.path] = i
        return i
    }

    /// ⌘K on a calculator/generator row: paste it, and for generated values make another.
    /// `trigger` + the clipboard's text when it's a single line (multi-line or empty: just the trigger).
    private func fillFromClipboard(_ trigger: String) {
        let clip = (NSPasteboard.general.string(forType: .string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        fill(clip.isEmpty || clip.contains("\n") ? trigger + " " : trigger + " " + String(clip.prefix(2000)))
    }

    private func fillColor() {
        let clip = (NSPasteboard.general.string(forType: .string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        fill(RGBA.parse(clip) != nil ? clip : "#")
    }

    /// Puts `text` in the search box (with the cursor there), which runs it through the calculator.
    private func fill(_ text: String) {
        query = text
        focusTick += 1
    }

    private func calcExtras(for row: CalcRow) -> [ActionItem] {
        var a = [ActionItem(title: "Paste to \(clipboard.targetName)", symbol: "arrow.right.doc.on.clipboard", run: { [weak self] in
            let target = self?.clipboard.targetApp
            target?.activate()
            ClipboardService.shared.write(paste: true) { $0.setString(row.copy, forType: .string) }
        })]
        if row.generated {
            a.append(ActionItem(title: "Generate Another", symbol: "arrow.clockwise", keepsOpen: true, run: { [weak self] in self?.update() }))
        }
        return a
    }

    /// Display order of command groups when matches tie: your modules, scripts, system, generators, dev tools, text.
    private enum Group {
        static let modules = 0, scripts = 1, system = 2, generators = 3, devTools = 4, text = 5
    }

    private static let moduleTitles: Set<String> = [
        "Clipboard History", "Search Snippets", "Create Snippet", "Create Code Snippet", "Create Terminal Command Snippet",
        "Generate 2FA Code", "Open Ports",
    ]
    private static let systemTitles: Set<String> = [
        "Quit Application", "Force Quit Application", "Lock Screen", "Sleep", "Sleep Display", "Empty Trash",
        "Toggle Dark Mode", "Restart Nexus", "Quit Nexus", "Copy Clipboard as Plain Text",
    ]
    private static let textTitles = Set(TextTransform.allCases.map(\.title))

    private static func group(of title: String) -> Int {
        if moduleTitles.contains(title) { return Group.modules }
        if systemTitles.contains(title) { return Group.system }
        if title.hasPrefix("Generate ") { return Group.generators }
        if textTitles.contains(title) { return Group.text }
        return Group.devTools
    }

    /// Every text transform is a command: it reads the clipboard and shows the result.
    private static let transformCommands: [Command] = TextTransform.allCases.map { t in
        Command(title: t.title, keywords: t.keywords, symbol: t.symbol, run: { $0.openTransform(t) })
    } + [
        Command(title: "Copy Clipboard as Plain Text", keywords: ["plain", "text", "strip", "formatting", "unformat", "clipboard"],
                symbol: "doc.plaintext", navigates: false, run: { _ in
                    guard let s = NSPasteboard.general.string(forType: .string) else { return }
                    ClipboardService.shared.write(paste: false) { $0.setString(s, forType: .string) }
                }),
    ]

    private struct Command {
        let title: String
        let keywords: [String]
        let symbol: String
        /// true = opens a list inside the overlay; false = one-shot action (overlay closes first).
        var navigates = true
        let run: (SearchModel) -> Void
    }

    private static let commands = [
        Command(title: "Clipboard History", keywords: ["clipboard", "history", "paste", "copy"], symbol: "doc.on.clipboard",
                run: { $0.openClipboard(direct: false) }),
        Command(title: "Search Snippets", keywords: ["snippets", "snippet", "text", "password"], symbol: "text.quote",
                run: { $0.openSnippets(direct: false) }),
        Command(title: "Generate 2FA Code", keywords: ["2fa", "totp", "otp", "authenticator", "code"], symbol: "lock.shield",
                run: { $0.openTOTP(direct: false) }),
        Command(title: "Open Ports", keywords: ["ports", "port", "kill", "process", "listening", "localhost"], symbol: "network",
                run: { $0.openPorts(direct: false) }),
        Command(title: "Quit Application", keywords: ["quit", "close", "exit", "app", "kill"], symbol: "xmark.circle",
                run: { $0.openApps(direct: false, force: false) }),
        Command(title: "Force Quit Application", keywords: ["force", "quit", "kill", "frozen", "app"], symbol: "bolt.slash",
                run: { $0.openApps(direct: false, force: true) }),
        Command(title: "Lock Screen", keywords: ["lock", "screen"], symbol: "lock", navigates: false, run: { _ in SystemActions.lockScreen() }),
        Command(title: "Sleep", keywords: ["sleep", "suspend"], symbol: "moon.zzz", navigates: false, run: { _ in SystemActions.sleepMac() }),
        Command(title: "Sleep Display", keywords: ["display", "screen", "off", "sleep"], symbol: "display", navigates: false,
                run: { _ in SystemActions.sleepDisplay() }),
        Command(title: "Empty Trash", keywords: ["trash", "empty", "bin", "delete"], symbol: "trash", navigates: false,
                run: { _ in SystemActions.emptyTrash() }),
        Command(title: "Toggle Dark Mode", keywords: ["dark", "light", "appearance", "theme", "mode"], symbol: "circle.lefthalf.filled", navigates: false,
                run: { _ in SystemActions.toggleDarkMode() }),
        Command(title: "Restart Nexus", keywords: ["restart", "relaunch", "nexus"], symbol: "arrow.clockwise", navigates: false,
                run: { _ in SystemActions.restartNexus() }),
        Command(title: "Quit Nexus", keywords: ["quit", "exit", "nexus"], symbol: "power", navigates: false,
                run: { _ in NSApp.terminate(nil) }),
        // Generators: these fill the search box with the matching trigger, so the live result rows appear
        // (↵ copies one, ⌘K pastes it or generates another).
        Command(title: "Generate UUID", keywords: ["generate", "uuid", "guid", "random", "id"], symbol: "number",
                run: { $0.fill("uuid") }),
        Command(title: "Generate UUID v7 (time-ordered)", keywords: ["generate", "uuid", "uuid7", "v7", "guid"], symbol: "number",
                run: { $0.fill("uuid v7") }),
        Command(title: "Generate MongoDB ObjectId", keywords: ["generate", "objectid", "object id", "oid", "mongo", "mongodb", "id"], symbol: "leaf",
                run: { $0.fill("objectid") }),
        Command(title: "Generate ULID", keywords: ["generate", "ulid", "id"], symbol: "number",
                run: { $0.fill("ulid") }),
        Command(title: "Generate Nano ID", keywords: ["generate", "nanoid", "id"], symbol: "number",
                run: { $0.fill("nanoid") }),
        Command(title: "Generate Password", keywords: ["generate", "password", "random", "secret"], symbol: "key",
                run: { $0.fill("password 20") }),
        Command(title: "Generate Random Hex", keywords: ["generate", "hex", "random", "token"], symbol: "number",
                run: { $0.fill("hex 32") }),
        // Developer tools: prefill the search box with the trigger plus whatever single-line text is on the
        // clipboard, so the result rows appear immediately (type to change the input).
        Command(title: "Base64 Encode", keywords: ["base64", "b64", "encode"], symbol: "lock.rectangle",
                run: { $0.fillFromClipboard("base64") }),
        Command(title: "Base64 Decode", keywords: ["base64", "unbase64", "b64", "decode"], symbol: "lock.open",
                run: { $0.fillFromClipboard("unbase64") }),
        Command(title: "URL Encode", keywords: ["url", "urlencode", "percent", "encode"], symbol: "link",
                run: { $0.fillFromClipboard("urlencode") }),
        Command(title: "URL Decode", keywords: ["url", "urldecode", "percent", "decode"], symbol: "link",
                run: { $0.fillFromClipboard("urldecode") }),
        Command(title: "Hash Text (MD5, SHA-1, SHA-256, SHA-512)", keywords: ["hash", "md5", "sha", "sha1", "sha256", "sha512", "checksum"],
                symbol: "number.square", run: { $0.fillFromClipboard("hash") }),
        Command(title: "Decode JWT", keywords: ["jwt", "token", "decode", "json web token"], symbol: "key.viewfinder",
                run: { $0.fillFromClipboard("jwt") }),
        Command(title: "MessagePack Encode (JSON to packb)", keywords: ["msgpack", "messagepack", "packb", "pack", "encode"], symbol: "shippingbox",
                run: { $0.fillFromClipboard("packb") }),
        Command(title: "MessagePack Decode (unpackb to JSON)", keywords: ["msgpack", "messagepack", "unpackb", "unpack", "decode"], symbol: "shippingbox.fill",
                run: { $0.fillFromClipboard("unpackb") }),
        Command(title: "Convert Color (Hex, RGB, HSL)", keywords: ["color", "colour", "hex", "rgb", "hsl", "convert"], symbol: "paintpalette",
                run: { $0.fillColor() }),
        Command(title: "Convert Text Case", keywords: ["case", "camel", "snake", "kebab", "pascal", "constant", "convert"], symbol: "textformat",
                run: { $0.fillFromClipboard("case") }),
        Command(title: "HTTP Status Code Lookup", keywords: ["http", "status", "code", "404", "error", "response"], symbol: "globe",
                run: { $0.fillFromClipboard("http") }),
        Command(title: "Convert Number Base (Hex, Binary, Octal)", keywords: ["base", "hex", "binary", "octal", "decimal", "convert", "number"],
                symbol: "number.circle", run: { $0.fillFromClipboard("base") }),
        Command(title: "Lorem Ipsum (3 paragraphs)", keywords: ["lorem", "ipsum", "placeholder", "dummy", "text", "paragraphs"], symbol: "text.alignleft",
                run: { $0.fill("lorem 3") }),
        Command(title: "Lorem Ipsum (50 words)", keywords: ["lorem", "ipsum", "placeholder", "dummy", "text", "words"], symbol: "text.alignleft",
                run: { $0.fill("lorem 50 words") }),
        Command(title: "Explain Cron Expression", keywords: ["cron", "crontab", "schedule", "next", "run"], symbol: "clock.arrow.2.circlepath",
                run: { $0.fillFromClipboard("cron") }),
        Command(title: "Compare Last Two Clipboard Items (Diff)", keywords: ["diff", "compare", "clipboard", "difference", "changes"], symbol: "plusminus.circle",
                run: { $0.openDiff() }),
        Command(title: "Generate QR Code from Clipboard", keywords: ["qr", "qrcode", "code", "barcode", "link"], symbol: "qrcode",
                run: { $0.openQR() }),
        Command(title: "Docker Containers", keywords: ["docker", "container", "containers", "logs", "stop", "start", "orbstack"], symbol: "shippingbox",
                run: { $0.openDocker() }),
        Command(title: "Local IP and Network Info", keywords: ["ip", "network", "wifi", "dns", "gateway", "address", "mac", "netinfo", "interfaces"],
                symbol: "network", run: { $0.fill("netinfo") }),
        Command(title: "Look Up Public IP", keywords: ["ip", "public", "external", "address", "ipify"], symbol: "globe.europe.africa", navigates: false,
                run: { _ in SystemActions.lookUpPublicIP() }),
        Command(title: "Regex Tester", keywords: ["regex", "regexp", "regular", "expression", "pattern", "match"], symbol: "chevron.left.forwardslash.chevron.right",
                run: { $0.openRegex() }),
        Command(title: "Create Code Snippet", keywords: ["code", "codeblock", "snippet", "new"], symbol: "chevron.left.forwardslash.chevron.right",
                run: { $0.openSnippets(direct: false, newSnippet: true, kind: .code) }),
        Command(title: "Create Terminal Command Snippet", keywords: ["terminal", "command", "shell", "snippet", "new"], symbol: "terminal",
                run: { $0.openSnippets(direct: false, newSnippet: true, kind: .command) }),
        Command(title: "Create Snippet", keywords: ["new", "snippet", "add"], symbol: "plus.square",
                run: { $0.openSnippets(direct: false, newSnippet: true) }),
    ]

    private func update() {
        var items: [ResultItem] = []
        for (i, row) in Calculator.evaluate(query, currency: CurrencyService.shared.state).enumerated() {
            items.append(ResultItem(
                id: "calc-\(i)", section: "Calculator", title: row.title, subtitle: row.subtitle,
                accessory: "Copy", primaryLabel: "Copy Result", isCalc: true, icon: nil,
                extra: calcExtras(for: row),
                run: { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(row.copy, forType: .string) }))
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        let apps = AppIndex.shared.search(q, limit: q.isEmpty ? 5 : 8)
        for app in apps {
            items.append(ResultItem(
                id: app.url.path, section: q.isEmpty ? "Suggestions" : "Applications", title: app.name, subtitle: "",
                accessory: "Application", primaryLabel: "Open Application", isCalc: false, icon: icon(for: app),
                extra: [
                    ActionItem(title: "Show in Finder", symbol: "folder", run: { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }),
                    ActionItem(title: "Copy Path", symbol: "doc.on.doc", run: {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(app.url.path, forType: .string)
                    }),
                ],
                run: {
                    AppIndex.shared.recordLaunch(app)
                    NSWorkspace.shared.openApplication(at: app.url, configuration: .init())
                }))
        }
        // Commands, scripts and Caffeinate share one list, ranked by match quality, then use, then group.
        var commandItems: [String: ResultItem] = [:]
        var ranking: [CommandRanker.Entry] = []
        func add(_ item: ResultItem, keywords: [String], group: Int) {
            commandItems[item.id] = item
            ranking.append(.init(id: item.id, title: item.title, keywords: keywords, group: group))
        }
        for c in Self.commands + Self.transformCommands {
            let id = "cmd-" + c.title
            add(ResultItem(
                id: id, section: "Commands", title: c.title, subtitle: "",
                accessory: "Command", primaryLabel: c.navigates ? "Open Command" : "Run Command", isCalc: false, icon: nil,
                symbol: c.symbol, keepsOpen: c.navigates,
                run: { [weak self] in CommandUsage.record(id); if let self { c.run(self) } }),
                keywords: c.keywords, group: Self.group(of: c.title))
        }
        for info in ScriptIndex.shared.scripts {
            let id = "script-" + info.path
            add(ResultItem(
                id: id, section: "Commands", title: info.title, subtitle: info.description,
                accessory: "Script", primaryLabel: "Run Script", isCalc: false, icon: nil,
                symbol: ScriptView.symbol(info.icon), keepsOpen: info.argument != nil || info.mode == .output,
                extra: ScriptModel.fileActions(info.path),
                run: { [weak self] in CommandUsage.record(id); self?.openScript(info) }),
                keywords: info.keywords, group: Group.scripts)
        }
        let on = Caffeinate.shared.isActive
        var extra: [ActionItem] = [ActionItem(title: "Caffeinate Indefinitely", symbol: "infinity", run: { Caffeinate.shared.start(.indefinite) })]
        for (title, m) in Caffeinate.presets {
            extra.append(ActionItem(title: "Caffeinate for \(title)", symbol: "timer", run: { Caffeinate.shared.start(.minutes(m)) }))
        }
        if on { extra.append(ActionItem(title: "Decaffeinate", symbol: "cup.and.saucer", run: { Caffeinate.shared.stop() })) }
        add(ResultItem(
            id: "cmd-caffeinate", section: "Commands", title: on ? "Decaffeinate" : "Caffeinate", subtitle: on ? "Awake" : "",
            accessory: "Command", primaryLabel: on ? "Decaffeinate" : "Caffeinate (Indefinitely)", isCalc: false, icon: nil,
            symbol: on ? "cup.and.saucer.fill" : "cup.and.saucer", extra: Array(extra.dropFirst(on ? 0 : 1)),
            run: { CommandUsage.record("cmd-caffeinate"); Caffeinate.shared.toggle() }),
            keywords: ["caffeinate", "decaffeinate", "awake", "sleep", "coffee", "caffeine", "keep awake"], group: Group.modules)
        for id in CommandRanker.order(ranking, query: q, usage: CommandUsage.counts) {
            if let item = commandItems[id] { items.append(item) }
        }
        results = items
        selection = 0
    }
}
