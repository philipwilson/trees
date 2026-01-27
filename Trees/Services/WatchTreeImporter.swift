import Foundation
import SwiftData

/// Imports trees received from Apple Watch into SwiftData
struct WatchTreeImporter {
    let modelContext: ModelContext

    /// Import a WatchTree into SwiftData
    /// Returns the created Tree or nil if a tree with the same ID already exists
    @discardableResult
    func importTree(_ watchTree: WatchTree) -> Tree? {
        // Check for duplicate by ID
        let existingID = watchTree.id
        let descriptor = FetchDescriptor<Tree>(
            predicate: #Predicate { $0.id == existingID }
        )

        if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty {
            return nil
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
            return tree
        } catch {
            return nil
        }
    }

    /// Import multiple WatchTrees
    func importTrees(_ watchTrees: [WatchTree]) -> [Tree] {
        watchTrees.compactMap { importTree($0) }
    }
}
