import SwiftUI
import NexusCore

struct TOTPView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var t: TOTPModel
    @FocusState private var focused: Bool

    var body: some View {
        if t.editor != nil { TOTPEditorView(model: model, t: t) } else { browser }
    }

    private var browser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { model.back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                TextField("Search…", text: $t.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .focused($focused)
                    .onKeyPress(.downArrow) { model.key(.down); return .handled }
                    .onKeyPress(.upArrow) { model.key(.up); return .handled }
                    .onKeyPress(.return) { model.key(.enter); return .handled }
                    .onKeyPress(.escape) { model.key(.escape); return .handled }
                Button { t.beginNew() } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("New entry (⌘N)")
            }
            .padding(.horizontal, 22)
            .frame(height: 62)

            ScrollView {
                // One timeline for all rows so every code and ring ticks together.
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(t.items.enumerated()), id: \.element.id) { i, e in
                            row(e, selected: i == t.selection, now: ctx.date)
                                .onTapGesture { t.selection = i; t.focusTick += 1 }
                        }
                        if t.items.isEmpty { empty }
                    }
                    .padding(.horizontal, 8)
                }
            }

            if let n = t.notice {
                Text(n).font(.system(size: 12)).foregroundStyle(.orange).padding(.horizontal, 22).padding(.bottom, 4)
            }
            Footer(moduleIcon: "lock.shield.fill", moduleName: "Generate 2FA Code", primary: t.primaryLabel,
                   onActions: { model.toggleActions(); t.focusTick += 1 })
        }
        .refocusOnAppear($focused)
        .onChange(of: t.focusTick) { _, _ in focused = true }
    }

    private func row(_ e: TOTPEntry, selected: Bool, now: Date) -> some View {
        let left = TOTP.remaining(at: now, period: e.period)
        let code = t.code(for: e, at: now) ?? "······"
        let next = left <= 5 && Settings.shared.data.totpShowNextCode ? t.code(for: e, at: now.addingTimeInterval(Double(left))) : nil
        return HStack(spacing: 14) {
            Text(e.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
            Text(code).font(.system(size: 15, design: .monospaced)).foregroundStyle(.secondary)
            if let next {
                Text("→ \(next)").font(.system(size: 12, design: .monospaced)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Ring(fraction: Double(left) / Double(e.period), warn: left <= 5).frame(width: 20, height: 20)
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Color.white.opacity(0.09) : .clear))
        .contentShape(Rectangle())
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t.query.isEmpty ? "No 2FA entries yet" : "No matches").foregroundStyle(.secondary)
            if t.query.isEmpty {
                Button("Add an entry (secret or otpauth:// link)") { t.beginNew() }.buttonStyle(.link)
                Button("Import QR from clipboard image") { t.importFromClipboardQR() }.buttonStyle(.link)
            }
        }.padding(22)
    }
}

struct Ring: View {
    let fraction: Double
    let warn: Bool
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 2.5)
            Circle().trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(warn ? Color.orange : Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct TOTPEditorView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var t: TOTPModel
    @FocusState private var nameFocused: Bool

    private var e: Binding<TOTPEditor> { Binding(get: { t.editor ?? TOTPEditor() }, set: { t.editor = $0 }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button { t.cancelEditor() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Text(e.wrappedValue.id == nil ? "New 2FA Entry" : "Edit 2FA Entry").font(.system(size: 20, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 22).frame(height: 62)

            VStack(alignment: .leading, spacing: 14) {
                field("Name") {
                    TextField("e.g. Work VPN", text: e.name).textFieldStyle(.plain).focused($nameFocused)
                        .onKeyPress(.escape) { model.key(.escape); return .handled }
                }
                field(e.wrappedValue.id == nil ? "Secret (base32) or otpauth:// link" : "New secret (leave blank to keep the current one)") {
                    SecureField("Base32 secret", text: e.secret).textFieldStyle(.plain)
                        .onKeyPress(.escape) { model.key(.escape); return .handled }
                }
                HStack(spacing: 16) {
                    Picker("Algorithm", selection: e.algorithm) {
                        ForEach(TOTPAlgorithm.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Digits", selection: e.digits) { ForEach(6...8, id: \.self) { Text("\($0)").tag($0) } }
                    Picker("Period", selection: e.period) { ForEach([15, 30, 60], id: \.self) { Text("\($0)s").tag($0) } }
                }
                Text("Most services use SHA1, 6 digits, 30 s. A pasted otpauth:// link fills these in. The secret is stored in the Keychain.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if let err = e.wrappedValue.error { Text(err).font(.caption).foregroundStyle(.red) }
            }
            .padding(.horizontal, 22)

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { t.cancelEditor() }
                Button { t.saveEditor() } label: { HStack(spacing: 6) { Text("Save"); Keycap("⌘"); Keycap("↵") } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 22).padding(.bottom, 16)
        }
        .refocusOnAppear($nameFocused)
        .onChange(of: t.focusTick) { _, _ in nameFocused = true }
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
