import XCTest
import UIKit
@testable import Trees

final class PhotoEncoderTests: XCTestCase {
    /// An image of exactly the given pixel size, with detail so it doesn't
    /// compress to nothing.
    private func makeImage(width: Int, height: Int, orientation: UIImage.Orientation = .up) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: width, height: height)
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.brown.setFill()
            for index in 0..<40 {
                context.fill(CGRect(x: index * width / 40, y: index * height / 40, width: width / 80, height: height / 3))
            }
        }
        guard orientation != .up, let cgImage = rendered.cgImage else { return rendered }
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }

    private func pixelSize(of data: Data?) throws -> CGSize {
        let image = try XCTUnwrap(UIImage(data: try XCTUnwrap(data)))
        XCTAssertEqual(image.imageOrientation, .up)
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    func testTwelveMegapixelPhotoIsCappedAt2560() throws {
        let original = makeImage(width: 4032, height: 3024)
        let capped = PhotoEncoder.jpegData(from: original, keepFullSize: false)

        XCTAssertEqual(try pixelSize(of: capped), CGSize(width: 2560, height: 1920))
    }

    func testCappedPhotoIsSmallerThanFullSize() throws {
        let original = makeImage(width: 4032, height: 3024)
        let capped = try XCTUnwrap(PhotoEncoder.jpegData(from: original, keepFullSize: false))
        let full = try XCTUnwrap(PhotoEncoder.jpegData(from: original, keepFullSize: true))

        XCTAssertLessThan(capped.count, full.count)
    }

    func testKeepFullSizeLeavesTheResolutionAlone() throws {
        let original = makeImage(width: 4032, height: 3024)
        let kept = PhotoEncoder.jpegData(from: original, keepFullSize: true)

        XCTAssertEqual(try pixelSize(of: kept), CGSize(width: 4032, height: 3024))
    }

    func testPhotosAlreadyWithinTheCapAreNotResized() throws {
        let small = PhotoEncoder.jpegData(from: makeImage(width: 1600, height: 1200), keepFullSize: false)
        XCTAssertEqual(try pixelSize(of: small), CGSize(width: 1600, height: 1200))

        let exact = PhotoEncoder.jpegData(from: makeImage(width: 2560, height: 1440), keepFullSize: false)
        XCTAssertEqual(try pixelSize(of: exact), CGSize(width: 2560, height: 1440))
    }

    /// A portrait photo from the camera is stored sideways with a rotation
    /// flag. The capped result must come out upright with the long edge
    /// vertical, not squashed or turned.
    func testPortraitPhotoKeepsItsShapeAndComesOutUpright() throws {
        let portrait = makeImage(width: 4032, height: 3024, orientation: .right)
        XCTAssertEqual(portrait.size, CGSize(width: 3024, height: 4032))

        let capped = PhotoEncoder.jpegData(from: portrait, keepFullSize: false)
        XCTAssertEqual(try pixelSize(of: capped), CGSize(width: 1920, height: 2560))
    }

    func testImageScaleIsAccountedFor() throws {
        // 1500 × 1000 points at 3× is 4500 × 3000 pixels
        let cgImage = try XCTUnwrap(makeImage(width: 4500, height: 3000).cgImage)
        let retina = UIImage(cgImage: cgImage, scale: 3, orientation: .up)

        let capped = PhotoEncoder.jpegData(from: retina, keepFullSize: false)
        XCTAssertEqual(try pixelSize(of: capped), CGSize(width: 2560, height: 1707))
    }

    func testSettingDefaultsToCapped() {
        let defaults = UserDefaults(suiteName: "PhotoEncoderTests-\(UUID().uuidString)")!
        XCTAssertFalse(defaults.bool(forKey: PhotoEncoder.keepFullSizeKey))
    }
}
