import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportTreesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingFilePicker = false
    @State private var importResult: ImportResult?
    @State private var showingResult = false
    @State private var isLoading = false
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

        var photoHandling: TreeImportService.PhotoHandling {
            switch self {
            case .none: return .none
            case .withDelay: return .deferred
            case .immediate: return .immediate
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
        let service = TreeImportService(modelContext: modelContext)
        let summary: TreeImportService.Summary
        do {
            summary = try service.importArchive(archive, photoHandling: photoImportMode.photoHandling)
            print("🌐 Import: Saved \(summary.importedCount) trees, \(summary.collectionsCreated) new collections")
        } catch {
            print("🌐 Import: Failed to save: \(error)")
            importResult = ImportResult(
                success: false,
                message: "Import failed while saving trees: \(error.localizedDescription)"
            )
            showingResult = true
            return
        }

        var messageParts: [String] = []
        if summary.collectionsCreated > 0 {
            messageParts.append("\(summary.collectionsCreated) collection\(summary.collectionsCreated == 1 ? "" : "s")")
        }
        messageParts.append("\(summary.importedCount) tree\(summary.importedCount == 1 ? "" : "s")")
        if summary.remappedIDCount > 0 {
            messageParts.append("\(summary.remappedIDCount) ID\(summary.remappedIDCount == 1 ? "" : "s") regenerated")
        }
        if summary.skippedCount > 0 {
            messageParts.append("\(summary.skippedCount) skipped (invalid coordinates)")
        }

        if !summary.deferredPhotos.isEmpty {
            importResult = ImportResult(
                success: true,
                message: "Imported \(messageParts.joined(separator: " and ")). Adding \(summary.photoCount) photos in background — keep the app open until they finish."
            )
            showingResult = true
            startDeferredPhotoImport(summary: summary, messageParts: messageParts)
        } else {
            if summary.photoCount > 0 {
                messageParts.append("\(summary.photoCount) photo\(summary.photoCount == 1 ? "" : "s")")
            }
            importResult = ImportResult(
                success: true,
                message: "Successfully imported \(messageParts.joined(separator: ", "))."
            )
            showingResult = true
        }
    }

    /// Drip-feeds photos one tree at a time so CloudKit sync keeps up.
    /// Intentionally not cancelled when this view disappears: the task only
    /// references container-owned objects, and the user has already been told
    /// the photos are being added in the background.
    private func startDeferredPhotoImport(summary: TreeImportService.Summary, messageParts: [String]) {
        let service = TreeImportService(modelContext: modelContext)
        let batches = summary.deferredPhotos

        Task { @MainActor in
            var failedPhotoBatchSaves = 0
            for (index, batch) in batches.enumerated() {
                // Wait before adding each tree's photos
                try? await Task.sleep(for: .seconds(2))

                for photo in batch.photos {
                    service.attach(photo, to: batch.tree)
                }

                do {
                    try modelContext.save()
                    print("🌐 Import: Added \(batch.photos.count) photos to tree \(index + 1)/\(batches.count)")
                } catch {
                    failedPhotoBatchSaves += 1
                    print("🌐 Import: Failed to save delayed photos for tree \(index + 1): \(error)")
                }
            }

            if failedPhotoBatchSaves > 0 {
                importResult = ImportResult(
                    success: false,
                    message: "Imported \(messageParts.joined(separator: ", ")), but failed to save delayed photos for \(failedPhotoBatchSaves) tree\(failedPhotoBatchSaves == 1 ? "" : "s")."
                )
                showingResult = true
            }
            print("🌐 Import: Finished adding all photos")
        }
    }
}

#Preview {
    ImportTreesView()
        .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
