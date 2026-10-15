// Original, synthetic artwork for local UI tests only. Nothing is bundled in the app.
import AppKit

let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/library-artwork-fixtures")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let fixtures: [(String, String, NSColor, Bool)] = [
    ("voyage", "MAVİ\nYOLCULUK", .systemTeal, true),
    ("light", "SON\nIŞIK", .systemOrange, true),
    ("beyond", "YOLUN\nÖTESİ", .systemIndigo, true),
    ("nova", "NOVA", .systemTeal, false),
    ("arena", "ARENA", .systemOrange, false),
    ("news", "HABER", .systemBlue, false)
]
for (name, title, tint, poster) in fixtures {
    let width = 360, height = poster ? 540 : 360
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let rect = NSRect(x: 0, y: 0, width: width, height: height)
    NSGradient(starting: NSColor(calibratedWhite: 0.035, alpha: 1), ending: tint.blended(withFraction: 0.4, of: .black)!)!.draw(in: rect, angle: 65)
    if poster {
        NSColor(calibratedRed: 1, green: 0.83, blue: 0.57, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 190, y: 330, width: 106, height: 106)).fill()
        for layer in 0..<5 {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: 0)); path.line(to: NSPoint(x: 0, y: 230 - layer * 27))
            path.curve(to: NSPoint(x: 360, y: 195 - layer * 24), controlPoint1: NSPoint(x: 120, y: 315 - layer * 30), controlPoint2: NSPoint(x: 240, y: 120 - layer * 25))
            path.line(to: NSPoint(x: 360, y: 0)); path.close()
            tint.blended(withFraction: CGFloat(layer) * 0.14 + 0.15, of: .black)!.setFill(); path.fill()
        }
    } else {
        tint.withAlphaComponent(0.22).setFill()
        NSBezierPath(ovalIn: NSRect(x: 45, y: 45, width: 270, height: 270)).fill()
    }
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: poster ? 42 : 44, weight: .bold), .foregroundColor: NSColor.white, .paragraphStyle: paragraph, .kern: 3]
    (title as NSString).draw(in: NSRect(x: 20, y: poster ? 60 : 143, width: 320, height: 110), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
}
