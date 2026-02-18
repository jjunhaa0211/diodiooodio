import AppKit
import CoreGraphics
import Foundation

let outputPath = "/Users/junha/develop/jjunhaa/odioodiodio/diodiooodio/Assets.xcassets/diodiooodio.appiconset/icon_512x512@2x.png"
let size = CGSize(width: 1024, height: 1024)

let image = NSImage(size: size)
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("Unable to create graphics context")
}

ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

let canvas = CGRect(origin: .zero, size: size)
let roundedRect = CGPath(roundedRect: canvas.insetBy(dx: 96, dy: 96), cornerWidth: 212, cornerHeight: 212, transform: nil)
ctx.addPath(roundedRect)
ctx.clip()

let bgColors = [
    NSColor(calibratedRed: 0.545, green: 0.361, blue: 0.965, alpha: 1.0).cgColor,
    NSColor(calibratedRed: 0.486, green: 0.227, blue: 0.929, alpha: 1.0).cgColor,
    NSColor(calibratedRed: 0.357, green: 0.129, blue: 0.714, alpha: 1.0).cgColor
] as CFArray
let locations: [CGFloat] = [0.0, 0.52, 1.0]
let colorSpace = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: locations)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 140, y: 904),
    end: CGPoint(x: 884, y: 120),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

let glowColors = [
    NSColor(calibratedRed: 0.768, green: 0.710, blue: 0.992, alpha: 0.35).cgColor,
    NSColor(calibratedRed: 0.768, green: 0.710, blue: 0.992, alpha: 0.0).cgColor
] as CFArray
let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0])!
ctx.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: 354, y: 738),
    startRadius: 0,
    endCenter: CGPoint(x: 354, y: 738),
    endRadius: 540,
    options: [.drawsAfterEndLocation]
)

let heart = CGMutablePath()
heart.move(to: CGPoint(x: 512, y: 254))
heart.addCurve(to: CGPoint(x: 280, y: 592), control1: CGPoint(x: 494.2, y: 269.8), control2: CGPoint(x: 280, y: 413.1))
heart.addCurve(to: CGPoint(x: 432, y: 744), control1: CGPoint(x: 280, y: 679.2), control2: CGPoint(x: 346.5, y: 744))
heart.addCurve(to: CGPoint(x: 536, y: 692.6), control1: CGPoint(x: 478.8, y: 744), control2: CGPoint(x: 514.3, y: 725.2))
heart.addCurve(to: CGPoint(x: 640, y: 744), control1: CGPoint(x: 557.7, y: 725.2), control2: CGPoint(x: 593.2, y: 744))
heart.addCurve(to: CGPoint(x: 792, y: 592), control1: CGPoint(x: 725.5, y: 744), control2: CGPoint(x: 792, y: 679.2))
heart.addCurve(to: CGPoint(x: 560, y: 254), control1: CGPoint(x: 792, y: 413.1), control2: CGPoint(x: 577.8, y: 269.8))
heart.addCurve(to: CGPoint(x: 512, y: 254), control1: CGPoint(x: 545.5, y: 241.0), control2: CGPoint(x: 526.5, y: 241.0))
heart.closeSubpath()

ctx.setFillColor(NSColor.white.cgColor)
ctx.addPath(heart)
ctx.fillPath()

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Unable to encode PNG")
}

try pngData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
print("Wrote \(outputPath)")
