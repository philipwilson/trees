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

    var onCapture: () -> Void
    var onExport: () -> Void
    var onImport: () -> Void
    var onFindDuplicates: () -> Void

    var filteredTrees: [Tree] {
        if activeSearchText.isEmpty {
            return trees
        }
        return trees.filter { $0.matches(searchText: activeSearchText) }
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
                .searchable(text: $searchText, prompt: "Search species or notes")
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
                    } label: {
                        Image(systemName: "ellipsis.circle")
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
