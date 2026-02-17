import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportCollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Collection.name) private var collections: [Collection]

    @State private var showingFilePicker = false
    @State private var collectionName = ""
    @State private var selectedCollection: Collection?
    @State private var createNewCollection = true
    @State private var importResult: ImportResult?
    @State private var showingResult = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Create New Collection", isOn: $createNewCollection)

                    if createNewCollection {
                        TextField("Collection Name", text: $collectionName)
                    } else {
                        Picker("Add to Collection", selection: $selectedCollection) {
                            Text("Select...").tag(nil as Collection?)
                            ForEach(collections) { collection in
                                Text(collection.name).tag(collection as Collection?)
                            }
                        }
                    }
                } header: {
                    Text("Destination")
                }

                Section {
                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Select JSON File", systemImage: "doc.badge.plus")
                    }
                    .disabled(!canImport)
                } header: {
                    Text("Import")
                } footer: {
                    Text("Import trees from a JSON file exported by Tree Tracker.")
                }
            }
            .navigationTitle("Import Collection")
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

    private var canImport: Bool {
        if createNewCollection {
            return !collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            return selectedCollection != nil
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

            // Try new format first (object with collections and trees keys)
            let trees: [ImportedTree]
            if let importedData = try? JSONDecoder().decode(ImportedCollectionData.self, from: data) {
                trees = importedData.trees
            } else {
                // Fall back to old format (bare array of trees)
                trees = try JSONDecoder().decode([ImportedTree].self, from: data)
            }

            let collection: Collection
            if createNewCollection {
                let name = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                collection = Collection(name: name)
                modelContext.insert(collection)
            } else {
                guard let selected = selectedCollection else { return }
                collection = selected
            }

            var importedCount = 0
            var skippedCount = 0
            var photoCount = 0
            var remappedIDCount = 0
            var seenImportedIDs = Set<UUID>()

            // Batch-fetch all existing tree IDs to avoid N+1 queries
            let existingIDs = fetchAllTreeIDs()

            for importedTree in trees {
                // Validate GPS coordinates
                guard importedTree.latitude >= -90 && importedTree.latitude <= 90 &&
                      importedTree.longitude >= -180 && importedTree.longitude <= 180 &&
                      importedTree.horizontalAccuracy >= 0 else {
                    skippedCount += 1
                    continue
                }

                let resolvedID: UUID
                if let parsedID = importedTree.parsedId {
                    if seenImportedIDs.contains(parsedID) || existingIDs.contains(parsedID) {
                        resolvedID = UUID()
                        remappedIDCount += 1
                    } else {
                        resolvedID = parsedID
                        seenImportedIDs.insert(parsedID)
                    }
                } else {
                    resolvedID = UUID()
                }

                let tree = Tree(
                    id: resolvedID,
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
                tree.collection = collection
                modelContext.insert(tree)

                // Add notes as a Note entity if provided
                if !importedTree.notes.isEmpty {
                    _ = tree.addNote(text: importedTree.notes)
                }

                // Add photos if present
                if let photosBase64 = importedTree.photos {
                    for (index, photoString) in photosBase64.enumerated() {
                        if let photoData = Data(base64Encoded: photoString) {
                            let captureDate = importedTree.captureDate(at: index)
                            tree.addPhoto(photoData, capturedAt: captureDate)
                            photoCount += 1
                        }
                    }
                }

                importedCount += 1
            }

            try modelContext.save()

            var details: [String] = []
            if photoCount > 0 {
                details.append("with \(photoCount) photos")
            }
            if remappedIDCount > 0 {
                details.append("\(remappedIDCount) ID\(remappedIDCount == 1 ? "" : "s") regenerated")
            }
            if skippedCount > 0 {
                details.append("\(skippedCount) skipped (invalid coordinates)")
            }
            let detailSuffix = details.isEmpty ? "" : " (\(details.joined(separator: ", ")))"

            importResult = ImportResult(
                success: true,
                message: "Successfully imported \(importedCount) tree\(importedCount == 1 ? "" : "s")\(detailSuffix) into \"\(collection.name)\"."
            )
            showingResult = true

        } catch {
            importResult = ImportResult(success: false, message: "Import failed: \(error.localizedDescription)")
            showingResult = true
        }
    }

    private func fetchAllTreeIDs() -> Set<UUID> {
        var descriptor = FetchDescriptor<Tree>()
        descriptor.propertiesToFetch = [\.id]
        do {
            let trees = try modelContext.fetch(descriptor)
            return Set(trees.map(\.id))
        } catch {
            print("Collection import: Failed to fetch existing tree IDs: \(error)")
            return []
        }
    }
}

struct ImportResult {
    let success: Bool
    let message: String
}

// New format: top-level object with collections and trees
struct ImportedCollectionData: Codable {
    let collections: [ImportedCollectionInfo]
    let trees: [ImportedTree]
}

struct ImportedCollectionInfo: Codable {
    let id: String
    let name: String
}

struct ImportedTree: Codable {
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
    let photoDates: [Date]?  // Capture dates (Date format)
    let photoDateStrings: [String]?  // Capture dates (ISO8601 string format)
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, horizontalAccuracy, altitude
        case species, variety, rootstock, notes, photos, photoDates
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

    /// Parse the ISO8601 createdAt string into a Date
    var parsedCreatedAt: Date? {
        createdAt.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    /// Parse the ISO8601 updatedAt string into a Date
    var parsedUpdatedAt: Date? {
        updatedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    /// Parse the id string into a UUID
    var parsedId: UUID? {
        id.flatMap { UUID(uuidString: $0) }
    }
}

#Preview {
    ImportCollectionView()
        .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
