import Foundation
import CoreImage
import CoreGraphics

/// QR codes via Core Image: black modules on white, scaled with hard edges. The generator already includes a
/// 1-module margin, so the default extra `quietZone` of 3 gives the 4 modules the QR spec asks for.
public enum QRCode {
    /// Binary capacity of a version-40 code at error-correction level M.
    public static let maxBytes = 2331

    public static func cgImage(for text: String, scale: Int = 10, quietZone: Int = 3) -> CGImage? {
        guard !text.isEmpty, text.utf8.count <= maxBytes, let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = filter.outputImage, let modules = CIContext().createCGImage(out, from: out.extent) else { return nil }
        let side = (modules.width + 2 * quietZone) * scale
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.interpolationQuality = .none
        ctx.draw(modules, in: CGRect(x: quietZone * scale, y: quietZone * scale, width: modules.width * scale, height: modules.height * scale))
        return ctx.makeImage()
    }
}
