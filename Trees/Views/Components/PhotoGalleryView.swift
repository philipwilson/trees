import SwiftUI

struct CapturedPhoto: Identifiable {
    let id = UUID()
    let data: Data
    let captureDate: Date?
}

@Observable
class PhotoViewerState {
    var isPresented = false
}

struct PhotoGalleryView: View {
    static let thumbnailDimension: CGFloat = 120

    let photos: [Photo]
    @State private var selectedPhoto: Photo?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 5 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        if photos.isEmpty {
            ContentUnavailableView(
                "No Photos",
                systemImage: "photo.on.rectangle.angled",
                description: Text("Photos added to this tree will appear here")
            )
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(photos) { photo in
                    VStack(spacing: 4) {
                        PhotoThumbnail(photo: photo, maxDimension: Self.thumbnailDimension)
                            .frame(minWidth: 100, minHeight: 100)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedPhoto = photo
                            }

                        if let captureDate = photo.captureDate {
                            Text(captureDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .fullScreenCover(item: $selectedPhoto) { photo in
                PhotoDetailView(photos: photos, initialPhoto: photo)
            }
        }
    }
}

struct PhotoDetailView: View {
    let photos: [Photo]
    @State private var currentPhotoID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(PhotoViewerState.self) private var photoViewerState

    init(photos: [Photo], initialPhoto: Photo) {
        self.photos = photos
        _currentPhotoID = State(initialValue: initialPhoto.id)
    }

    private var currentIndex: Int {
        photos.firstIndex(where: { $0.id == currentPhotoID }) ?? 0
    }

    private var currentDateString: String? {
        guard let photo = photos.first(where: { $0.id == currentPhotoID }),
              let date = photo.captureDate else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $currentPhotoID) {
                ForEach(photos) { photo in
                    PhotoPageView(photo: photo)
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let photo = photos.first(where: { $0.id == currentPhotoID }) {
                        ShareLink(
                            item: PhotoFile(data: photo.imageData),
                            preview: SharePreview(
                                "Photo",
                                image: Image(uiImage: ImageDownsampler.cachedThumbnail(
                                    id: photo.id, maxDimension: PhotoGalleryView.thumbnailDimension
                                ) ?? UIImage())
                            )
                        )
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("\(currentIndex + 1) of \(photos.count)")
                        if let dateString = currentDateString {
                            Text(dateString)
                                .font(.caption)
                                .opacity(0.7)
                        }
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            photoViewerState.isPresented = true
            #if targetEnvironment(macCatalyst)
            setMacCatalystToolbarVisible(false)
            #endif
        }
        .onDisappear {
            photoViewerState.isPresented = false
            #if targetEnvironment(macCatalyst)
            setMacCatalystToolbarVisible(true)
            #endif
        }
    }

    #if targetEnvironment(macCatalyst)
    private func setMacCatalystToolbarVisible(_ visible: Bool) {
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                windowScene.titlebar?.toolbar?.isVisible = visible
            }
        }
    }
    #endif
}

/// A single page of the fullscreen viewer. Loads its image lazily and
/// downsampled to screen size, and releases it when swiped off-screen,
/// so peak memory stays bounded regardless of photo count. Deliberately
/// bypasses the thumbnail cache, which would keep these large images alive.
private struct PhotoPageView: View {
    let photo: Photo
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ZoomableImageView(image: image)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: photo.id) {
            guard image == nil else { return }
            let screen = UIScreen.main.bounds.size
            let maxDimension = max(screen.width, screen.height)
            let data = photo.imageData
            let scale = displayScale
            image = await Task.detached(priority: .userInitiated) {
                ImageDownsampler.downsample(data: data, maxDimension: maxDimension, scale: scale)
            }.value
        }
        .onDisappear {
            image = nil
        }
    }
}

/// Editable gallery for use during tree capture/editing
/// Works with CapturedPhoto since Photo entities aren't created yet
struct EditablePhotoGalleryView: View {
    @Binding var capturedPhotos: [CapturedPhoto]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 6 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(capturedPhotos) { photo in
                VStack(spacing: 4) {
                    ZStack(alignment: .topTrailing) {
                        PhotoThumbnail(capturedPhoto: photo, maxDimension: 80)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button {
                            capturedPhotos.removeAll { $0.id == photo.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, .red)
                        }
                        .offset(x: 6, y: -6)
                    }

                    if let date = photo.captureDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct PhotoFile: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { photo in
            photo.data
        }
    }
}

#Preview {
    PhotoGalleryView(photos: [])
}
