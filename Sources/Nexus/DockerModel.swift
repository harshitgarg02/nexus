import AppKit
import NexusCore

enum DockerRunner {
    /// Runs the docker CLI with stdout and stderr merged. Gives up after `timeout` seconds.
    static func run(_ args: [String], timeout: TimeInterval = 20) async -> (status: Int32, output: String) {
        guard let path = DockerCLI.locate() else { return (127, "") }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                var env = ProcessInfo.processInfo.environment
                // docker shells out to credential helpers etc., which live next to it or in Homebrew
                env["PATH"] = [(path as NSString).deletingLastPathComponent, "/opt/homebrew/bin", "/usr/local/bin", env["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
                p.environment = env
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch { cont.resume(returning: (126, error.localizedDescription)); return }
                let killer = DispatchWorkItem { p.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                killer.cancel()
                cont.resume(returning: (p.terminationStatus, String(decoding: data.suffix(1_000_000), as: UTF8.self)))
            }
        }
    }
}

final class DockerModel: ObservableObject {
    @Published var query = "" { didSet { selection = 0; applyFilter() } }
    @Published private(set) var items: [DockerContainer] = []
    @Published var selection = 0
    @Published private(set) var problem: String?
    @Published private(set) var loading = false
    /// Open log view: which container, and its recent output.
    @Published private(set) var logs: (container: DockerContainer, text: String)?
    @Published var focusTick = 0
    var dismiss: () -> Void = {}
    private var all: [DockerContainer] = []

    var selected: DockerContainer? { items.indices.contains(selection) ? items[selection] : nil }
    var primaryLabel: String { logs != nil ? "Copy Logs" : "Show Logs" }

    func open() {
        query = ""; selection = 0; logs = nil
        refresh()
        focusTick += 1
    }

    func refresh() {
        guard DockerCLI.locate() != nil else {
            problem = "The docker CLI wasn't found. Install Docker Desktop, OrbStack or Colima, then try again."
            all = []; applyFilter(); return
        }
        loading = true
        Task { @MainActor in
            let r = await DockerRunner.run(["ps", "-a", "--format", "{{json .}}"])
            loading = false
            if r.status == 0 { problem = nil; all = DockerCLI.parsePS(r.output) }
            else {
                all = []
                problem = r.output.contains("Cannot connect") || r.output.contains("daemon") ? "Docker isn't running. Start it and try again."
                    : "docker failed: " + (r.output.split(separator: "\n").first.map(String.init) ?? "exit \(r.status)")
            }
            applyFilter()
        }
    }

    private func applyFilter() {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        items = q.isEmpty ? all : all.filter { $0.name.lowercased().contains(q) || $0.image.lowercased().contains(q) || $0.id.hasPrefix(q) }
        if selection >= items.count { selection = max(0, items.count - 1) }
    }

    func move(_ d: Int) {
        guard logs == nil, !items.isEmpty else { return }
        selection = (selection + d + items.count) % items.count
    }

    /// ⎋ closes the log view first; returns false when there was nothing to close.
    func closeLogs() -> Bool {
        guard logs != nil else { return false }
        logs = nil; focusTick += 1
        return true
    }

    func submit() {
        if let l = logs { copy(l.text) } else { showLogs() }
    }

    func showLogs() {
        guard let c = selected else { return }
        logs = (c, "Loading…")
        Task { @MainActor in
            let r = await DockerRunner.run(["logs", "--tail", "300", c.id])
            guard logs?.container.id == c.id else { return }
            logs = (c, r.output.isEmpty ? "(no output)" : r.output)
        }
    }

    private func act(_ args: [String]) {
        Task { @MainActor in
            let r = await DockerRunner.run(args, timeout: 60)
            if r.status != 0 { problem = "docker \(args[0]) failed: " + (r.output.split(separator: "\n").last.map(String.init) ?? "") }
            refresh()
        }
    }

    func start() { if let c = selected { act(["start", c.id]) } }
    func stop() { if let c = selected { act(["stop", c.id]) } }
    func restart() { if let c = selected { act(["restart", c.id]) } }

    func remove() {
        guard let c = selected else { return }
        let a = NSAlert()
        a.messageText = "Remove container “\(c.name)”?"
        a.informativeText = c.isRunning ? "It is running and will be force-removed. Its anonymous volumes are kept." : "The container will be deleted."
        a.addButton(withTitle: "Remove")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        act(["rm", "-f", c.id])
    }

    private func copy(_ s: String) {
        dismiss()
        ClipboardService.shared.write(paste: false) { $0.setString(s, forType: .string) }
    }

    var actions: [ActionItem] {
        if let l = logs {
            return [ActionItem(title: "Copy Logs", symbol: "doc.on.doc", run: { [self] in copy(l.text) }),
                    ActionItem(title: "Refresh Logs", symbol: "arrow.clockwise", keepsOpen: true, run: { [self] in showLogs() }),
                    ActionItem(title: "Back to Containers", symbol: "chevron.left", keepsOpen: true, run: { [self] in _ = closeLogs() })]
        }
        guard let c = selected else { return [ActionItem(title: "Refresh", symbol: "arrow.clockwise", keepsOpen: true, run: { [self] in refresh() })] }
        var a = [ActionItem(title: "Show Logs", symbol: "text.alignleft", keepsOpen: true, run: { [self] in showLogs() })]
        if c.isRunning {
            a.append(ActionItem(title: "Stop", symbol: "stop.fill", keepsOpen: true, run: { [self] in stop() }))
            a.append(ActionItem(title: "Restart", symbol: "arrow.clockwise", keepsOpen: true, run: { [self] in restart() }))
        } else {
            a.append(ActionItem(title: "Start", symbol: "play.fill", keepsOpen: true, run: { [self] in start() }))
        }
        if let p = c.hostPort {
            a.append(ActionItem(title: "Open localhost:\(p)", symbol: "safari", run: { if let u = URL(string: "http://localhost:\(p)") { NSWorkspace.shared.open(u) } }))
        }
        a.append(ActionItem(title: "Copy Container ID", symbol: "doc.on.doc", run: { [self] in copy(c.id) }))
        a.append(ActionItem(title: "Copy Name", symbol: "textformat", run: { [self] in copy(c.name) }))
        a.append(ActionItem(title: "Remove…", symbol: "trash", destructive: true, keepsOpen: true, run: { [self] in remove() }))
        a.append(ActionItem(title: "Refresh", symbol: "arrow.clockwise", keepsOpen: true, run: { [self] in refresh() }))
        return a
    }
}
