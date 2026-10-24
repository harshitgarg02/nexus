import AppKit
import UniformTypeIdentifiers
import NexusCore

/// Save/open panels and result alerts for snippet backup. Secret snippets are never exported.
enum SnippetTransferUI {
    static func export() {
        do {
            let out = try SnippetTransfer.export(SnippetsModel.sharedStore.all())
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "nexus-snippets.json"
            panel.allowedContentTypes = [.json]
            panel.message = "Export snippets (secret snippets are not included)"
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try out.data.write(to: url, options: .atomic)
            var msg = "Exported \(out.exported) snippet\(out.exported == 1 ? "" : "s") to \(url.lastPathComponent)."
            if out.skippedSecrets > 0 {
                msg += "\n\(out.skippedSecrets) secret snippet\(out.skippedSecrets == 1 ? " was" : "s were") not exported: their values stay in your Keychain."
            }
            alert("Export complete", msg)
        } catch {
            alert("Export failed", error.localizedDescription)
        }
    }

    static func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Nexus snippet export (.json)"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let entries = try SnippetTransfer.decode(try Data(contentsOf: url))
            let s = SnippetsModel.sharedStore.importEntries(entries)
            var lines = ["Added \(s.added)."]
            if s.duplicates > 0 { lines.append("Skipped \(s.duplicates) already present.") }
            if s.renamed > 0 { lines.append("\(s.renamed) had a name clash with different content and were added as “… (imported)”.") }
            if s.invalid > 0 { lines.append("Ignored \(s.invalid) with an empty name or content.") }
            alert("Import complete", lines.joined(separator: "\n"))
        } catch {
            alert("Import failed", error.localizedDescription)
        }
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
