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

            // Try new format first (object with collections and trees)
            if let importedData = try? JSONDecoder().decode(ImportedData.self, from: data) {
                importNewFormat(importedData)
            } else {
                // Fall back to old format (array of trees)
                let trees = try JSONDecoder().decode([ImportedTreeData].self, from: data)
                importTrees(trees, collectionMap: [:])
            }

        } catch {
            importResult = ImportResult(success: false, message: "Failed to parse file: \(error.localizedDescription)")
            showingResult = true
        }
    }

    private func importNewFormat(_ importedData: ImportedData) {
        // Create collections first and build a mapping from old ID to new Collection
        var collectionMap: [String: Collection] = [:]
        var collectionCount = 0

        for importedCollection in importedData.collections {
            let collection = Collection(name: importedCollection.name)
            modelContext.insert(collection)
            collectionMap[importedCollection.id] = collection
            collectionCount += 1
        }

        print("🌐 Import: Created \(collectionCount) collections")

        // Import trees with collection mapping
        importTrees(importedData.trees, collectionMap: collectionMap, collectionCount: collectionCount)
    }

    private func importTrees(_ trees: [ImportedTreeData], collectionMap: [String: Collection], collectionCount: Int = 0) {
        var importedCount = 0
        var photoCount = 0
        var treesWithPhotos: [(Tree, [(Data, Date?)])] = []

        for importedTree in trees {
            let tree = Tree(
                id: importedTree.parsedId ?? UUID(),
                latitude: importedTree.latitude,
                longitude: importedTree.longitude,
                horizontalAccuracy: importedTree.horizontalAccuracy,
                altitude: importedTree.altitude,
                species: importedTree.species,
                variety: importedTree.variety,
                rootstock: importedTree.rootstock,
                createdAt: importedTree.parsedCreatedAt ?? Date(),
                updatedAt: importedTree.parsedUpdatedAt ?? Date()
            )

            modelContext.insert(tree)

            // Link to collection if specified
            if let collectionId = importedTree.collectionId,
               let collection = collectionMap[collectionId] {
                tree.collection = collection
            }

            // Add notes as a Note entity if provided
            if !importedTree.notes.isEmpty {
                _ = tree.addNote(text: importedTree.notes)
            }

            // Collect photos for delayed import
            if photoImportMode != .none, let photosBase64 = importedTree.photos {
                var photos: [(Data, Date?)] = []
                for (index, photoString) in photosBase64.enumerated() {
                    if let photoData = Data(base64Encoded: photoString) {
                        let captureDate = importedTree.captureDate(at: index)
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
        do {
            try modelContext.save()
            print("🌐 Import: Saved \(importedCount) trees")
        } catch {
            print("🌐 Import: Failed to save: \(error)")
        }

        // Build result message
        var messageParts: [String] = []
        if collectionCount > 0 {
            messageParts.append("\(collectionCount) collection\(collectionCount == 1 ? "" : "s")")
        }
        messageParts.append("\(importedCount) tree\(importedCount == 1 ? "" : "s")")

        // For delayed mode, add photos one tree at a time with delays
        if photoImportMode == .withDelay && !treesWithPhotos.isEmpty {
            importResult = ImportResult(
                success: true,
                message: "Imported \(messageParts.joined(separator: " and ")). Adding \(photoCount) photos in background..."
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
            if photoCount > 0 {
                messageParts.append("\(photoCount) photo\(photoCount == 1 ? "" : "s")")
            }
            importResult = ImportResult(
                success: true,
                message: "Successfully imported \(messageParts.joined(separator: ", "))."
            )
            showingResult = true
        }
    }
}

// New format with collections
private struct ImportedData: Codable {
    let collections: [ImportedCollection]
    let trees: [ImportedTreeData]
}

private struct ImportedCollection: Codable {
    let id: String
    let name: String
    let createdAt: String?
    let updatedAt: String?
}

// Extended import structure that supports photos
private struct ImportedTreeData: Codable {
    let id: String?
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let altitude: Double?
    let species: String
    let variety: String?
    let rootstock: String?
    let notes: String
    let photos: [String]?  // Base64 encoded photo data
    let photoDates: [Date]?  // Capture dates from old format (as Date)
    let photoDateStrings: [String]?  // Capture dates from new format (as ISO8601 strings)
    let collectionId: String?  // Reference to collection
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, horizontalAccuracy, altitude
        case species, variety, rootstock, notes, photos, photoDates, collectionId
        case createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        horizontalAccuracy = try container.decode(Double.self, forKey: .horizontalAccuracy)
        altitude = try container.decodeIfPresent(Double.self, forKey: .altitude)
        species = try container.decode(String.self, forKey: .species)
        variety = try container.decodeIfPresent(String.self, forKey: .variety)
        rootstock = try container.decodeIfPresent(String.self, forKey: .rootstock)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        photos = try container.decodeIfPresent([String].self, forKey: .photos)
        collectionId = try container.decodeIfPresent(String.self, forKey: .collectionId)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)

        // Try to decode photoDates as Date array first, then as String array
        if let dates = try? container.decodeIfPresent([Date].self, forKey: .photoDates) {
            photoDates = dates
            photoDateStrings = nil
        } else if let dateStrings = try? container.decodeIfPresent([String].self, forKey: .photoDates) {
            photoDateStrings = dateStrings
            photoDates = nil
        } else {
            photoDates = nil
            photoDateStrings = nil
        }
    }

    func captureDate(at index: Int) -> Date? {
        if let dates = photoDates, dates.indices.contains(index) {
            return dates[index]
        }
        if let dateStrings = photoDateStrings, dateStrings.indices.contains(index) {
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: dateStrings[index])
        }
        return nil
    }

    var parsedCreatedAt: Date? {
        createdAt.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    var parsedUpdatedAt: Date? {
        updatedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    var parsedId: UUID? {
        id.flatMap { UUID(uuidString: $0) }
    }
}

#Preview {
    ImportTreesView()
        .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
