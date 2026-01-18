import SwiftUI

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
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .csv
    @State private var includePhotosInJSON = false
    @State private var exportURL: URL?
    @State private var showingShareSheet = false
    @State private var isExporting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "tree.fill")
                            .foregroundStyle(.green)
                        Text("\(trees.count) trees to export")
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
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private func exportData() {
        isExporting = true

        DispatchQueue.global(qos: .userInitiated).async {
            let url: URL?

            switch selectedFormat {
            case .csv:
                url = CSVExporter.exportToFile(trees: trees)
            case .json:
                url = JSONExporter.exportToFile(trees: trees, includePhotos: includePhotosInJSON)
            case .gpx:
                url = GPXExporter.exportToFile(trees: trees)
            }

            DispatchQueue.main.async {
                isExporting = false
                if let url = url {
                    exportURL = url
                    showingShareSheet = true
                }
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
