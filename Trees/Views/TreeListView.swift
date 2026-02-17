import SwiftUI
import SwiftData

struct TreeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tree.createdAt, order: .reverse) private var trees: [Tree]
    @Query(sort: \Collection.name) private var collections: [Collection]
    @State private var searchText = ""
    @State private var showingCaptureSheet = false
    @State private var showingExportSheet = false
    @State private var showingImportSheet = false
    @State private var showingDuplicatesSheet = false

    var filteredTrees: [Tree] {
        if searchText.isEmpty {
            return trees
        }
        return trees.filter { tree in
            tree.species.localizedStandardContains(searchText) ||
            (tree.variety ?? "").localizedStandardContains(searchText) ||
            tree.treeNotes.contains { $0.text.localizedStandardContains(searchText) }
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
                            Divider()
                            Button {
                                showingDuplicatesSheet = true
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
                ExportView(trees: trees, collections: collections)
            }
            .sheet(isPresented: $showingImportSheet) {
                ImportTreesView()
            }
            .sheet(isPresented: $showingDuplicatesSheet) {
                DuplicateTreesView()
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
