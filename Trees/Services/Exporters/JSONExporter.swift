import Foundation

struct JSONExporter {
    struct ExportedCollection: Codable {
        let id: String
        let name: String
        let createdAt: String
        let updatedAt: String
    }

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
        let photoDates: [String]?
        let collectionId: String?
        let createdAt: String
        let updatedAt: String
    }

    struct ExportedData: Codable {
        let collections: [ExportedCollection]
        let trees: [ExportedTree]
    }

    static func export(trees: [Tree], collections: [Collection] = [], includePhotos: Bool = false) -> String {
        let dateFormatter = ISO8601DateFormatter()

        let exportedCollections = collections.map { collection in
            ExportedCollection(
                id: collection.id.uuidString,
                name: collection.name,
                createdAt: dateFormatter.string(from: collection.createdAt),
                updatedAt: dateFormatter.string(from: collection.updatedAt)
            )
        }

        let exportedTrees = trees.map { tree in
            // Combine all notes into a single string
            let allNotesText = tree.treeNotes.map { $0.text }.joined(separator: " | ")

            // Get all photos from tree (including note photos)
            let treePhotos = tree.allPhotos

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
                photoDates: includePhotos ? treePhotos.map { photo in
                    photo.captureDate.map { dateFormatter.string(from: $0) } ?? ""
                } : nil,
                collectionId: tree.collection?.id.uuidString,
                createdAt: dateFormatter.string(from: tree.createdAt),
                updatedAt: dateFormatter.string(from: tree.updatedAt)
            )
        }

        let exportedData = ExportedData(collections: exportedCollections, trees: exportedTrees)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(exportedData),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return jsonString
    }

    static func exportToFile(trees: [Tree], collections: [Collection] = [], includePhotos: Bool = false, filePrefix: String = "trees") -> URL? {
        let content = export(trees: trees, collections: collections, includePhotos: includePhotos)
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
