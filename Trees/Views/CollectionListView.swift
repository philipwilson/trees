import SwiftUI
import SwiftData

struct CollectionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Collection.name) private var collections: [Collection]
    @State private var showingNewCollectionSheet = false
    @State private var newCollectionName = ""
    @State private var showingImportSheet = false
    @State private var pendingDeletion = PendingDeletion<Collection>()

    var body: some View {
        NavigationStack {
            Group {
                if collections.isEmpty {
                    ContentUnavailableView(
                        "No Collections",
                        systemImage: "folder.fill",
                        description: Text("Create a collection to organize your trees")
                    )
                } else {
                    List {
                        ForEach(collections) { collection in
                            NavigationLink(destination: CollectionDetailView(collection: collection)) {
                                CollectionRowView(collection: collection)
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
                        showingImportSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .accessibilityLabel("Import Collection")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newCollectionName = ""
                        showingNewCollectionSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("New Collection")
                    }
                }
            }
            .alert("New Collection", isPresented: $showingNewCollectionSheet) {
                TextField("Collection Name", text: $newCollectionName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    createCollection()
                }
                .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("Enter a name for your new collection")
            }
            .sheet(isPresented: $showingImportSheet) {
                ImportCollectionView()
            }
            .deleteConfirmation(
                $pendingDeletion,
                title: Collection.deletionTitle(for:),
                message: Collection.deletionMessage
            ) { collections in
                for collection in collections {
                    modelContext.delete(collection)
                }
            }
        }
    }

    private func createCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let collection = Collection(name: name)
        modelContext.insert(collection)
        newCollectionName = ""
    }

    private func deleteCollections(at offsets: IndexSet) {
        pendingDeletion.request(offsets.map { collections[$0] })
    }
}

struct CollectionRowView: View {
    let collection: Collection

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(.orange)
                .font(.title2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name)
                    .font(.headline)
                Text("\(collection.treeCount) trees")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
    }
}

#Preview {
    CollectionListView()
        .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
