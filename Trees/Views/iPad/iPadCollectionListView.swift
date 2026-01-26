import SwiftUI
import SwiftData

struct iPadCollectionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Collection.name) private var collections: [Collection]
    @Binding var selectedCollection: Collection?

    var onImport: () -> Void
    var onCreate: () -> Void

    var body: some View {
        Group {
            if collections.isEmpty {
                ContentUnavailableView(
                    "No Collections",
                    systemImage: "folder.fill",
                    description: Text("Create a collection to organize your trees")
                )
            } else {
                List(selection: $selectedCollection) {
                    ForEach(collections) { collection in
                        CollectionRowView(collection: collection)
                            .tag(collection)
                            .hoverEffect(.highlight)
                            .contextMenu {
                                Button {
                                    selectedCollection = collection
                                } label: {
                                    Label("View Details", systemImage: "info.circle")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    if selectedCollection?.id == collection.id {
                                        selectedCollection = nil
                                    }
                                    modelContext.delete(collection)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete(perform: deleteCollections)
                }
            }
        }
        .navigationTitle("Collections")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onImport()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    onCreate()
                } label: {
                    Label("New Collection", systemImage: "plus")
                }
            }
        }
    }

    private func deleteCollections(at offsets: IndexSet) {
        for index in offsets {
            let collection = collections[index]
            if selectedCollection?.id == collection.id {
                selectedCollection = nil
            }
            modelContext.delete(collection)
        }
    }
}

#Preview {
    NavigationSplitView {
        Text("Sidebar")
    } content: {
        iPadCollectionListView(
            selectedCollection: .constant(nil),
            onImport: {},
            onCreate: {}
        )
    } detail: {
        Text("Detail")
    }
    .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
