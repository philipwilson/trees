import UIKit
import ImageIO

enum ImageDownsampler {
    private static let cache = NSCache<NSString, UIImage>()

    /// Creates a downsampled UIImage from data without loading full resolution into memory.
    /// Results are cached by data fingerprint + dimension to avoid redundant work on re-render.
    static func downsample(data: Data, maxDimension: CGFloat) -> UIImage? {
        let cacheKey = "\(data.count)-\(data.prefix(16).hashValue)-\(Int(maxDimension))" as NSString

        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary

        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return nil
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension * UIScreen.main.scale
        ] as CFDictionary

        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }

        let result = UIImage(cgImage: downsampledImage)
        cache.setObject(result, forKey: cacheKey)
        return result
    }
}
