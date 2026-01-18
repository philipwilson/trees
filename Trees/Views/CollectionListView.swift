import SwiftUI
import SwiftData

struct CollectionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Collection.name) private var collections: [Collection]
    @State private var showingNewCollectionSheet = false
    @State private var newCollectionName = ""
    @State private var showingImportSheet = false

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
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newCollectionName = ""
                        showingNewCollectionSheet = true
                    } label: {
                        Image(systemName: "plus")
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
        for index in offsets {
            let collection = collections[index]
            modelContext.delete(collection)
        }
    }
}

struct CollectionRowView: View {
    let collection: Collection

    var body: some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(.orange)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name)
                    .font(.headline)
                Text("\(collection.treeCount) trees")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    CollectionListView()
        .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
