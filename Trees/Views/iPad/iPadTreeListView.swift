import SwiftUI
import SwiftData

struct iPadTreeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tree.createdAt, order: .reverse) private var trees: [Tree]
    @Binding var selectedTree: Tree?
    @State private var searchText = ""

    var onCapture: () -> Void
    var onExport: () -> Void

    var filteredTrees: [Tree] {
        if searchText.isEmpty {
            return trees
        }
        return trees.filter { tree in
            tree.species.localizedCaseInsensitiveContains(searchText) ||
            (tree.variety ?? "").localizedCaseInsensitiveContains(searchText) ||
            tree.notes.localizedCaseInsensitiveContains(searchText)
        }
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

                                if tree.collection != nil {
                                    Button {
                                        tree.collection = nil
                                    } label: {
                                        Label("Remove from Collection", systemImage: "folder.badge.minus")
                                    }
                                }

                                Divider()

                                Button(role: .destructive) {
                                    if selectedTree?.id == tree.id {
                                        selectedTree = nil
                                    }
                                    modelContext.delete(tree)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete(perform: deleteTrees)
                }
                .searchable(text: $searchText, prompt: "Search species or notes")
            }
        }
        .navigationTitle("Trees")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !trees.isEmpty {
                    Button {
                        onExport()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
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

    private func deleteTrees(at offsets: IndexSet) {
        for index in offsets {
            let tree = filteredTrees[index]
            if selectedTree?.id == tree.id {
                selectedTree = nil
            }
            modelContext.delete(tree)
        }
    }
}

#Preview {
    NavigationSplitView {
        Text("Sidebar")
    } content: {
        iPadTreeListView(
            selectedTree: .constant(nil),
            onCapture: {},
            onExport: {}
        )
    } detail: {
        Text("Detail")
    }
    .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
