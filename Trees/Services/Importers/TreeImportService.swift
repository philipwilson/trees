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
        /// Return photos in `Summary.deferredPhotos` for the caller to drip-feed
        /// (one tree at a time, for reliable CloudKit sync)
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

    /// A decoded photo not yet attached to its target.
    struct PendingPhoto {
        let data: Data
        let captureDate: Date?
        /// When set, the photo belongs to this note; otherwise to the tree.
        let note: Note?
    }

    struct Summary {
        var collectionsCreated = 0
        var importedCount = 0
        var skippedCount = 0
        var photoCount = 0
        var remappedIDCount = 0
        var alreadyPresentCount = 0
        var deferredPhotos: [(tree: Tree, photos: [PendingPhoto])] = []
    }

    /// Decodes any of the three export formats: v2 (versioned, structured notes),
    /// v1 (collections + flat trees), or the oldest bare tree array.
    nonisolated static func decode(_ data: Data) -> ImportedArchive? {
        let decoder = JSONDecoder()
        if let archive = try? decoder.decode(ImportedArchive.self, from: data) {
            return archive
        }
        if let trees = try? decoder.decode([ImportedTreeRecord].self, from: data) {
            return ImportedArchive(version: nil, collections: nil, trees: trees)
        }
        return nil
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

            var pending: [PendingPhoto] = []

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

                    guard photoHandling != .none else { continue }
                    for photoRecord in noteRecord.photos ?? [] {
                        guard let data = Data(base64Encoded: photoRecord.data) else { continue }
                        summary.photoCount += 1
                        let photo = PendingPhoto(data: data, captureDate: photoRecord.parsedCaptureDate, note: note)
                        if photoHandling == .immediate {
                            attach(photo, to: tree)
                        } else {
                            pending.append(photo)
                        }
                    }
                }
            } else if !record.notes.isEmpty {
                // v1: single note from the combined string; original dates are lost
                let note = Note(text: record.notes)
                note.tree = tree
                if tree.notes == nil { tree.notes = [] }
                tree.notes?.append(note)
            }

            if photoHandling != .none {
                if let treePhotoRecords = record.treePhotos {
                    // v2: tree-owned photos only (note photos handled above)
                    for photoRecord in treePhotoRecords {
                        guard let data = Data(base64Encoded: photoRecord.data) else { continue }
                        summary.photoCount += 1
                        let photo = PendingPhoto(data: data, captureDate: photoRecord.parsedCaptureDate, note: nil)
                        if photoHandling == .immediate {
                            attach(photo, to: tree)
                        } else {
                            pending.append(photo)
                        }
                    }
                } else if let legacyPhotos = record.photos {
                    // v1: flat array, everything reattaches to the tree
                    for (index, base64) in legacyPhotos.enumerated() {
                        guard let data = Data(base64Encoded: base64) else { continue }
                        summary.photoCount += 1
                        let photo = PendingPhoto(data: data, captureDate: record.legacyCaptureDate(at: index), note: nil)
                        if photoHandling == .immediate {
                            attach(photo, to: tree)
                        } else {
                            pending.append(photo)
                        }
                    }
                }
            }

            if !pending.isEmpty {
                summary.deferredPhotos.append((tree: tree, photos: pending))
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

    /// Attaches a pending photo to its note or tree. Constructs the Photo
    /// directly (not via the add* helpers) so imported updatedAt values survive.
    func attach(_ pending: PendingPhoto, to tree: Tree) {
        let photo = Photo(imageData: pending.data, captureDate: pending.captureDate)
        if let note = pending.note {
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
