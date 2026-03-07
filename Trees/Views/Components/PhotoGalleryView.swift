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
                    if let uiImage = ImageDownsampler.downsample(data: photo.imageData, maxDimension: 120) {
                        VStack(spacing: 4) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(minWidth: 100, minHeight: 100)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    if let uiImage = UIImage(data: photo.imageData) {
                        ZoomableImageView(image: uiImage)
                            .tag(photo.id)
                    }
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
                            preview: SharePreview("Photo", image: Image(uiImage: UIImage(data: photo.imageData) ?? UIImage()))
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
                if let uiImage = ImageDownsampler.downsample(data: photo.data, maxDimension: 80) {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipped()
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
