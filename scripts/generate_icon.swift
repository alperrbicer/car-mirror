import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let space = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let background = CGGradient(colorsSpace: space,
    colors: [CGColor(red: 0.03, green: 0.08, blue: 0.13, alpha: 1),
             CGColor(red: 0.06, green: 0.22, blue: 0.24, alpha: 1)] as CFArray,
    locations: [0, 1])!
context.drawLinearGradient(background, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1024, y: 1024), options: [])
let mint = CGColor(red: 0.35, green: 0.91, blue: 0.77, alpha: 1)
context.setStrokeColor(mint)
context.setLineWidth(32)
context.addPath(CGPath(roundedRect: CGRect(x: 185, y: 275, width: 650, height: 460), cornerWidth: 65, cornerHeight: 65, transform: nil))
context.strokePath()
context.setFillColor(CGColor(red: 0.03, green: 0.08, blue: 0.13, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: 360, y: 190, width: 245, height: 460), cornerWidth: 45, cornerHeight: 45, transform: nil))
context.drawPath(using: .fillStroke)
context.setFillColor(mint)
context.fill(CGRect(x: 439, y: 217, width: 90, height: 12))
context.setLineCap(.round)
context.move(to: CGPoint(x: 441, y: 499))
context.addLine(to: CGPoint(x: 484, y: 541))
context.addLine(to: CGPoint(x: 527, y: 499))
context.strokePath()
context.move(to: CGPoint(x: 484, y: 533))
context.addLine(to: CGPoint(x: 484, y: 396))
context.strokePath()
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write icon") }
