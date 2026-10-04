import SwiftUI

/// A photo thumbnail that fills whatever frame the caller gives it.
///
/// The cache is consulted by ID first, so re-renders and scrolling never
/// touch the (multi-megabyte, externally stored) image data. On a miss the
/// data is read once and decoded off the main thread while a placeholder shows.
struct PhotoThumbnail: View {
    private let id: UUID
    private let maxDimension: CGFloat
    private let loadData: () -> Data

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: UIImage?

    init(photo: Photo, maxDimension: CGFloat) {
        id = photo.id
        self.maxDimension = maxDimension
        loadData = { photo.imageData }
    }

    init(capturedPhoto: CapturedPhoto, maxDimension: CGFloat) {
        id = capturedPhoto.id
        self.maxDimension = maxDimension
        loadData = { capturedPhoto.data }
    }

    var body: some View {
        Group {
            if let image = loaded ?? ImageDownsampler.cachedThumbnail(id: id, maxDimension: maxDimension) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .task(id: id) {
            loaded = nil
            guard ImageDownsampler.cachedThumbnail(id: id, maxDimension: maxDimension) == nil else { return }
            loaded = await ImageDownsampler.thumbnail(
                id: id, data: loadData(), maxDimension: maxDimension, scale: displayScale
            )
        }
    }
}
