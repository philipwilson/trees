import SwiftUI
import SwiftData

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case json = "JSON"
    case gpx = "GPX"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .csv:
            return "Spreadsheet compatible format"
        case .json:
            return "Full data with optional photos"
        case .gpx:
            return "GPS waypoints for mapping apps"
        }
    }

    var icon: String {
        switch self {
        case .csv:
            return "tablecells"
        case .json:
            return "curlybraces"
        case .gpx:
            return "map"
        }
    }

    var fileExtension: String {
        rawValue.lowercased()
    }
}

struct ExportView: View {
    let trees: [Tree]
    var collections: [Collection] = []
    var collectionName: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var selectedFormat: ExportFormat = .csv
    @State private var includePhotosInJSON = false
    @State private var includeCollections = true
    @State private var exportURL: URL?
    @State private var showingShareSheet = false
    @State private var isExporting = false
    @State private var showingExportError = false

    private var filePrefix: String {
        if let name = collectionName {
            return Self.sanitizedFilePrefix(name)
        }
        return "trees"
    }

    /// Turns a collection name into a safe filename prefix. Path separators and
    /// other punctuation would otherwise make the temp-file write fail.
    static func sanitizedFilePrefix(_ name: String) -> String {
        let mapped = name.lowercased().map { character -> Character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "_"
        }
        let prefix = String(mapped)
        return prefix.contains(where: { $0 != "_" }) ? prefix : "trees"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let name = collectionName {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.orange)
                            Text(name)
                        }
                    }
                    HStack {
                        Image(systemName: "tree.fill")
                            .foregroundStyle(.green)
                        Text("\(trees.count) tree\(trees.count == 1 ? "" : "s") to export")
                    }
                    if !collections.isEmpty {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.orange)
                            Text("\(collections.count) collection\(collections.count == 1 ? "" : "s") to export")
                        }
                    }
                } header: {
                    Text("Summary")
                }

                Section {
                    ForEach(ExportFormat.allCases) { format in
                        Button {
                            selectedFormat = format
                        } label: {
                            HStack {
                                Image(systemName: format.icon)
                                    .frame(width: 24)
                                    .foregroundStyle(.primary)
                                VStack(alignment: .leading) {
                                    Text(format.rawValue)
                                        .foregroundStyle(.primary)
                                    Text(format.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedFormat == format {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Format")
                }

                if selectedFormat == .json {
                    Section {
                        if !collections.isEmpty {
                            Toggle("Include Collections", isOn: $includeCollections)
                        }
                        Toggle("Include Photos (Base64)", isOn: $includePhotosInJSON)
                    } footer: {
                        Text("Including photos will significantly increase file size.")
                    }
                }

                Section {
                    Button {
                        exportData()
                    } label: {
                        HStack {
                            Spacer()
                            if isExporting {
                                ProgressView()
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                Text("Export \(selectedFormat.rawValue)")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isExporting || trees.isEmpty)
                }
            }
            .navigationTitle("Export Trees")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet, onDismiss: {
                if let url = exportURL {
                    try? FileManager.default.removeItem(at: url)
                    exportURL = nil
                }
            }) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
            .alert("Export Failed", isPresented: $showingExportError) {
                Button("OK") {}
            } message: {
                Text("Could not create the \(selectedFormat.rawValue) file. Please try again.")
            }
        }
    }

    private func exportData() {
        isExporting = true
        let prefix = filePrefix
        let format = selectedFormat
        let includePhotos = includePhotosInJSON
        let treeIDs = trees.map(\.persistentModelID)
        let collectionIDs = (includeCollections ? collections : []).map(\.persistentModelID)

        // The worker reads through its own context, so pending edits must be
        // saved for it to see them.
        try? modelContext.save()
        let container = modelContext.container

        Task {
            // Created inside a detached task: a model actor made on the main
            // actor would do its work on the main thread.
            let url = await Task.detached(priority: .userInitiated) {
                let worker = ExportWorker(modelContainer: container)
                return await worker.export(
                    format: format,
                    treeIDs: treeIDs,
                    collectionIDs: collectionIDs,
                    includePhotos: includePhotos,
                    filePrefix: prefix
                )
            }.value

            isExporting = false
            if let url {
                exportURL = url
                showingShareSheet = true
            } else {
                showingExportError = true
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ExportView(trees: [
        Tree(latitude: 45.0, longitude: -122.0, horizontalAccuracy: 5.0, species: "Oak"),
        Tree(latitude: 45.1, longitude: -122.1, horizontalAccuracy: 3.0, species: "Maple")
    ])
}
