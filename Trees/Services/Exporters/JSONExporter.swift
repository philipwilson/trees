import Foundation

struct JSONExporter {
    struct ExportedTree: Codable {
        let id: String
        let latitude: Double
        let longitude: Double
        let horizontalAccuracy: Double
        let altitude: Double?
        let species: String
        let variety: String?
        let rootstock: String?
        let notes: String
        let photoCount: Int
        let photos: [String]?
        let createdAt: String
        let updatedAt: String
    }

    static func export(trees: [Tree], includePhotos: Bool = false) -> String {
        let dateFormatter = ISO8601DateFormatter()

        let exportedTrees = trees.map { tree in
            // Combine all notes into a single string
            let allNotesText = tree.treeNotes.map { $0.text }.joined(separator: " | ")

            // Get all photos from tree (direct photos only for export)
            let treePhotos = tree.treePhotos

            return ExportedTree(
                id: tree.id.uuidString,
                latitude: tree.latitude,
                longitude: tree.longitude,
                horizontalAccuracy: tree.horizontalAccuracy,
                altitude: tree.altitude,
                species: tree.species,
                variety: tree.variety,
                rootstock: tree.rootstock,
                notes: allNotesText,
                photoCount: treePhotos.count,
                photos: includePhotos ? treePhotos.map { $0.imageData.base64EncodedString() } : nil,
                createdAt: dateFormatter.string(from: tree.createdAt),
                updatedAt: dateFormatter.string(from: tree.updatedAt)
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(exportedTrees),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return jsonString
    }

    static func exportToFile(trees: [Tree], includePhotos: Bool = false, filePrefix: String = "trees") -> URL? {
        let content = export(trees: trees, includePhotos: includePhotos)
        let filename = "\(filePrefix)_\(formattedDate()).json"

        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(filename) else {
            return nil
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: Date())
    }
}
