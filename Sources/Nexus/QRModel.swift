import AppKit
import NexusCore

/// QR code for some text (prefilled from the clipboard), regenerated as you type.
final class QRModel: ObservableObject {
    @Published var text = "" { didSet { regenerate() } }
    @Published private(set) var image: CGImage?
    @Published private(set) var message: String?
    @Published var focusTick = 0
    var dismiss: () -> Void = {}

    func open() {
        let clip = (NSPasteboard.general.string(forType: .string) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        text = clip.utf8.count <= QRCode.maxBytes ? clip : ""
        focusTick += 1
    }

    private func regenerate() {
        if text.isEmpty { image = nil; message = "Type or paste text or a link."; return }
        if text.utf8.count > QRCode.maxBytes { image = nil; message = "Too long for a QR code (\(text.utf8.count) of \(QRCode.maxBytes) bytes)."; return }
        image = QRCode.cgImage(for: text)
        message = image == nil ? "Couldn't generate a code for this text." : nil
    }

    private var png: Data? { image.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) } }

    func copyImage() {
        guard let image, let data = png else { return }
        dismiss()
        ClipboardService.shared.write(paste: false) { pb in
            pb.writeObjects([NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))])
            pb.setData(data, forType: .png)
        }
    }

    func save() {
        guard let data = png else { return }
        dismiss()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "qrcode.png"
        panel.allowedContentTypes = [.png]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
    }

    func copyText() {
        let t = text
        dismiss()
        ClipboardService.shared.write(paste: false) { $0.setString(t, forType: .string) }
    }

    var actions: [ActionItem] {
        guard image != nil else { return [] }
        return [ActionItem(title: "Copy QR Image", symbol: "doc.on.doc", run: { [self] in copyImage() }),
                ActionItem(title: "Save as PNG…", symbol: "square.and.arrow.down", run: { [self] in save() }),
                ActionItem(title: "Copy Text", symbol: "textformat", run: { [self] in copyText() })]
    }
}
