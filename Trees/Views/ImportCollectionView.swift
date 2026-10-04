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
    @State private var isLoading = false

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

                if isLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Reading file...")
                                .foregroundStyle(.secondary)
                        }
                    }
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

        isLoading = true

        Task.detached {
            do {
                let data = try Data(contentsOf: url)
                let archive = TreeImportService.decode(data)

                await MainActor.run {
                    url.stopAccessingSecurityScopedResource()
                    isLoading = false

                    if let archive {
                        importArchive(archive)
                    } else {
                        importResult = ImportResult(success: false, message: "Failed to parse file. Ensure it is a valid Trees JSON export.")
                        showingResult = true
                    }
                }
            } catch {
                await MainActor.run {
                    url.stopAccessingSecurityScopedResource()
                    isLoading = false
                    importResult = ImportResult(success: false, message: "Failed to read file: \(error.localizedDescription)")
                    showingResult = true
                }
            }
        }
    }

    private func importArchive(_ archive: ImportedArchive) {
        let collection: Collection
        if createNewCollection {
            let name = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
            collection = Collection(name: name)
            modelContext.insert(collection)
        } else {
            guard let selected = selectedCollection else { return }
            collection = selected
        }

        let service = TreeImportService(modelContext: modelContext)
        do {
            // overrideCollection puts every tree into the chosen destination; the
            // archive's own collections are ignored by design in this flow. Trees
            // that already exist are imported as copies so the destination
            // collection always receives the file's full contents.
            let summary = try service.importArchive(
                archive,
                photoHandling: .immediate,
                existingIDPolicy: .remap,
                overrideCollection: collection
            )

            var details: [String] = []
            if summary.photoCount > 0 {
                details.append("with \(summary.photoCount) photos")
            }
            if summary.remappedIDCount > 0 {
                details.append("\(summary.remappedIDCount) ID\(summary.remappedIDCount == 1 ? "" : "s") regenerated")
            }
            if summary.skippedCount > 0 {
                details.append("\(summary.skippedCount) skipped (invalid coordinates)")
            }
            let detailSuffix = details.isEmpty ? "" : " (\(details.joined(separator: ", ")))"

            importResult = ImportResult(
                success: true,
                message: "Successfully imported \(summary.importedCount) tree\(summary.importedCount == 1 ? "" : "s")\(detailSuffix) into \"\(collection.name)\"."
            )
            showingResult = true
        } catch {
            // The service rolled back the context, which also discards the
            // collection inserted above if it was new.
            importResult = ImportResult(success: false, message: "Import failed: \(error.localizedDescription)")
            showingResult = true
        }
    }
}

#Preview {
    ImportCollectionView()
        .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
