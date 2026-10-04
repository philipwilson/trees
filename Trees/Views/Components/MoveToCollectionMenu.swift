import SwiftUI
import SwiftData

/// A "Move to Collection" submenu for a tree's context menu. Lists every
/// collection plus "None", with a checkmark on the current one.
struct MoveToCollectionMenu: View {
    let tree: Tree
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Collection.name) private var collections: [Collection]

    var body: some View {
        Menu {
            Button {
                move(to: nil)
            } label: {
                if tree.collection == nil {
                    Label("None", systemImage: "checkmark")
                } else {
                    Text("None")
                }
            }

            ForEach(collections) { collection in
                Button {
                    move(to: collection)
                } label: {
                    if tree.collection?.id == collection.id {
                        Label(collection.name, systemImage: "checkmark")
                    } else {
                        Text(collection.name)
                    }
                }
            }
        } label: {
            Label("Move to Collection", systemImage: "folder")
        }
    }

    private func move(to collection: Collection?) {
        guard tree.collection?.id != collection?.id else { return }
        tree.move(to: collection)
        do {
            try modelContext.save()
        } catch {
            print("Failed to move tree \(tree.id) to collection: \(error)")
            modelContext.rollback()
        }
    }
}

extension Tree {
    /// Reassigns the tree and stamps it and both collections as updated.
    func move(to newCollection: Collection?) {
        let now = Date()
        collection?.updatedAt = now
        newCollection?.updatedAt = now
        collection = newCollection
        updatedAt = now
    }
}
