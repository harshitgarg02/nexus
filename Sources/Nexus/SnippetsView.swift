import SwiftUI
import NexusCore

struct SnippetsView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var sn: SnippetsModel
    @FocusState private var focused: Bool

    var body: some View {
        if sn.editor != nil {
            SnippetEditorView(model: model, sn: sn)
        } else {
            browser
        }
    }

    private var browser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { model.back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                TextField("Search snippets…", text: $sn.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .focused($focused)
                    .onKeyPress(.downArrow) { model.key(.down); return .handled }
                    .onKeyPress(.upArrow) { model.key(.up); return .handled }
                    .onKeyPress(.return) { model.key(.enter); return .handled }
                    .onKeyPress(.escape) { model.key(.escape); return .handled }
                Menu {
                    Button { sn.tagFilter = nil } label: { Label("All Tags", systemImage: "tag") }
                    ForEach(sn.tags, id: \.self) { t in Button { sn.tagFilter = t } label: { Text(t) } }
                } label: {
                    Label(sn.tagFilter ?? "All Tags", systemImage: "tag").font(.system(size: 14)).foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton).fixedSize()
                Button { sn.beginNew() } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("New Snippet (⌘N)")
            }
            .padding(.horizontal, 22)
            .frame(height: 62)

            HStack(spacing: 0) {
                list.frame(width: 290)
                Divider().opacity(0.3)
                detail.frame(maxWidth: .infinity)
            }

            Footer(moduleIcon: "text.quote", moduleName: "Search Snippets", primary: sn.primaryLabel,
                   onActions: { model.toggleActions(); sn.focusTick += 1 })
        }
        .refocusOnAppear($focused)
        .onChange(of: sn.focusTick) { _, _ in focused = true }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(sn.items.enumerated()), id: \.element.id) { i, s in
                        if i == 0 || SnippetsModel.group(for: sn.items[i - 1]) != SnippetsModel.group(for: s) {
                            SectionHeader(title: SnippetsModel.group(for: s), first: i == 0)
                        }
                        HStack(spacing: 12) {
                            Image(systemName: s.isSecret ? "lock.fill" : Self.symbol(s.kind))
                                .font(.system(size: 16)).foregroundStyle(s.isSecret ? Color.orange : .secondary).frame(width: 28)
                            Text(s.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(i == sn.selection ? Color.white.opacity(0.09) : .clear))
                        .contentShape(Rectangle())
                        .id(s.id)
                        .onTapGesture { sn.selection = i; sn.focusTick += 1 }
                    }
                    if sn.items.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(sn.query.isEmpty ? "No snippets yet" : "No matches").foregroundStyle(.secondary)
                            Button("New Snippet") { sn.beginNew() }.buttonStyle(.link)
                        }.padding(22)
                    }
                }
                .padding(.horizontal, 8)
            }
            .onChange(of: sn.selection) { _, new in
                if sn.items.indices.contains(new) { proxy.scrollTo(sn.items[new].id) }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let s = sn.selected {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView {
                    Group {
                        if s.isSecret && sn.revealed == nil {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("••••••••••").font(.system(size: 20, design: .monospaced))
                                Text("Secret. Pasting works without a prompt; revealing or editing needs your Mac login (⌘K → Reveal).")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        } else {
                            Text(s.isSecret ? (sn.revealed ?? "") : s.content)
                                .font(.system(size: 13, design: s.kind != .text || s.content.contains("\n") ? .monospaced : .default))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxHeight: .infinity)
                Text("Information").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                info(s)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        } else {
            Color.clear
        }
    }

    static func symbol(_ k: SnippetKind) -> String {
        switch k {
        case .text: return "doc.text"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .command: return "terminal"
        }
    }

    static func typeLabel(_ s: Snippet) -> String {
        var t = s.kind.title
        if s.kind == .code, !s.language.isEmpty { t += " (\(s.language))" }
        return s.isSecret ? "Secret \(t.lowercased())" : t
    }

    private func info(_ s: Snippet) -> some View {
        let date: (Date) -> Text = { Text($0, format: .dateTime.day().month().year().hour().minute().second()) }
        let rows: [(String, Text)] = [
            ("Name", Text(s.name)),
            ("Content Type", Text(Self.typeLabel(s))),
            ("Tags", Text(s.tags.isEmpty ? "—" : s.tags.joined(separator: ", "))),
            ("Times Copied", Text("\(s.timesUsed)")),
            ("Last Copied", s.lastUsed.map(date) ?? Text("Never")),
            ("Modified", date(s.modified)),
            ("Created", date(s.created)),
        ]
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                HStack {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer()
                    row.1.lineLimit(1)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 10).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(i % 2 == 0 ? 0.05 : 0)))
            }
        }
    }
}

struct SnippetEditorView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var sn: SnippetsModel
    @FocusState private var nameFocused: Bool

    private var e: Binding<SnippetEditor> {
        Binding(get: { sn.editor ?? SnippetEditor() }, set: { sn.editor = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button { sn.cancelEditor() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Text(e.wrappedValue.id == nil ? "New Snippet" : "Edit Snippet").font(.system(size: 20, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 22).frame(height: 62)

            ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                field("Name") {
                    TextField("e.g. username", text: e.name).textFieldStyle(.plain).focused($nameFocused)
                        .onKeyPress(.escape) { model.key(.escape); return .handled }
                }
                field("Tags (comma separated)") {
                    TextField("work, dev", text: e.tags).textFieldStyle(.plain)
                        .onKeyPress(.escape) { model.key(.escape); return .handled }
                }
                Picker("Type", selection: e.kind) {
                    ForEach(SnippetKind.allCases, id: \.self) { Label($0.title, systemImage: SnippetsView.symbol($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                if e.wrappedValue.kind == .code {
                    field("Language (optional, e.g. swift, bash, json)") {
                        TextField("swift", text: e.language).textFieldStyle(.plain)
                            .onKeyPress(.escape) { model.key(.escape); return .handled }
                    }
                }
                Toggle(isOn: e.isSecret) {
                    Label("Secret (stored in Keychain, masked, login needed to edit or reveal)", systemImage: "lock")
                        .font(.system(size: 13))
                }
                field("Content  ·  {clipboard} {date} {time} {datetime}") {
                    if e.wrappedValue.isSecret {
                        SecureField("Secret value", text: e.content).textFieldStyle(.plain)
                            .onKeyPress(.escape) { model.key(.escape); return .handled }
                    } else {
                        TextEditor(text: e.content)
                            .font(.system(size: 13, design: e.wrappedValue.kind == .text ? .default : .monospaced))
                            .scrollContentBackground(.hidden)
                            .frame(height: 110)
                            .onKeyPress(.escape) { model.key(.escape); return .handled }
                    }
                }
                if let err = e.wrappedValue.error { Text(err).font(.caption).foregroundStyle(.red) }
            }
            .padding(.horizontal, 22)
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { sn.cancelEditor() }
                Button { sn.saveEditor() } label: {
                    HStack(spacing: 6) { Text("Save"); Keycap("⌘"); Keycap("↵") }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 22).padding(.bottom, 16)
        }
        .refocusOnAppear($nameFocused)
        .onChange(of: sn.focusTick) { _, _ in nameFocused = true }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            content()
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
        }
    }
}
