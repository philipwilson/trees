import SwiftUI

/// Items a list has been asked to delete, held until the user confirms.
struct PendingDeletion<Item> {
    var items: [Item] = []
    var isPresented = false

    mutating func request(_ items: [Item]) {
        guard !items.isEmpty else { return }
        self.items = items
        isPresented = true
    }
}

extension View {
    /// Asks before deleting from a list. Swipe-to-delete and context-menu
    /// deletes route through this so they match the detail screens, which
    /// already confirm.
    func deleteConfirmation<Item>(
        _ pending: Binding<PendingDeletion<Item>>,
        title: ([Item]) -> String,
        message: String,
        onConfirm: @escaping ([Item]) -> Void
    ) -> some View {
        confirmationDialog(
            title(pending.wrappedValue.items),
            isPresented: pending.isPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let items = pending.wrappedValue.items
                pending.wrappedValue.items = []
                onConfirm(items)
            }
            Button("Cancel", role: .cancel) {
                pending.wrappedValue.items = []
            }
        } message: {
            Text(message)
        }
    }
}

extension Tree {
    static let deletionMessage = "Its photos and notes will be deleted too. This action cannot be undone."

    static func deletionTitle(for trees: [Tree]) -> String {
        if trees.count == 1, let tree = trees.first {
            return tree.species.isEmpty ? "Delete this tree?" : "Delete \(tree.species)?"
        }
        return "Delete \(trees.count) trees?"
    }
}

extension Collection {
    static let deletionMessage = "This will delete the collection but keep all trees."

    static func deletionTitle(for collections: [Collection]) -> String {
        if collections.count == 1, let collection = collections.first {
            return "Delete \u{201C}\(collection.name)\u{201D}?"
        }
        return "Delete \(collections.count) collections?"
    }
}
