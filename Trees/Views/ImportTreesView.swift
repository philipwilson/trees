import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportTreesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingFilePicker = false
    @State private var importResult: ImportResult?
    @State private var showingResult = false
    @State private var photoImportMode: PhotoImportMode = .withDelay

    enum PhotoImportMode: String, CaseIterable {
        case none = "No Photos"
        case withDelay = "With Photos (Delayed)"
        case immediate = "With Photos (Immediate)"

        var description: String {
            switch self {
            case .none: return "Import tree data only, no photos"
            case .withDelay: return "Import photos one at a time for reliable sync"
            case .immediate: return "Import all photos at once (may not sync)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Select JSON File", systemImage: "doc.badge.plus")
                    }

                    Picker("Photo Import", selection: $photoImportMode) {
                        ForEach(PhotoImportMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                } header: {
                    Text("Import")
                } footer: {
                    Text(photoImportMode.description)
                }
            }
            .navigationTitle("Import Trees")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .alert("Import Complete", isPresented: $showingResult) {
                Button("OK") {
                    if importResult?.success == true {
                        dismiss()
                    }
                }
            } message: {
                if let result = importResult {
                    Text(result.message)
                }
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importFromURL(url)
        case .failure(let error):
            importResult = ImportResult(success: false, message: "Failed to access file: \(error.localizedDescription)")
            showingResult = true
        }
    }

    private func importFromURL(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importResult = ImportResult(success: false, message: "Cannot access the selected file.")
            showingResult = true
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            let trees = try JSONDecoder().decode([ImportedTreeData].self, from: data)

            var importedCount = 0
            var photoCount = 0
            var treesWithPhotos: [(Tree, [(Data, Date?)])] = []

            for importedTree in trees {
                let tree = Tree(
                    latitude: importedTree.latitude,
                    longitude: importedTree.longitude,
                    horizontalAccuracy: importedTree.horizontalAccuracy,
                    altitude: importedTree.altitude,
                    species: importedTree.species,
                    variety: importedTree.variety,
                    rootstock: importedTree.rootstock
                )

                modelContext.insert(tree)

                // Add notes as a Note entity if provided
                if !importedTree.notes.isEmpty {
                    _ = tree.addNote(text: importedTree.notes)
                }

                // Collect photos for delayed import
                if photoImportMode != .none, let photosBase64 = importedTree.photos {
                    var photos: [(Data, Date?)] = []
                    for (index, photoString) in photosBase64.enumerated() {
                        if let photoData = Data(base64Encoded: photoString) {
                            let captureDate = importedTree.photoDates?.indices.contains(index) == true
                                ? importedTree.photoDates?[index]
                                : nil
                            if photoImportMode == .immediate {
                                tree.addPhoto(photoData, capturedAt: captureDate)
                            } else {
                                photos.append((photoData, captureDate))
                            }
                            photoCount += 1
                        }
                    }
                    if !photos.isEmpty {
                        treesWithPhotos.append((tree, photos))
                    }
                }

                importedCount += 1
            }

            // Save trees first (without photos if delayed mode)
            try modelContext.save()
            print("🌐 Import: Saved \(importedCount) trees")

            // For delayed mode, add photos one tree at a time with delays
            if photoImportMode == .withDelay && !treesWithPhotos.isEmpty {
                importResult = ImportResult(
                    success: true,
                    message: "Imported \(importedCount) trees. Adding \(photoCount) photos in background..."
                )
                showingResult = true

                // Add photos with delays in background
                Task {
                    for (index, (tree, photos)) in treesWithPhotos.enumerated() {
                        // Wait before adding each tree's photos
                        try? await Task.sleep(for: .seconds(2))

                        await MainActor.run {
                            for (photoData, captureDate) in photos {
                                tree.addPhoto(photoData, capturedAt: captureDate)
                            }
                            try? modelContext.save()
                            print("🌐 Import: Added \(photos.count) photos to tree \(index + 1)/\(treesWithPhotos.count)")
                        }
                    }
                    print("🌐 Import: Finished adding all photos")
                }
            } else {
                importResult = ImportResult(
                    success: true,
                    message: "Successfully imported \(importedCount) tree\(importedCount == 1 ? "" : "s")\(photoCount > 0 ? " with \(photoCount) photos" : "")."
                )
                showingResult = true
            }

        } catch {
            importResult = ImportResult(success: false, message: "Failed to parse file: \(error.localizedDescription)")
            showingResult = true
        }
    }
}

// Extended import structure that supports photos
private struct ImportedTreeData: Codable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let altitude: Double?
    let species: String
    let variety: String?
    let rootstock: String?
    let notes: String
    let photos: [String]?  // Base64 encoded photo data
    let photoDates: [Date]?  // Capture dates from old format

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, horizontalAccuracy, altitude
        case species, variety, rootstock, notes, photos, photoDates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        horizontalAccuracy = try container.decode(Double.self, forKey: .horizontalAccuracy)
        altitude = try container.decodeIfPresent(Double.self, forKey: .altitude)
        species = try container.decode(String.self, forKey: .species)
        variety = try container.decodeIfPresent(String.self, forKey: .variety)
        rootstock = try container.decodeIfPresent(String.self, forKey: .rootstock)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        photos = try container.decodeIfPresent([String].self, forKey: .photos)
        photoDates = try container.decodeIfPresent([Date].self, forKey: .photoDates)
    }
}

#Preview {
    ImportTreesView()
        .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
