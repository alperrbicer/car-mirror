import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// All icon variants use the same vector paths as the in-app logo.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ??
    root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset/Icon.png").path)
let svg = try XMLDocument(contentsOf: root.appendingPathComponent("Design/mirror-mark.svg"))
let elements = try svg.nodes(forXPath: "/*[local-name()='svg']/*[local-name()='rect' or local-name()='path']")
    .compactMap { $0 as? XMLElement }
guard elements.filter({ $0.name == "rect" }).count == 2,
      elements.filter({ $0.name == "path" }).count == 1 else {
    fatalError("Expected the selected two-screen and car Mirivo mark")
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!

// The selected SVG uses explicit, absolute M/L/H/V/C/Z commands.
// Read the car from the source so the icon and in-app mark cannot drift.
func carPath(_ data: String) -> CGPath {
    let scanner = Scanner(string: data)
    scanner.locale = Locale(identifier: "en_US_POSIX")
    scanner.charactersToBeSkipped = .whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
    let path = CGMutablePath()
    func number() -> CGFloat {
        guard let value = scanner.scanDouble() else { fatalError("Missing SVG path coordinate") }
        return CGFloat(value)
    }
    func point() -> CGPoint { CGPoint(x: number(), y: number()) }
    while !scanner.isAtEnd {
        if scanner.scanString("M") != nil {
            path.move(to: point())
        } else if scanner.scanString("L") != nil {
            path.addLine(to: point())
        } else if scanner.scanString("H") != nil {
            path.addLine(to: CGPoint(x: number(), y: path.currentPoint.y))
        } else if scanner.scanString("V") != nil {
            path.addLine(to: CGPoint(x: path.currentPoint.x, y: number()))
        } else if scanner.scanString("C") != nil {
            let control1 = point()
            let control2 = point()
            path.addCurve(to: point(), control1: control1, control2: control2)
        } else if scanner.scanString("Z") != nil {
            path.closeSubpath()
        } else {
            fatalError("Unsupported SVG path command in the selected Mirivo mark")
        }
    }
    return path
}

func color(_ hex: UInt32) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 255) / 255,
        CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, 1])!
}

func generate(name: String, foreground: UInt32, background: UInt32, highlight: UInt32) throws {
    let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)
    let gradient = CGGradient(colorsSpace: space, colors: [color(highlight), color(background)] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 256, y: 0), end: CGPoint(x: 768, y: 1024),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.translateBy(x: 160, y: 160)
    context.scaleBy(x: 11, y: 11)
    context.setStrokeColor(color(foreground))
    context.setLineJoin(.round)
    for element in elements {
        func value(_ key: String) -> CGFloat { CGFloat(Double(element.attribute(forName: key)!.stringValue!)!) }
        let path: CGPath
        if element.name == "rect" {
            path = CGPath(roundedRect: CGRect(x: value("x"), y: value("y"), width: value("width"), height: value("height")),
                cornerWidth: value("rx"), cornerHeight: value("rx"), transform: nil)
        } else {
            path = carPath(element.attribute(forName: "d")!.stringValue!)
        }
        context.setLineWidth(value("stroke-width"))
        context.setLineCap(element.attribute(forName: "stroke-linecap")?.stringValue == "round" ? .round : .butt)
        if element.attribute(forName: "fill") != nil {
            context.setFillColor(color(background))
            context.addPath(path)
            context.drawPath(using: .fillStroke)
        } else {
            context.addPath(path)
            context.strokePath()
        }
    }
    let file = output.deletingLastPathComponent().appendingPathComponent(name)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write icon") }
    print("Created \(file.lastPathComponent): 1024x1024, opaque sRGB")
}

let stem = output.deletingPathExtension().lastPathComponent
try generate(name: output.lastPathComponent, foreground: 0x66E3C7, background: 0x090B0D, highlight: 0x17231F)
try generate(name: "\(stem)-dark.png", foreground: 0x66E3C7, background: 0x060809, highlight: 0x111B18)
try generate(name: "\(stem)-tinted.png", foreground: 0xE7E7E7, background: 0x090909, highlight: 0x1B1B1B)
