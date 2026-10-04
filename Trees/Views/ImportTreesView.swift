import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportTreesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(PendingPhotoImportQueue.self) private var photoImportQueue

    @State private var showingFilePicker = false
    @State private var importResult: ImportResult?
    @State private var showingResult = false
    @State private var isLoading = false
    @State private var loadingMessage = "Reading file..."
    @State private var photoImportMode: PhotoImportMode = .withDelay

    enum PhotoImportMode: String, CaseIterable {
        case none = "No Photos"
        case withDelay = "With Photos (Delayed)"
        case immediate = "With Photos (Immediate)"

        var description: String {
            switch self {
            case .none: return "Import tree data only, no photos"
            case .withDelay: return "Add photos gradually in the background for reliable sync"
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
                        Label("Select JSON or CSV File", systemImage: "doc.badge.plus")
                    }

                    Picker("Photo Import", selection: $photoImportMode) {
                        ForEach(PhotoImportMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                } header: {
                    Text("Import")
                } footer: {
                    Text("\(photoImportMode.description). CSV files need latitude and longitude columns and carry no photos.")
                }

                if isLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text(loadingMessage)
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
                allowedContentTypes: [.json, .commaSeparatedText, .tabSeparatedText, .plainText],
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

    /// Says what happened to the photos, including any that will not arrive,
    /// so the import never claims more than it did.
    static func photoQueueSummary(_ outcome: PendingPhotoImportQueue.EnqueueResult) -> String {
        func photos(_ count: Int) -> String { "\(count) photo\(count == 1 ? "" : "s")" }
        var text = ""
        if outcome.queued > 0 {
            text += " Adding \(photos(outcome.queued)) in the background; if the app closes first, they continue next time it opens."
        }
        if outcome.failed > 0 {
            text += " \(photos(outcome.failed)) could not be stored on this device and \(outcome.failed == 1 ? "was" : "were") not imported. Free up space and import the file again."
        }
        if outcome.unreadable > 0 {
            text += " \(photos(outcome.unreadable)) in the file \(outcome.unreadable == 1 ? "was" : "were") damaged and could not be read."
        }
        return text
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

        loadingMessage = "Reading file..."
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
                        importResult = ImportResult(success: false, message: "Could not read this file. It needs to be a Tree Tracker JSON export, or a CSV file with latitude and longitude columns.")
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
        if summary.alreadyPresentCount > 0 {
            messageParts.append("\(summary.alreadyPresentCount) already present (skipped)")
        }
        if summary.skippedCount > 0 {
            messageParts.append("\(summary.skippedCount) skipped (missing or invalid coordinates)")
        }

        if !summary.deferredPhotos.isEmpty {
            // The queue owns the photos from here: it spools them to disk and
            // keeps adding them after this view is gone, or after a relaunch.
            let deferredPhotos = summary.deferredPhotos
            let queue = photoImportQueue
            loadingMessage = "Preparing photos..."
            isLoading = true
            Task {
                let outcome = await queue.enqueue(deferredPhotos)
                isLoading = false
                var message = "Imported \(messageParts.joined(separator: ", "))."
                message += Self.photoQueueSummary(outcome)
                importResult = ImportResult(success: true, message: message)
                showingResult = true
            }
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
}

#Preview {
    let container = try! ModelContainer(
        for: Tree.self, Collection.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ImportTreesView()
        .modelContainer(container)
        .environment(PendingPhotoImportQueue(modelContainer: container))
}
