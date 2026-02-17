import SwiftUI
import SwiftData

struct CollectionDetailView: View {
    @Bindable var collection: Collection
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tree.createdAt, order: .reverse) private var allTrees: [Tree]

    @State private var isEditing = false
    @State private var showingExportSheet = false
    @State private var showingAddTreesSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingCaptureSheet = false

    // Local editing state to avoid lag from SwiftData updates on every keystroke
    @State private var editName = ""

    private var unassignedTrees: [Tree] {
        allTrees.filter { $0.collection == nil }
    }

    private var collectionTrees: [Tree] {
        collection.trees ?? []
    }

    var body: some View {
        List {
            Section {
                if isEditing {
                    TextField("Collection Name", text: $editName)
                } else {
                    LabeledContent("Name") {
                        Text(collection.name)
                    }
                }
                LabeledContent("Trees") {
                    Text("\(collection.treeCount)")
                }
                LabeledContent("Created") {
                    Text(collection.formattedDate)
                }
            } header: {
                Text("Collection Info")
            }

            Section {
                if collectionTrees.isEmpty {
                    ContentUnavailableView(
                        "No Trees",
                        systemImage: "tree",
                        description: Text("Add trees to this collection")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(collectionTrees.sorted { $0.createdAt > $1.createdAt }) { tree in
                        NavigationLink(destination: TreeDetailView(tree: tree)) {
                            TreeRowView(tree: tree)
                        }
                    }
                    .onDelete(perform: removeTreesFromCollection)
                }
            } header: {
                HStack {
                    Text("Trees")
                    Spacer()
                    if !collectionTrees.isEmpty {
                        Button {
                            showingAddTreesSheet = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                    }
                }
            }

            if collectionTrees.isEmpty {
                Section {
                    Button {
                        showingCaptureSheet = true
                    } label: {
                        Label("Capture New Tree", systemImage: "location.fill")
                    }

                    Button {
                        showingAddTreesSheet = true
                    } label: {
                        Label("Add Existing Trees", systemImage: "plus.circle")
                    }
                    .disabled(unassignedTrees.isEmpty)
                }
            }

            if isEditing {
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Collection")
                            Spacer()
                        }
                    }
                } footer: {
                    Text("Trees in this collection will not be deleted.")
                }
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        if isEditing {
                            // Save local state back to collection
                            collection.name = editName
                            collection.updatedAt = Date()
                        } else {
                            // Load collection data into local state
                            editName = collection.name
                        }
                        isEditing.toggle()
                    } label: {
                        Label(isEditing ? "Done Editing" : "Edit", systemImage: "pencil")
                    }

                    Button {
                        showingExportSheet = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(collectionTrees.isEmpty)

                    Button {
                        showingCaptureSheet = true
                    } label: {
                        Label("Capture Tree", systemImage: "location.fill")
                    }

                    Button {
                        showingAddTreesSheet = true
                    } label: {
                        Label("Add Existing Trees", systemImage: "plus.circle")
                    }
                    .disabled(unassignedTrees.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportView(trees: collectionTrees, collectionName: collection.name)
        }
        .sheet(isPresented: $showingAddTreesSheet) {
            AddTreesToCollectionView(collection: collection, availableTrees: unassignedTrees)
        }
        .sheet(isPresented: $showingCaptureSheet) {
            CaptureTreeView(preselectedCollection: collection)
        }
        .confirmationDialog("Delete Collection", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(collection)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete the collection but keep all trees.")
        }
    }

    private func removeTreesFromCollection(at offsets: IndexSet) {
        let sortedTrees = collectionTrees.sorted { $0.createdAt > $1.createdAt }
        for index in offsets {
            sortedTrees[index].collection = nil
            sortedTrees[index].updatedAt = Date()
        }
        collection.updatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            print("Failed to remove trees from collection \(collection.id): \(error)")
        }
    }
}

struct AddTreesToCollectionView: View {
    let collection: Collection
    let availableTrees: [Tree]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTrees: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List(availableTrees, selection: $selectedTrees) { tree in
                TreeRowView(tree: tree)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Add Trees")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedTrees.count))") {
                        addSelectedTrees()
                    }
                    .disabled(selectedTrees.isEmpty)
                }
            }
        }
    }

    private func addSelectedTrees() {
        for tree in availableTrees where selectedTrees.contains(tree.id) {
            tree.collection = collection
            tree.updatedAt = Date()
        }
        collection.updatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            print("Failed to add trees to collection \(collection.id): \(error)")
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        CollectionDetailView(collection: Collection(name: "Victoria's Orchard"))
    }
    .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
