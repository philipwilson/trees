import Foundation
import SwiftData

/// Imports trees received from Apple Watch into SwiftData
struct WatchTreeImporter {
    let modelContext: ModelContext

    /// Import a WatchTree into SwiftData
    /// Returns the created Tree or nil if a tree with the same ID already exists
    @discardableResult
    func importTree(_ watchTree: WatchTree) -> Tree? {
        if case .imported(let tree) = importOutcome(watchTree) {
            return tree
        }
        return nil
    }

    /// Imports a WatchTree and says what happened, so a caller holding the
    /// original payload knows whether it is safe to discard: a duplicate is,
    /// a failed lookup or save is not.
    func importOutcome(_ watchTree: WatchTree) -> WatchTreeInbox.ImportOutcome {
        // Check for duplicate by ID
        let existingID = watchTree.id
        let descriptor = FetchDescriptor<Tree>(
            predicate: #Predicate { $0.id == existingID }
        )

        do {
            let existing = try modelContext.fetch(descriptor)
            if !existing.isEmpty {
                return .alreadyPresent
            }
        } catch {
            print("Watch import fetch failed: \(error)")
            return .failed
        }

        let tree = Tree(
            id: watchTree.id,
            latitude: watchTree.latitude,
            longitude: watchTree.longitude,
            horizontalAccuracy: watchTree.horizontalAccuracy,
            altitude: watchTree.altitude,
            species: watchTree.species,
            createdAt: watchTree.capturedAt,
            updatedAt: Date()
        )

        modelContext.insert(tree)

        // Add notes as a Note entity if provided
        if !watchTree.notes.isEmpty {
            _ = tree.addNote(text: watchTree.notes)
        }

        do {
            try modelContext.save()
            return .imported(tree)
        } catch {
            print("Watch import save failed for \(watchTree.id): \(error)")
            // Don't leave the unsaved tree in the context to be picked up by
            // a later autosave while its payload is also retried
            modelContext.rollback()
            return .failed
        }
    }

    /// Import multiple WatchTrees
    func importTrees(_ watchTrees: [WatchTree]) -> [Tree] {
        watchTrees.compactMap { importTree($0) }
    }
}
