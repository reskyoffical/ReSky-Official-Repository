import SwiftUI
import ImageIO
import UIKit

enum ImageInspector {
    /// Number of frames in GIF / APNG / WebP / HEICS data.
    static func frameCount(_ data: Data) -> Int {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return 0 }
        return CGImageSourceGetCount(src)
    }

    static func isAnimated(_ data: Data) -> Bool { frameCount(data) > 1 }

    /// (extension, mime) for formats the profile bucket accepts, else nil.
    static func profileFormat(_ data: Data) -> (ext: String, mime: String)? {
        let b = [UInt8](data.prefix(16))
        guard b.count >= 12 else { return nil }
        if b[0] == 0xFF && b[1] == 0xD8 { return ("jpg", "image/jpeg") }
        if b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 { return ("png", "image/png") }
        if b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 { return ("gif", "image/gif") }
        if b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45 { return ("webp", "image/webp") }
        return nil
    }

    /// First frame as PNG (used as the locked/static fallback for animated art).
    static func firstFramePNG(_ data: Data, maxPixel: Int = 1024) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).pngData()
    }

    /// Downscaled JPEG for photos picked in HEIC or other formats.
    static func jpeg(_ data: Data, maxPixel: Int = 2048, quality: CGFloat = 0.85) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: quality)
    }

    /// Builds an animated UIImage (or a still) from image data.
    static func uiImage(_ data: Data, animate: Bool) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
        let count = CGImageSourceGetCount(src)
        guard animate, count > 1 else { return UIImage(data: data) }
        var frames: [UIImage] = []
        var duration = 0.0
        let maxFrames = min(count, 300)
        for i in 0..<maxFrames {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            duration += frameDelay(src, i)
        }
        return UIImage.animatedImage(with: frames, duration: max(duration, 0.1))
    }

    private static func frameDelay(_ src: CGImageSource, _ i: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any] else { return 0.1 }
        let dicts: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
        ]
        for (dictKey, unclamped, clamped) in dicts {
            if let d = props[dictKey] as? [CFString: Any] {
                let v = (d[unclamped] as? Double) ?? (d[clamped] as? Double) ?? 0.1
                return v < 0.02 ? 0.1 : v
            }
        }
        return 0.1
    }
}

/// UIImageView wrapper that plays animated images inside SwiftUI.
struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage
    var contentMode: UIView.ContentMode = .scaleAspectFill

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.clipsToBounds = true
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {
        v.contentMode = contentMode
        if v.image !== image {
            v.image = image
            if image.images != nil { v.startAnimating() }
        }
    }
}
