import AppKit
import NexusCore

final class ScriptModel: ObservableObject {
    enum Phase { case prompt, running, result(ScriptOutcome) }

    @Published private(set) var info: ScriptInfo?
    @Published var arg = ""
    @Published private(set) var phase = Phase.prompt
    @Published var focusTick = 0
    var targetApp: NSRunningApplication?
    var dismiss: () -> Void = {}

    var primaryLabel: String {
        switch phase {
        case .prompt: return "Run Script"
        case .running: return "Running…"
        case .result: return "Copy Output"
        }
    }

    /// Starts a script from the root list. Returns after deciding: prompt for an argument, or run right away.
    func open(_ i: ScriptInfo) {
        info = i
        arg = ""
        phase = .prompt
        if i.argument == nil { execute() }
        focusTick += 1
    }

    func submit() {
        switch phase {
        case .prompt: execute()
        case .result(let o): copyOutput(o)
        case .running: break
        }
    }

    func execute() {
        guard let i = info else { return }
        let argument = i.argument == nil ? nil : arg
        // Fire-and-forget modes close the overlay first; "output" stays to show the result.
        if i.mode == .output { phase = .running } else { dismiss() }
        let target = targetApp
        ScriptRunner.run(i.path, argument: argument) { [self] o in finish(i, o, target: target) }
    }

    private func finish(_ i: ScriptInfo, _ o: ScriptOutcome, target: NSRunningApplication?) {
        guard o.succeeded else {
            if i.mode == .output { phase = .result(o) } else { Self.showFailure(i, o) }
            return
        }
        switch i.mode {
        case .output: phase = .result(o)
        case .clipboard: ClipboardService.shared.write(paste: false) { $0.setString(o.text, forType: .string) }
        case .paste:
            target?.activate()
            ClipboardService.shared.write(paste: true) { $0.setString(o.text, forType: .string) }
        case .silent: break
        }
    }

    private func copyOutput(_ o: ScriptOutcome) {
        dismiss()
        ClipboardService.shared.write(paste: false) { $0.setString(o.text, forType: .string) }
    }

    private func pasteOutput(_ o: ScriptOutcome) {
        let target = targetApp
        dismiss()
        target?.activate()
        ClipboardService.shared.write(paste: true) { $0.setString(o.text, forType: .string) }
    }

    private static func showFailure(_ i: ScriptInfo, _ o: ScriptOutcome) {
        let a = NSAlert()
        a.messageText = "“\(i.title)” failed"
        a.informativeText = failureText(o)
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    static func failureText(_ o: ScriptOutcome) -> String {
        if let e = o.launchError { return e }
        if o.timedOut { return "Timed out after \(Int(ScriptRunner.timeout)) seconds." }
        let tail = o.stderr.split(separator: "\n").suffix(6).joined(separator: "\n")
        return "Exit status \(o.status)." + (tail.isEmpty ? "" : "\n\n" + tail)
    }

    var actions: [ActionItem] {
        guard let i = info else { return [] }
        var a: [ActionItem] = []
        switch phase {
        case .prompt:
            a.append(ActionItem(title: "Run Script", symbol: "play.fill", run: { [self] in execute() }))
        case .running: break
        case .result(let o):
            a.append(ActionItem(title: "Copy Output", symbol: "doc.on.doc", run: { [self] in copyOutput(o) }))
            if o.succeeded {
                a.append(ActionItem(title: "Paste Output to \(targetApp?.localizedName ?? "Frontmost App")", symbol: "arrow.right.doc.on.clipboard",
                                    run: { [self] in pasteOutput(o) }))
            }
            a.append(ActionItem(title: "Run Again", symbol: "arrow.clockwise", keepsOpen: true, run: { [self] in execute() }))
        }
        a.append(contentsOf: Self.fileActions(i.path))
        return a
    }

    /// Shared with the root list rows.
    static func fileActions(_ path: String) -> [ActionItem] {
        [ActionItem(title: "Edit Script", symbol: "pencil", run: {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-t", path] // default text editor, never runs the file
            try? p.run()
        }),
         ActionItem(title: "Show in Finder", symbol: "folder", run: { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) })]
    }
}
