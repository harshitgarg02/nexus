import SwiftUI
import NexusCore

struct TransformView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var t: TransformModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { model.back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Text(t.transform?.title ?? "Transform").font(.system(size: 20, weight: .semibold)).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 22)
            .frame(height: 62)

            Group {
                switch t.result {
                case .failure(let e):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(e.localizedDescription).font(.system(size: 13, design: .monospaced)).foregroundStyle(.orange)
                        if case .invalid = e { Text("Copy the text you want to transform, then run the command again.").font(.system(size: 12)).foregroundStyle(.secondary) }
                    }
                    .padding(.horizontal, 22).padding(.top, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                case .success:
                    VStack(alignment: .leading, spacing: 8) {
                        ScrollView {
                            Text(t.preview).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        if t.isTruncated {
                            Text("Preview shows the first 20,000 characters. The full result is copied.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        if !t.summary.isEmpty { Text(t.summary).font(.system(size: 12)).foregroundStyle(.secondary) }
                    }
                    .padding(.horizontal, 22).padding(.bottom, 6)
                }
            }

            Footer(moduleIcon: t.transform?.symbol ?? "textformat", moduleName: t.transform?.title ?? "Transform",
                   primary: t.primaryLabel, onActions: { model.toggleActions() })
        }
    }
}
