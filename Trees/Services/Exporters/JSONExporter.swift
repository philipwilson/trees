import Foundation

/// Exports trees as versioned JSON (format v2).
///
/// v2 adds structured fields that round-trip the full data model:
/// - `noteEntries`: one object per note with its text, dates, and own photos
/// - `treePhotos`: photos owned by the tree itself (no longer flattened with note photos)
///
/// Legacy v1 fields are still written so older app builds and external tools can
/// read v2 files (they get coordinates, species, dates, and the combined notes
/// text, but no photos): `notes` stays the " | "-joined string and `photoCount`
/// the total across tree and notes. The v1 flat `photos`/`photoDates` arrays are
/// no longer written.
struct JSONExporter {
    static let formatVersion = 2

    struct ExportedCollection: Codable {
        let id: String
        let name: String
        let createdAt: String
        let updatedAt: String
    }

    struct ExportedPhoto: Codable {
        let data: String          // base64-encoded image data
        let captureDate: String?  // ISO8601
    }

    struct ExportedNote: Codable {
        let text: String
        let createdAt: String
        let updatedAt: String
        let photos: [ExportedPhoto]?
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
        let noteEntries: [ExportedNote]?
        let treePhotos: [ExportedPhoto]?
        let collectionId: String?
        let createdAt: String
        let updatedAt: String
    }

    struct ExportedData: Codable {
        let version: Int
        let collections: [ExportedCollection]
        let trees: [ExportedTree]
    }

    static func export(trees: [Tree], collections: [Collection] = [], includePhotos: Bool = false) -> String {
        encode(trees: trees, collections: collections, includePhotos: includePhotos) ?? "{}"
    }

    /// Returns nil if the data cannot be encoded (e.g. a non-finite coordinate).
    private static func encode(trees: [Tree], collections: [Collection], includePhotos: Bool) -> String? {
        let dateFormatter = ISO8601DateFormatter()

        let exportedData = ExportedData(
            version: formatVersion,
            collections: collections.map { makeExportedCollection($0, dateFormatter: dateFormatter) },
            trees: trees.map { makeExportedTree($0, includePhotos: includePhotos, dateFormatter: dateFormatter) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(exportedData) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func exportToFile(trees: [Tree], collections: [Collection] = [], includePhotos: Bool = false, filePrefix: String = "trees") -> URL? {
        let filename = "\(filePrefix)_\(formattedDate()).json"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        if !includePhotos {
            guard let content = encode(trees: trees, collections: collections, includePhotos: false) else {
                return nil
            }
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                return url
            } catch {
                return nil
            }
        }

        // Stream photo exports per-tree to avoid loading all base64 data into memory
        guard let outputStream = OutputStream(url: url, append: false) else { return nil }
        outputStream.open()
        defer { outputStream.close() }

        let dateFormatter = ISO8601DateFormatter()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        // Set by a failed write or a tree that won't encode. Either way the
        // file is incomplete, so it is deleted and the export reported as failed
        // rather than handing over a backup with data silently missing.
        var writeError = false

        func write(_ string: String) {
            guard !writeError else { return }
            let bytes = Array(string.utf8)
            var offset = 0
            while offset < bytes.count {
                let written = outputStream.write(Array(bytes[offset...]), maxLength: bytes.count - offset)
                if written <= 0 {
                    writeError = true
                    return
                }
                offset += written
            }
        }

        let exportedCollections = collections.map { makeExportedCollection($0, dateFormatter: dateFormatter) }
        let collectionsJSON = (try? encoder.encode(exportedCollections))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        write("{\"version\":\(formatVersion),\"collections\":\(collectionsJSON),\"trees\":[")

        // Write each tree individually so only one tree's photos are in memory at a time
        for (index, tree) in trees.enumerated() {
            autoreleasepool {
                guard !writeError else { return }
                let exportedTree = makeExportedTree(tree, includePhotos: true, dateFormatter: dateFormatter)

                guard let treeData = try? encoder.encode(exportedTree),
                      let treeJSON = String(data: treeData, encoding: .utf8) else {
                    print("JSON export: failed to encode tree \(tree.id)")
                    writeError = true
                    return
                }
                if index > 0 { write(",") }
                write(treeJSON)
            }
        }

        write("]}")

        if writeError {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        return url
    }

    private static func makeExportedCollection(_ collection: Collection, dateFormatter: ISO8601DateFormatter) -> ExportedCollection {
        ExportedCollection(
            id: collection.id.uuidString,
            name: collection.name,
            createdAt: dateFormatter.string(from: collection.createdAt),
            updatedAt: dateFormatter.string(from: collection.updatedAt)
        )
    }

    private static func makeExportedTree(_ tree: Tree, includePhotos: Bool, dateFormatter: ISO8601DateFormatter) -> ExportedTree {
        let noteEntries = tree.treeNotes.map { note in
            ExportedNote(
                text: note.text,
                createdAt: dateFormatter.string(from: note.createdAt),
                updatedAt: dateFormatter.string(from: note.updatedAt),
                photos: includePhotos ? note.notePhotos.map { makeExportedPhoto($0, dateFormatter: dateFormatter) } : nil
            )
        }

        return ExportedTree(
            id: tree.id.uuidString,
            latitude: tree.latitude,
            longitude: tree.longitude,
            horizontalAccuracy: tree.horizontalAccuracy,
            altitude: tree.altitude,
            species: tree.species,
            variety: tree.variety,
            rootstock: tree.rootstock,
            notes: tree.treeNotes.map { $0.text }.joined(separator: " | "),
            photoCount: tree.allPhotos.count,
            noteEntries: noteEntries,
            treePhotos: includePhotos ? tree.treePhotos.map { makeExportedPhoto($0, dateFormatter: dateFormatter) } : nil,
            collectionId: tree.collection?.id.uuidString,
            createdAt: dateFormatter.string(from: tree.createdAt),
            updatedAt: dateFormatter.string(from: tree.updatedAt)
        )
    }

    private static func makeExportedPhoto(_ photo: Photo, dateFormatter: ISO8601DateFormatter) -> ExportedPhoto {
        ExportedPhoto(
            data: photo.imageData.base64EncodedString(),
            captureDate: photo.captureDate.map { dateFormatter.string(from: $0) }
        )
    }

    private static func formattedDate() -> String {
        let formatter = DateFormatter()
        // Fixed locale: with the device set to 12-hour time, the user's locale
        // rewrites HH and the name comes out as e.g. "44444_008 PM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss_SSS"
        return formatter.string(from: Date())
    }
}
