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
            let trees = try JSONDecoder().decode([ImportedTree].self, from: data)

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
            for importedTree in trees {
                let tree = Tree(
                    latitude: importedTree.latitude,
                    longitude: importedTree.longitude,
                    horizontalAccuracy: importedTree.horizontalAccuracy,
                    altitude: importedTree.altitude,
                    species: importedTree.species,
                    variety: importedTree.variety,
                    rootstock: importedTree.rootstock,
                    notes: importedTree.notes
                )
                tree.collection = collection
                modelContext.insert(tree)
                importedCount += 1
            }

            importResult = ImportResult(
                success: true,
                message: "Successfully imported \(importedCount) trees into \"\(collection.name)\"."
            )
            showingResult = true

        } catch {
            importResult = ImportResult(success: false, message: "Failed to parse file: \(error.localizedDescription)")
            showingResult = true
        }
    }
}

struct ImportResult {
    let success: Bool
    let message: String
}

struct ImportedTree: Codable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let altitude: Double?
    let species: String
    let variety: String?
    let rootstock: String?
    let notes: String
}

#Preview {
    ImportCollectionView()
        .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
