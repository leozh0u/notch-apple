// Original Notch Apple vector icon, 15 October 2026. GPL-3.0.
import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("boringNotch/Assets.xcassets")
func render(size: Int, to url: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius).fill()
    }
    rect(64, 64, 896, 896, 200, NSColor(calibratedWhite: 0.055, alpha: 1))
    guard let apple = NSImage(contentsOf: root.appendingPathComponent("design/enchanted-golden-apple.png")) else {
        fatalError("Missing enchanted golden apple artwork")
    }
    NSGraphicsContext.current?.imageInterpolation = .none
    apple.draw(in: NSRect(x: 104, y: 104, width: 816, height: 816), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}
let icon = assets.appendingPathComponent("NotchAppleIcon.appiconset")
let mark = assets.appendingPathComponent("NotchAppleMark.imageset")
try FileManager.default.createDirectory(at: icon, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: mark, withIntermediateDirectories: true)
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon-\(size)@\(scale)x.png"
        try render(size: size * scale, to: icon.appendingPathComponent(filename))
        images.append(["filename": filename, "idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)"])
    }
}
let info: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]).write(to: icon.appendingPathComponent("Contents.json"))
try render(size: 512, to: mark.appendingPathComponent("mark.png"))
try Data("{\"images\":[{\"filename\":\"mark.png\",\"idiom\":\"universal\"}],\"info\":{\"author\":\"xcode\",\"version\":1}}".utf8).write(to: mark.appendingPathComponent("Contents.json"))
