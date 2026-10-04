import SwiftUI
import SwiftData

struct TreeListView: View {
    @Environment(PhotoViewerState.self) private var photoViewerState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tree.createdAt, order: .reverse) private var trees: [Tree]
    @Query(sort: \Collection.name) private var collections: [Collection]
    @State private var searchText = ""
    /// Trails `searchText` by a short pause so filtering (which reads every
    /// tree's notes) doesn't run on each keystroke
    @State private var activeSearchText = ""
    @State private var showingCaptureSheet = false
    @State private var showingExportSheet = false
    @State private var showingImportSheet = false
    @State private var showingDuplicatesSheet = false
    @State private var pendingDeletion = PendingDeletion<Tree>()
    @State private var filter = TreeFilter()
    @AppStorage("treeSortOrder") private var sortOrder: TreeSortOrder = .newest

    var filteredTrees: [Tree] {
        filter.apply(to: trees, searchText: activeSearchText, sortOrder: sortOrder)
    }

    var body: some View {
        NavigationStack {
            Group {
                if trees.isEmpty {
                    ContentUnavailableView(
                        "No Trees Yet",
                        systemImage: "tree.fill",
                        description: Text("Tap the + button to capture your first tree location")
                    )
                } else {
                    List {
                        ForEach(filteredTrees) { tree in
                            NavigationLink(destination: TreeDetailView(tree: tree)) {
                                TreeRowView(tree: tree)
                            }
                            .contextMenu {
                                MoveToCollectionMenu(tree: tree)
                                Divider()
                                Button(role: .destructive) {
                                    pendingDeletion.request([tree])
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete(perform: deleteTrees)
                    }
                    .overlay {
                        if filteredTrees.isEmpty {
                            NoMatchingTreesView(searchText: activeSearchText, filter: $filter)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Species, notes, collection, date")
                    .task(id: searchText) {
                        await debounceSearch()
                    }
                }
            }
            .navigationTitle("Trees")
            .toolbar {
                if !photoViewerState.isPresented {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button {
                                showingImportSheet = true
                            } label: {
                                Label("Import", systemImage: "square.and.arrow.down")
                            }
                            if !trees.isEmpty {
                                Button {
                                    showingExportSheet = true
                                } label: {
                                    Label("Export", systemImage: "square.and.arrow.up")
                                }
                                Divider()
                                Button {
                                    showingDuplicatesSheet = true
                                } label: {
                                    Label("Find Duplicates", systemImage: "doc.on.doc")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .accessibilityLabel("More")
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        SyncStatusButton()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if !trees.isEmpty {
                            TreeFilterMenu(
                                filter: $filter,
                                sortOrder: $sortOrder,
                                collections: collections,
                                speciesOptions: TreeFilter.speciesOptions(in: trees)
                            )
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingCaptureSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .accessibilityLabel("Capture Tree")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCaptureSheet) {
                CaptureTreeView()
            }
            .sheet(isPresented: $showingExportSheet) {
                ExportView(trees: trees, collections: collections)
            }
            .sheet(isPresented: $showingImportSheet) {
                ImportTreesView()
            }
            .sheet(isPresented: $showingDuplicatesSheet) {
                DuplicateTreesView()
            }
            .deleteConfirmation(
                $pendingDeletion,
                title: Tree.deletionTitle(for:),
                message: Tree.deletionMessage
            ) { trees in
                for tree in trees {
                    modelContext.delete(tree)
                }
            }
        }
    }

    private func debounceSearch() async {
        if searchText.isEmpty {
            activeSearchText = ""
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(250))
            activeSearchText = searchText
        } catch {
            // Superseded by a newer keystroke
        }
    }

    private func deleteTrees(at offsets: IndexSet) {
        let visible = filteredTrees
        pendingDeletion.request(offsets.map { visible[$0] })
    }
}

#Preview {
    TreeListView()
        .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
