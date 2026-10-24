import SwiftUI
import NexusCore

struct RegexView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var rx: RegexModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { model.back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Text("/").font(.system(size: 22, design: .monospaced)).foregroundStyle(.secondary)
                TextField("pattern", text: $rx.pattern)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, design: .monospaced))
                    .focused($focused)
                    .onKeyPress(.escape) { model.key(.escape); return .handled }
                Text("/").font(.system(size: 22, design: .monospaced)).foregroundStyle(.secondary)
                flag("i", "Ignore case", $rx.ignoreCase)
                flag("m", "Multiline: ^ and $ match at each line", $rx.multiline)
                flag("s", "Dot matches newlines", $rx.dotAll)
            }
            .padding(.horizontal, 22)
            .frame(height: 62)

            VStack(alignment: .leading, spacing: 4) {
                Text("Test text").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                TextEditor(text: $rx.text)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
                    .frame(height: 96)
                    .onKeyPress(.escape) { model.key(.escape); return .handled }
            }
            .padding(.horizontal, 22)

            results.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Footer(moduleIcon: "chevron.left.forwardslash.chevron.right", moduleName: "Regex Tester", primary: rx.primaryLabel,
                   primaryKey: "⌘↵", onActions: { model.toggleActions() })
            // ⌘↵ copies (plain ↵ belongs to the text editor)
            Button("") { rx.submit() }.keyboardShortcut(.return, modifiers: .command).frame(width: 0, height: 0).opacity(0)
        }
        .refocusOnAppear($focused)
        .onChange(of: rx.focusTick) { _, _ in focused = true }
    }

    @ViewBuilder private var results: some View {
        switch rx.result {
        case .failure(let e):
            Text(e.localizedDescription).font(.system(size: 12, design: .monospaced)).foregroundStyle(.orange).padding(.horizontal, 22).padding(.top, 10)
        case .success(let m):
            if rx.pattern.isEmpty {
                Text("Type a pattern. Matches appear here as you type.").foregroundStyle(.secondary).padding(.horizontal, 22).padding(.top, 10)
            } else if m.isEmpty {
                Text("No matches").foregroundStyle(.secondary).padding(.horizontal, 22).padding(.top, 10)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        Text("\(m.count)\(m.count >= RegexTool.matchLimit ? "+" : "") match\(m.count == 1 ? "" : "es")")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).padding(.top, 8)
                        ForEach(Array(m.enumerated()), id: \.offset) { i, x in matchRow(i, x) }
                    }
                    .padding(.horizontal, 22).padding(.bottom, 8)
                }
            }
        }
    }

    private func matchRow(_ i: Int, _ x: RegexMatch) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("\(i + 1)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 24, alignment: .trailing)
                Text(x.text.isEmpty ? "(empty match)" : x.text).font(.system(size: 13, design: .monospaced)).lineLimit(2)
                Spacer(minLength: 6)
                Text("\(x.range.location)–\(x.range.location + x.range.length)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            let groups = x.groups.enumerated().map { "$\($0.offset + 1) = \($0.element ?? "∅")" } + x.named.map { "\($0.name) = \($0.text ?? "∅")" }
            if !groups.isEmpty {
                Text(groups.joined(separator: "   ")).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .padding(.leading, 32).lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }

    private func flag(_ letter: String, _ help: String, _ on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            Text(letter).font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(on.wrappedValue ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
