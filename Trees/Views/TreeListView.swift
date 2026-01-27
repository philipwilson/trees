import SwiftUI
import SwiftData

struct TreeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tree.createdAt, order: .reverse) private var trees: [Tree]
    @State private var searchText = ""
    @State private var showingCaptureSheet = false
    @State private var showingExportSheet = false
    @State private var showingImportSheet = false

    var filteredTrees: [Tree] {
        if searchText.isEmpty {
            return trees
        }
        return trees.filter { tree in
            tree.species.localizedCaseInsensitiveContains(searchText) ||
            (tree.variety ?? "").localizedCaseInsensitiveContains(searchText) ||
            tree.treeNotes.contains { $0.text.localizedCaseInsensitiveContains(searchText) }
        }
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
                        }
                        .onDelete(perform: deleteTrees)
                    }
                    .searchable(text: $searchText, prompt: "Search species or notes")
                }
            }
            .navigationTitle("Trees")
            .toolbar {
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
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCaptureSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCaptureSheet) {
                CaptureTreeView()
            }
            .sheet(isPresented: $showingExportSheet) {
                ExportView(trees: trees)
            }
            .sheet(isPresented: $showingImportSheet) {
                ImportTreesView()
            }
        }
    }

    private func deleteTrees(at offsets: IndexSet) {
        for index in offsets {
            let tree = filteredTrees[index]
            modelContext.delete(tree)
        }
    }
}

#Preview {
    TreeListView()
        .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
