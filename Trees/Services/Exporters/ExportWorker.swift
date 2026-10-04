import Foundation
import SwiftData

/// Runs exports on a background model context so reading and encoding every
/// photo doesn't block the UI. Models are passed by identifier and re-fetched
/// here; callers should save the main context first so this context sees
/// their latest changes.
@ModelActor
actor ExportWorker {
    func export(
        format: ExportFormat,
        treeIDs: [PersistentIdentifier],
        collectionIDs: [PersistentIdentifier],
        includePhotos: Bool,
        filePrefix: String
    ) -> URL? {
        let trees = treeIDs.compactMap { self[$0, as: Tree.self] }
        let collections = collectionIDs.compactMap { self[$0, as: Collection.self] }

        switch format {
        case .csv:
            return CSVExporter.exportToFile(trees: trees, filePrefix: filePrefix)
        case .json:
            return JSONExporter.exportToFile(
                trees: trees, collections: collections, includePhotos: includePhotos, filePrefix: filePrefix
            )
        case .gpx:
            return GPXExporter.exportToFile(trees: trees, filePrefix: filePrefix)
        }
    }
}
