import SwiftUI

struct RunningAppsView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var apps: RunningAppsModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { model.back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                TextField("Search running apps…", text: $apps.query)
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
                        SectionHeader(title: "Running Applications", first: true)
                        ForEach(Array(apps.items.enumerated()), id: \.element.processIdentifier) { i, a in
                            HStack(spacing: 12) {
                                if let icon = a.icon { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
                                Text(a.localizedName ?? "Unknown").font(.system(size: 15, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 8)
                                Text("PID \(a.processIdentifier)").font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14).frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(i == apps.selection ? Color.white.opacity(0.09) : .clear))
                            .contentShape(Rectangle())
                            .id(a.processIdentifier)
                            .onTapGesture { apps.selection = i; apps.focusTick += 1 }
                        }
                        if apps.items.isEmpty { Text("No matching apps").foregroundStyle(.secondary).padding(22) }
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: apps.selection) { _, new in
                    if apps.items.indices.contains(new) { proxy.scrollTo(apps.items[new].processIdentifier) }
                }
            }

            Footer(moduleIcon: "xmark.app.fill", moduleName: apps.title, primary: apps.primaryLabel,
                   onActions: { model.toggleActions(); apps.focusTick += 1 })
        }
        .refocusOnAppear($focused)
        .onChange(of: apps.focusTick) { _, _ in focused = true }
    }
}
