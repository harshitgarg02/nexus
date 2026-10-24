import SwiftUI

struct LauncherView: View {
    @ObservedObject var model: SearchModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            switch model.mode {
            case .root: RootView(model: model)
            case .clipboard: ClipboardView(model: model, clip: model.clipboard)
            case .snippets: SnippetsView(model: model, sn: model.snippets)
            case .totp: TOTPView(model: model, t: model.totp)
            case .ports: PortsView(model: model, ports: model.ports)
            case .apps: RunningAppsView(model: model, apps: model.apps)
            case .script: ScriptView(model: model, script: model.script)
            case .transform: TransformView(model: model, t: model.transform)
            case .regex: RegexView(model: model, rx: model.regex)
            case .diff: DiffView(model: model, diff: model.diff)
            case .qr: QRView(model: model, qr: model.qr)
            case .docker: DockerView(model: model, docker: model.docker)
            }
            if model.actionsOpen {
                ActionsPopup(model: model)
                    .padding(.trailing, 14).padding(.bottom, 58)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.1), value: model.actionsOpen)
    }
}

struct RootView: View {
    @ObservedObject var model: SearchModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(.secondary)
                TextField("Search for apps or commands...", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .focused($focused)
                    .onKeyPress(.downArrow) { model.key(.down); return .handled }
                    .onKeyPress(.upArrow) { model.key(.up); return .handled }
                    .onKeyPress(.return) { model.key(.enter); return .handled }
                    .onKeyPress(.escape) { model.key(.escape); return .handled }
            }
            .padding(.horizontal, 22)
            .frame(height: 62)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.results.enumerated()), id: \.element.id) { i, item in
                            if i == 0 || model.results[i - 1].section != item.section {
                                SectionHeader(title: item.section, first: i == 0)
                            }
                            row(item, selected: i == model.selection)
                                .id(item.id)
                                .onTapGesture { model.selection = i; model.runSelected(); model.focusTick += 1 }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: model.selection) { _, new in
                    if model.results.indices.contains(new) { proxy.scrollTo(model.results[new].id) }
                }
            }

            Footer(moduleIcon: "command.square.fill", moduleName: "Nexus",
                   primary: model.results.indices.contains(model.selection) ? model.results[model.selection].primaryLabel : "",
                   onActions: { model.toggleActions(); model.focusTick += 1 })
        }
        .refocusOnAppear($focused)
        .onChange(of: model.focusTick) { _, _ in focused = true }
    }

    private func row(_ item: ResultItem, selected: Bool) -> some View {
        HStack(spacing: 12) {
            if let icon = item.icon {
                Image(nsImage: icon).resizable().frame(width: 28, height: 28)
            } else if let symbol = item.symbol {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.orange.gradient))
            } else {
                Image(systemName: "equal.square.fill").font(.system(size: 24)).foregroundStyle(.orange).frame(width: 28, height: 28)
            }
            if selected && item.isCalc {
                // the highlighted result wraps so long output (hex, JSON, bytes) can be read without copying
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 17, weight: .medium)).lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            } else {
                Text(item.title)
                    .font(.system(size: item.isCalc ? 17 : 15, weight: .medium))
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(item.accessory).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, selected && item.isCalc ? 6 : 0)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Color.white.opacity(0.09) : .clear))
        .contentShape(Rectangle())
    }
}

struct SectionHeader: View {
    let title: String
    var first = false
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.top, first ? 6 : 14).padding(.bottom, 4)
    }
}

struct Footer: View {
    let moduleIcon: String
    let moduleName: String
    let primary: String
    var primaryKey = "↵"
    var onActions: () -> Void = {}

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: moduleIcon).font(.system(size: 18))
                Text(moduleName).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).frame(height: 32)
            Spacer()
            HStack(spacing: 10) {
                Text(primary).font(.system(size: 13)).lineLimit(1)
                Keycap(primaryKey)
                Button(action: onActions) {
                    HStack(spacing: 10) {
                        Text("Actions").font(.system(size: 13)).foregroundStyle(.secondary)
                        Keycap("⌘"); Keycap("K")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).frame(height: 36)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 6)
    }
}

struct Keycap: View {
    let s: String
    init(_ s: String) { self.s = s }
    var body: some View {
        Text(s).font(.system(size: 11, weight: .medium))
            .frame(minWidth: 20, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.25), lineWidth: 1))
    }
}

/// ⌘K menu, anchored above the footer. Keys are routed through SearchModel.key (the search field keeps focus).
struct ActionsPopup: View {
    @ObservedObject var model: SearchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.actions.enumerated()), id: \.element.id) { i, a in
                HStack(spacing: 10) {
                    Image(systemName: a.symbol).frame(width: 18)
                    Text(a.title).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 13))
                .foregroundStyle(a.destructive ? Color.red : Color.primary)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(i == model.actionSelection ? Color.white.opacity(0.12) : .clear))
                .contentShape(Rectangle())
                .onTapGesture { model.actionSelection = i; model.key(.enter) }
            }
        }
        .padding(6)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 4)
    }
}
