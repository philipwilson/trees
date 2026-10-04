import UIKit
import ImageIO

enum ImageDownsampler {
    /// Thumbnail cache keyed by photo ID + size, so a lookup never needs the
    /// image data itself. Capped by decoded size; fullscreen images are not
    /// cached here at all.
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    private static func cacheKey(id: UUID, maxDimension: CGFloat) -> NSString {
        "\(id.uuidString)-\(Int(maxDimension))" as NSString
    }

    /// Returns a previously generated thumbnail, if still cached.
    static func cachedThumbnail(id: UUID, maxDimension: CGFloat) -> UIImage? {
        cache.object(forKey: cacheKey(id: id, maxDimension: maxDimension))
    }

    /// Decodes a thumbnail off the calling actor and caches it under `id`.
    static func thumbnail(id: UUID, data: Data, maxDimension: CGFloat, scale: CGFloat) async -> UIImage? {
        let key = cacheKey(id: id, maxDimension: maxDimension)
        if let cached = cache.object(forKey: key) {
            return cached
        }
        return await Task.detached(priority: .userInitiated) {
            guard let image = downsample(data: data, maxDimension: maxDimension, scale: scale) else { return nil }
            let cost = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
            cache.setObject(image, forKey: key, cost: cost)
            return image
        }.value
    }

    /// Creates a downsampled UIImage from data without loading full resolution
    /// into memory. Not cached. `maxDimension` is in points; `scale` is the
    /// display scale.
    static func downsample(data: Data, maxDimension: CGFloat, scale: CGFloat) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary

        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return nil
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension * scale
        ] as CFDictionary

        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }

        return UIImage(cgImage: downsampledImage)
    }
}
