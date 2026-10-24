import SwiftUI

struct QRView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var qr: QRModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { model.back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                TextField("Text or URL to encode", text: $qr.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
                    .focused($focused)
                    .onKeyPress(.return) { qr.copyImage(); return .handled }
                    .onKeyPress(.escape) { model.key(.escape); return .handled }
            }
            .padding(.horizontal, 22)
            .frame(height: 62)

            VStack(spacing: 8) {
                if let img = qr.image {
                    Image(decorative: img, scale: 1)
                        .interpolation(.none).resizable().scaledToFit()
                        .frame(maxWidth: 250, maxHeight: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if let m = qr.message {
                    Text(m).foregroundStyle(.secondary)
                }
                if qr.image != nil {
                    Text("\(qr.text.utf8.count) byte\(qr.text.utf8.count == 1 ? "" : "s") · error correction M").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Footer(moduleIcon: "qrcode", moduleName: "QR Code", primary: "Copy QR Image", onActions: { model.toggleActions(); qr.focusTick += 1 })
        }
        .refocusOnAppear($focused)
        .onChange(of: qr.focusTick) { _, _ in focused = true }
    }
}
