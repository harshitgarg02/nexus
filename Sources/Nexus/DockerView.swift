import SwiftUI
import NexusCore

struct DockerView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var docker: DockerModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { if !docker.closeLogs() { model.back() } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                if let l = docker.logs {
                    Text("Logs · \(l.container.name)").font(.system(size: 20, weight: .semibold)).lineLimit(1)
                    Spacer()
                } else {
                    TextField("Filter containers…", text: $docker.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22))
                        .focused($focused)
                        .onKeyPress(.downArrow) { model.key(.down); return .handled }
                        .onKeyPress(.upArrow) { model.key(.up); return .handled }
                        .onKeyPress(.return) { model.key(.enter); return .handled }
                        .onKeyPress(.escape) { model.key(.escape); return .handled }
                    if docker.loading { ProgressView().controlSize(.small) }
                }
            }
            .padding(.horizontal, 22)
            .frame(height: 62)

            if let l = docker.logs { logView(l.text) } else { list }

            Footer(moduleIcon: "shippingbox", moduleName: "Docker", primary: docker.primaryLabel, onActions: { model.toggleActions(); docker.focusTick += 1 })
        }
        .refocusOnAppear($focused)
        .onChange(of: docker.focusTick) { _, _ in focused = true }
    }

    private func logView(_ text: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading).padding(.horizontal, 22)
                Color.clear.frame(height: 1).id("end")
            }
            .onChange(of: text) { _, _ in proxy.scrollTo("end") }
            .onAppear { proxy.scrollTo("end") }
        }
    }

    @ViewBuilder private var list: some View {
        if let p = docker.problem, docker.items.isEmpty {
            Text(p).foregroundStyle(.orange).padding(.horizontal, 22).padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        SectionHeader(title: "Containers", first: true)
                        ForEach(Array(docker.items.enumerated()), id: \.element.id) { i, c in
                            HStack(spacing: 12) {
                                Circle().fill(c.isRunning ? Color.green : c.state == "paused" ? Color.yellow : Color.gray).frame(width: 9, height: 9)
                                Text(c.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                                Text(c.image).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                                Spacer(minLength: 8)
                                if let port = c.hostPort { Text(":\(port)").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary) }
                                Text(c.status).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(.horizontal, 14).frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(i == docker.selection ? Color.white.opacity(0.09) : .clear))
                            .contentShape(Rectangle())
                            .id(c.id)
                            .onTapGesture { docker.selection = i; docker.focusTick += 1 }
                        }
                        if docker.items.isEmpty && !docker.loading { Text("No containers").foregroundStyle(.secondary).padding(22) }
                        if let p = docker.problem { Text(p).font(.caption).foregroundStyle(.orange).padding(.horizontal, 22) }
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: docker.selection) { _, new in
                    if docker.items.indices.contains(new) { proxy.scrollTo(docker.items[new].id) }
                }
            }
        }
    }
}
