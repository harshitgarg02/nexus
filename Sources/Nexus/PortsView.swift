import SwiftUI
import NexusCore

struct PortsView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var ports: PortsModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { model.back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                TextField("Filter by port, name or PID…", text: $ports.query)
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
                        SectionHeader(title: "Open Ports", first: true)
                        ForEach(Array(ports.items.enumerated()), id: \.element.id) { i, p in
                            HStack(spacing: 12) {
                                Image(systemName: "network").font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 28)
                                Text(String(p.port)).font(.system(size: 15, weight: .medium, design: .monospaced))
                                Text("·").foregroundStyle(.secondary)
                                Text(p.name).font(.system(size: 15)).lineLimit(1)
                                Spacer(minLength: 8)
                                Text("PID \(p.pid)").font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14).frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(i == ports.selection ? Color.white.opacity(0.09) : .clear))
                            .contentShape(Rectangle())
                            .id(p.id)
                            .onTapGesture { ports.selection = i; ports.focusTick += 1 }
                        }
                        if ports.items.isEmpty { Text("No listening ports").foregroundStyle(.secondary).padding(22) }
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: ports.selection) { _, new in
                    if ports.items.indices.contains(new) { proxy.scrollTo(ports.items[new].id) }
                }
            }

            Footer(moduleIcon: "network", moduleName: "Open Ports", primary: ports.primaryLabel,
                   onActions: { model.toggleActions(); ports.focusTick += 1 })
        }
        .refocusOnAppear($focused)
        .onChange(of: ports.focusTick) { _, _ in focused = true }
    }
}
