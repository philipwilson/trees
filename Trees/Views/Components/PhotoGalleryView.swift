import SwiftUI

struct PhotoGalleryView: View {
    let photos: [Data]
    var photoDates: [Date]? = nil
    @State private var selectedPhotoIndex: Int?

    private var dates: [Date] { photoDates ?? [] }

    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 8)
    ]

    var body: some View {
        if photos.isEmpty {
            ContentUnavailableView(
                "No Photos",
                systemImage: "photo.on.rectangle.angled",
                description: Text("Photos added to this tree will appear here")
            )
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(photos.indices, id: \.self) { index in
                    if let uiImage = UIImage(data: photos[index]) {
                        VStack(spacing: 4) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(minWidth: 100, minHeight: 100)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture {
                                    selectedPhotoIndex = index
                                }

                            if index < dates.count {
                                Text(dates[index].formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .fullScreenCover(item: $selectedPhotoIndex) { index in
                PhotoDetailView(photos: photos, photoDates: dates, initialIndex: index)
            }
        }
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

struct PhotoDetailView: View {
    let photos: [Data]
    var photoDates: [Date] = []
    let initialIndex: Int
    @State private var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(photos: [Data], photoDates: [Date] = [], initialIndex: Int) {
        self.photos = photos
        self.photoDates = photoDates
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }

    private var currentDateString: String? {
        guard currentIndex < photoDates.count else { return nil }
        return photoDates[currentIndex].formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $currentIndex) {
                ForEach(photos.indices, id: \.self) { index in
                    if let uiImage = UIImage(data: photos[index]) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .tag(index)
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
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("\(currentIndex + 1) of \(photos.count)")
                            .foregroundStyle(.white)
                        if let dateString = currentDateString {
                            Text(dateString)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct EditablePhotoGalleryView: View {
    @Binding var photos: [Data]
    @Binding var photoDates: [Date]?

    private var dates: [Date] { photoDates ?? [] }

    private let columns = [
        GridItem(.adaptive(minimum: 80), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(photos.indices, id: \.self) { index in
                if let uiImage = UIImage(data: photos[index]) {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Button {
                                photos.remove(at: index)
                                if index < dates.count {
                                    photoDates?.remove(at: index)
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white, .red)
                            }
                            .offset(x: 6, y: -6)
                        }

                        if index < dates.count {
                            Text(dates[index].formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    PhotoGalleryView(photos: [])
}
