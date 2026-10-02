import CoreImage
import CoreText

/// Caption pixels are composed into the transmitted video; no transcript is saved.
final class CaptionRenderer {
    private var previous = ""
    private var cached: CIImage?
    func clear() { previous = ""; cached = nil }
    func image(text: String, width: Int, height: Int) -> CIImage? {
        guard !text.isEmpty else { clear(); return nil }
        if text == previous { return cached }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let scale = CGFloat(width) / 960
        let rect = CGRect(x: 40 * scale, y: 22 * scale, width: CGFloat(width) - 80 * scale, height: 94 * scale)
        context.setFillColor(CGColor(gray: 0, alpha: 0.82))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 14 * scale, cornerHeight: 14 * scale, transform: nil))
        context.fillPath()
        let string = NSAttributedString(string: String(text.suffix(150)), attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 28 * scale, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
        ])
        let setter = CTFramesetterCreateWithAttributedString(string)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: string.length),
            CGPath(rect: rect.insetBy(dx: 18 * scale, dy: 10 * scale), transform: nil), nil)
        CTFrameDraw(frame, context)
        guard let cgImage = context.makeImage() else { return nil }
        previous = text
        cached = CIImage(cgImage: cgImage)
        return cached
    }
}
