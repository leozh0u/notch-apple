import AppKit
import ImageIO

@main
struct ArtworkChecks {
    static func image(width: Int, height: Int, color: CGColor) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func png(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func average(_ image: NSImage) async -> NSColor? {
        await withCheckedContinuation { continuation in
            image.averageColor { color in
                precondition(Thread.isMainThread, "Average-color completion must stay on the main thread")
                continuation.resume(returning: color?.usingColorSpace(.deviceRGB))
            }
        }
    }

    static func main() async {
        let large = image(width: 4096, height: 2048,
                          color: CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        let data = png(large)
        let thumbnail = NSImage.downsampledArtwork(data: data)!
        let pixels = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        precondition(pixels.width == 384 && pixels.height == 192,
                     "Large artwork must be decoded to the bounded size and retain its aspect ratio")
        let small = NSImage.downsampledArtwork(data: data, maxPixelSize: 64)!
        let smallPixels = small.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        precondition(smallPixels.width == 64 && smallPixels.height == 32)
        precondition(NSImage.downsampledArtwork(data: Data()) == nil)
        precondition(NSImage.downsampledArtwork(data: Data("invalid image".utf8)) == nil)
        precondition(NSImage.downsampledArtwork(data: data, maxPixelSize: 0) == nil)

        let red = await average(NSImage(cgImage: large, size: .zero))!
        precondition(red.redComponent > 0.95 && red.greenComponent < 0.2 && red.blueComponent < 0.05,
                     "Sampling must retain artwork color channels: \(red)")
        let dark = image(width: 128, height: 64, color: CGColor(gray: 0, alpha: 1))
        let gray = await average(NSImage(cgImage: dark, size: .zero))!
        precondition(abs(gray.redComponent - 0.5) < 0.02 &&
                     abs(gray.greenComponent - 0.5) < 0.02 &&
                     abs(gray.blueComponent - 0.5) < 0.02,
                     "Near-black artwork must retain the minimum brightness")
        let dimRed = image(width: 8, height: 8,
                           color: CGColor(red: 0.2, green: 0, blue: 0, alpha: 1))
        let lifted = await average(NSImage(cgImage: dimRed, size: .zero))!
        precondition(lifted.brightnessComponent >= 0.49 && lifted.redComponent > lifted.greenComponent,
                     "Dim artwork must retain hue while its brightness is lifted")
        print("Artwork checks passed: bounded thumbnails, invalid input, main-thread colors, dark-art brightness.")
    }
}
