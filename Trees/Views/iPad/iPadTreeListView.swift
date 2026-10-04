import SwiftUI
import SwiftData

struct iPadTreeListView: View {
    @Environment(PhotoViewerState.self) private var photoViewerState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tree.createdAt, order: .reverse) private var trees: [Tree]
    @Binding var selectedTree: Tree?
    @State private var searchText = ""
    /// Trails `searchText` by a short pause so filtering (which reads every
    /// tree's notes) doesn't run on each keystroke
    @State private var activeSearchText = ""
    @State private var pendingDeletion = PendingDeletion<Tree>()
    @State private var showingAbout = false
    @Query(sort: \Collection.name) private var collections: [Collection]
    @State private var filter = TreeFilter()
    @AppStorage("treeSortOrder") private var sortOrder: TreeSortOrder = .newest

    var onCapture: () -> Void
    var onExport: () -> Void
    var onImport: () -> Void
    var onFindDuplicates: () -> Void

    var filteredTrees: [Tree] {
        filter.apply(to: trees, searchText: activeSearchText, sortOrder: sortOrder)
    }

    var body: some View {
        Group {
            if trees.isEmpty {
                ContentUnavailableView(
                    "No Trees Yet",
                    systemImage: "tree.fill",
                    description: Text("Tap the + button to capture your first tree location")
                )
            } else {
                List(selection: $selectedTree) {
                    ForEach(filteredTrees) { tree in
                        TreeRowView(tree: tree)
                            .tag(tree)
                            .hoverEffect(.highlight)
                            .contextMenu {
                                Button {
                                    selectedTree = tree
                                } label: {
                                    Label("View Details", systemImage: "info.circle")
                                }

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
        .deleteConfirmation(
            $pendingDeletion,
            title: Tree.deletionTitle(for:),
            message: Tree.deletionMessage
        ) { trees in
            for tree in trees {
                if selectedTree?.id == tree.id {
                    selectedTree = nil
                }
                modelContext.delete(tree)
            }
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .navigationTitle("Trees")
        .toolbar {
            if !photoViewerState.isPresented {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            onImport()
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                        if !trees.isEmpty {
                            Button {
                                onExport()
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                            Button {
                                onFindDuplicates()
                            } label: {
                                Label("Find Duplicates", systemImage: "doc.on.doc")
                            }
                        }
                        Divider()
                        Button {
                            showingAbout = true
                        } label: {
                            Label("About Tree Tracker", systemImage: "info.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("More")
                    }
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
                        onCapture()
                    } label: {
                        Label("Capture Tree", systemImage: "plus")
                    }
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
    NavigationSplitView {
        Text("Sidebar")
    } content: {
        iPadTreeListView(
            selectedTree: .constant(nil),
            onCapture: {},
            onExport: {},
            onImport: {},
            onFindDuplicates: {}
        )
    } detail: {
        Text("Detail")
    }
    .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
