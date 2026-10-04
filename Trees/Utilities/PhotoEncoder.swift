import UIKit

/// Turns a picked or captured image into the JPEG data stored on a Photo.
///
/// By default the long edge is capped at 2560 pixels. That is about what the
/// fullscreen viewer can show on the largest screens, and it roughly halves
/// what each photo costs in device and iCloud storage compared with a
/// 12-megapixel original. Photos restored from a backup are not re-encoded.
enum PhotoEncoder {
    static let maximumLongEdge: CGFloat = 2560
    static let jpegQuality: CGFloat = 0.8

    /// UserDefaults key for the "Keep Full-Size Photos" setting (off by default).
    static let keepFullSizeKey = "keepFullSizePhotos"

    /// Safe to call off the main thread.
    static func jpegData(from image: UIImage, keepFullSize: Bool) -> Data? {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longEdge = max(pixelSize.width, pixelSize.height)
        guard !keepFullSize, longEdge > maximumLongEdge else {
            return image.jpegData(compressionQuality: jpegQuality)
        }

        let ratio = maximumLongEdge / longEdge
        let targetSize = CGSize(
            width: (pixelSize.width * ratio).rounded(),
            height: (pixelSize.height * ratio).rounded()
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        // Drawing a UIImage applies its orientation, so the result is upright
        return UIGraphicsImageRenderer(size: targetSize, format: format)
            .jpegData(withCompressionQuality: jpegQuality) { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
    }
}
