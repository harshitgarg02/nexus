import SwiftUI
import NexusCore

struct ScriptView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var script: ScriptModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { model.back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                if case .prompt = script.phase, let placeholder = script.info?.argument {
                    TextField(placeholder, text: $script.arg)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22))
                        .focused($focused)
                        .onKeyPress(.return) { model.key(.enter); return .handled }
                        .onKeyPress(.escape) { model.key(.escape); return .handled }
                } else {
                    Text(script.info?.title ?? "Script").font(.system(size: 20, weight: .semibold))
                    Spacer()
                }
            }
            .padding(.horizontal, 22)
            .frame(height: 62)

            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Footer(moduleIcon: script.info.map { Self.symbol($0.icon) } ?? "terminal", moduleName: script.info?.title ?? "Script",
                   primary: script.primaryLabel, onActions: { model.toggleActions(); script.focusTick += 1 })
        }
        .refocusOnAppear($focused)
        .onChange(of: script.focusTick) { _, _ in focused = true }
    }

    @ViewBuilder private var content: some View {
        switch script.phase {
        case .prompt:
            VStack(alignment: .leading, spacing: 6) {
                if let d = script.info?.description, !d.isEmpty { Text(d).foregroundStyle(.secondary) }
                Text("Press ↵ to run.").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 22).padding(.top, 4)
        case .running:
            HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Running…").foregroundStyle(.secondary) }
                .padding(.horizontal, 22).padding(.top, 8)
        case .result(let o):
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !o.succeeded {
                        Text(ScriptModel.failureText(o)).font(.system(size: 12, design: .monospaced)).foregroundStyle(.orange)
                    }
                    if !o.stdout.isEmpty {
                        Text(o.stdout).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                    } else if o.succeeded {
                        Text("(no output)").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 22).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    /// Falls back to a terminal icon when the header names a symbol that doesn't exist.
    static func symbol(_ name: String) -> String {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : "terminal"
    }
}
