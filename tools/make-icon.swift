// Generates Resources/AppIcon.icns: the ⌘ glyph on a dark rounded square.
// Usage: swift tools/make-icon.swift <output.icns>
import AppKit

func render(_ px: Int) -> Data {
    let size = CGFloat(px)
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let inset = size * 0.098                       // macOS icon grid: ~824/1024 body
    let body = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = body.width * 0.2237
    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = size * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.01)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(white: 0.20, alpha: 1), NSColor(white: 0.06, alpha: 1)])!.draw(in: path, angle: -90)
    NSColor.white.withAlphaComponent(0.10).setStroke()
    path.lineWidth = max(1, size * 0.003)
    path.stroke()

    // white ⌘ glyph
    let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .semibold)
    if let sym = NSImage(systemSymbolName: "command", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: sym.size)
        tinted.lockFocus()
        sym.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: sym.size).fill(using: .sourceIn)
        tinted.unlockFocus()
        let r = NSRect(x: (size - sym.size.width) / 2, y: (size - sym.size.height) / 2, width: sym.size.width, height: sym.size.height)
        tinted.draw(in: r)
    }
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else { print("usage: make-icon <output.icns>"); exit(1) }
let out = CommandLine.arguments[1]
let set = NSTemporaryDirectory() + "NexusIcon.iconset"
try? FileManager.default.removeItem(atPath: set)
try FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base).png"))
    try render(base * 2).write(to: URL(fileURLWithPath: "\(set)/icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set, "-o", out]
try p.run(); p.waitUntilExit()
exit(p.terminationStatus)
