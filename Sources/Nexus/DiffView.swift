import SwiftUI
import NexusCore

struct DiffView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var diff: DiffModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { model.back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Text("Compare Last Two Copies").font(.system(size: 20, weight: .semibold))
                Spacer()
                if diff.message == nil {
                    HStack(spacing: 8) {
                        Text("+\(diff.stats.added)").foregroundStyle(.green)
                        Text("−\(diff.stats.removed)").foregroundStyle(.red)
                        Text(diff.direction).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12, design: .monospaced))
                }
            }
            .padding(.horizontal, 22)
            .frame(height: 62)

            if let m = diff.message {
                Text(m).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.top, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diff.rows.enumerated()), id: \.offset) { _, row in
                            switch row {
                            case .skipped(let n):
                                Text("⋯ \(n) unchanged line\(n == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 4)
                            case .line(let l):
                                HStack(alignment: .top, spacing: 8) {
                                    Text(l.kind == .added ? "+" : l.kind == .removed ? "−" : " ")
                                        .foregroundStyle(l.kind == .added ? .green : l.kind == .removed ? .red : .clear)
                                    Text(l.text.isEmpty ? " " : l.text).foregroundStyle(l.kind == .same ? .secondary : .primary)
                                    Spacer(minLength: 0)
                                }
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 22).padding(.vertical, 1)
                                .background(l.kind == .added ? Color.green.opacity(0.14) : l.kind == .removed ? Color.red.opacity(0.14) : .clear)
                                .textSelection(.enabled)
                            }
                        }
                    }
                }
            }

            Footer(moduleIcon: "plusminus.circle", moduleName: "Clipboard Diff", primary: diff.primaryLabel, onActions: { model.toggleActions() })
        }
    }
}
