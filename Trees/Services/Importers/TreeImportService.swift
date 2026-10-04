import Foundation
import SwiftData

/// Shared import logic for Trees JSON exports, used by both ImportTreesView
/// and ImportCollectionView. Runs on the main actor with the main ModelContext.
@MainActor
struct TreeImportService {
    let modelContext: ModelContext

    enum PhotoHandling {
        /// Skip photos entirely
        case none
        /// Attach photos during the import pass
        case immediate
        /// Return photos in `Summary.deferredPhotos` for the caller to hand to
        /// `PendingPhotoImportQueue`, which drip-feeds them one tree at a time
        /// for reliable CloudKit sync
        case deferred
    }

    /// What to do with an archive tree whose ID is already in the store.
    enum ExistingIDPolicy {
        /// Leave the existing tree alone and don't import the record, so
        /// re-importing a backup doesn't duplicate trees
        case skip
        /// Import the record as a copy under a new ID
        case remap
    }

    /// A photo not yet attached to its target. Targets are identified by ID
    /// rather than model reference so the photo can outlive this import (and
    /// the app session), and the image stays base64 — sharing storage with the
    /// decoded archive — until the queue writes it to disk.
    struct DeferredPhoto: Sendable {
        let treeID: UUID
        /// When set, the photo belongs to this note; otherwise to the tree.
        let noteID: UUID?
        let base64: String
        let captureDate: Date?
    }

    struct Summary {
        var collectionsCreated = 0
        var importedCount = 0
        var skippedCount = 0
        var photoCount = 0
        var remappedIDCount = 0
        var alreadyPresentCount = 0
        var deferredPhotos: [DeferredPhoto] = []
    }

    /// Decodes any of the three JSON export formats: v2 (versioned, structured
    /// notes), v1 (collections + flat trees), or the oldest bare tree array.
    /// Anything else is tried as CSV with latitude and longitude columns.
    nonisolated static func decode(_ data: Data) -> ImportedArchive? {
        let decoder = JSONDecoder()
        if let archive = try? decoder.decode(ImportedArchive.self, from: data) {
            return archive
        }
        if let trees = try? decoder.decode([ImportedTreeRecord].self, from: data) {
            return ImportedArchive(version: nil, collections: nil, trees: trees)
        }
        return CSVTreeParser.archive(from: data)
    }

    /// Imports an archive into the model context and saves. Rolls back and
    /// rethrows if the save fails, discarding everything inserted here.
    ///
    /// When `overrideCollection` is set, every tree goes into that collection and
    /// the archive's own collections are ignored. Otherwise archive collections
    /// are matched against existing ones by UUID, then by name, and only created
    /// when neither matches — so re-importing a backup doesn't duplicate them.
    ///
    /// IDs repeated within the archive itself are always remapped; IDs already
    /// in the store follow `existingIDPolicy`.
    func importArchive(
        _ archive: ImportedArchive,
        photoHandling: PhotoHandling,
        existingIDPolicy: ExistingIDPolicy = .skip,
        overrideCollection: Collection? = nil
    ) throws -> Summary {
        var summary = Summary()

        var collectionMap: [String: Collection] = [:]
        if overrideCollection == nil, let importedCollections = archive.collections {
            let existing = (try? modelContext.fetch(FetchDescriptor<Collection>())) ?? []
            for record in importedCollections {
                if let uuid = record.parsedId, let match = existing.first(where: { $0.id == uuid }) {
                    collectionMap[record.id] = match
                } else if let match = existing.first(where: { $0.name == record.name }) {
                    collectionMap[record.id] = match
                } else {
                    let collection = Collection(
                        id: record.parsedId ?? UUID(),
                        name: record.name,
                        createdAt: record.parsedCreatedAt ?? Date(),
                        updatedAt: record.parsedUpdatedAt ?? Date()
                    )
                    modelContext.insert(collection)
                    collectionMap[record.id] = collection
                    summary.collectionsCreated += 1
                }
            }
        }

        let existingIDs = fetchAllTreeIDs()
        var seenImportedIDs = Set<UUID>()

        for record in archive.trees {
            guard record.latitude >= -90, record.latitude <= 90,
                  record.longitude >= -180, record.longitude <= 180,
                  record.horizontalAccuracy >= 0 else {
                summary.skippedCount += 1
                continue
            }

            if existingIDPolicy == .skip, let parsedID = record.parsedId, existingIDs.contains(parsedID) {
                summary.alreadyPresentCount += 1
                continue
            }

            let resolvedID: UUID
            if let parsedID = record.parsedId {
                if seenImportedIDs.contains(parsedID) || existingIDs.contains(parsedID) {
                    resolvedID = UUID()
                    summary.remappedIDCount += 1
                } else {
                    resolvedID = parsedID
                    seenImportedIDs.insert(parsedID)
                }
            } else {
                resolvedID = UUID()
            }

            let tree = Tree(
                id: resolvedID,
                latitude: record.latitude,
                longitude: record.longitude,
                horizontalAccuracy: record.horizontalAccuracy,
                altitude: record.altitude,
                species: record.species,
                variety: record.variety,
                rootstock: record.rootstock,
                createdAt: record.parsedCreatedAt ?? Date(),
                updatedAt: record.parsedUpdatedAt ?? Date()
            )
            modelContext.insert(tree)

            if let overrideCollection {
                tree.collection = overrideCollection
            } else if let collectionId = record.collectionId,
                      let collection = collectionMap[collectionId] {
                tree.collection = collection
            }

            if let noteRecords = record.noteEntries {
                // v2: structured notes with original dates and their own photos
                for noteRecord in noteRecords {
                    let note = Note(
                        text: noteRecord.text,
                        createdAt: noteRecord.parsedCreatedAt ?? Date(),
                        updatedAt: noteRecord.parsedUpdatedAt ?? noteRecord.parsedCreatedAt ?? Date()
                    )
                    note.tree = tree
                    if tree.notes == nil { tree.notes = [] }
                    tree.notes?.append(note)

                    for photoRecord in noteRecord.photos ?? [] {
                        handlePhoto(
                            base64: photoRecord.data, captureDate: photoRecord.parsedCaptureDate,
                            tree: tree, note: note, photoHandling: photoHandling, summary: &summary
                        )
                    }
                }
            } else if !record.notes.isEmpty {
                // v1: single note from the combined string; original dates are lost
                let note = Note(text: record.notes)
                note.tree = tree
                if tree.notes == nil { tree.notes = [] }
                tree.notes?.append(note)
            }

            if let treePhotoRecords = record.treePhotos {
                // v2: tree-owned photos only (note photos handled above)
                for photoRecord in treePhotoRecords {
                    handlePhoto(
                        base64: photoRecord.data, captureDate: photoRecord.parsedCaptureDate,
                        tree: tree, note: nil, photoHandling: photoHandling, summary: &summary
                    )
                }
            } else if let legacyPhotos = record.photos {
                // v1: flat array, everything reattaches to the tree
                for (index, base64) in legacyPhotos.enumerated() {
                    handlePhoto(
                        base64: base64, captureDate: record.legacyCaptureDate(at: index),
                        tree: tree, note: nil, photoHandling: photoHandling, summary: &summary
                    )
                }
            }

            summary.importedCount += 1
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        return summary
    }

    private func handlePhoto(
        base64: String,
        captureDate: Date?,
        tree: Tree,
        note: Note?,
        photoHandling: PhotoHandling,
        summary: inout Summary
    ) {
        switch photoHandling {
        case .none:
            return
        case .immediate:
            guard let data = Data(base64Encoded: base64) else { return }
            summary.photoCount += 1
            Self.attachPhoto(data: data, captureDate: captureDate, to: tree, note: note)
        case .deferred:
            // Not decoded here; the queue decodes one photo at a time while
            // spooling to disk and drops any that turn out to be invalid.
            summary.photoCount += 1
            summary.deferredPhotos.append(
                DeferredPhoto(treeID: tree.id, noteID: note?.id, base64: base64, captureDate: captureDate)
            )
        }
    }

    /// Attaches photo data to the note if given, otherwise to the tree.
    /// Constructs the Photo directly (not via the add* helpers) so imported
    /// updatedAt values survive.
    static func attachPhoto(data: Data, captureDate: Date?, to tree: Tree, note: Note?) {
        let photo = Photo(imageData: data, captureDate: captureDate)
        if let note {
            photo.note = note
            if note.photos == nil { note.photos = [] }
            note.photos?.append(photo)
        } else {
            photo.tree = tree
            if tree.photos == nil { tree.photos = [] }
            tree.photos?.append(photo)
        }
    }

    private func fetchAllTreeIDs() -> Set<UUID> {
        var descriptor = FetchDescriptor<Tree>()
        descriptor.propertiesToFetch = [\.id]
        do {
            let trees = try modelContext.fetch(descriptor)
            return Set(trees.map(\.id))
        } catch {
            print("Import: failed to fetch existing tree IDs: \(error)")
            return []
        }
    }
}
