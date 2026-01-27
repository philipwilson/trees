import SwiftUI
import SwiftData

struct iPadContentView: View {
    @State private var selectedSection: SidebarSection = .trees
    @State private var selectedTree: Tree?
    @State private var selectedCollection: Collection?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingCaptureSheet = false
    @State private var showingExportSheet = false
    @State private var showingImportCollectionSheet = false
    @State private var showingImportTreesSheet = false
    @State private var showingDuplicatesSheet = false
    @State private var showingNewCollectionSheet = false
    @State private var newCollectionName = ""

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tree.createdAt, order: .reverse) private var trees: [Tree]
    @Query(sort: \Collection.name) private var collections: [Collection]

    enum SidebarSection: Hashable {
        case trees
        case collections
        case map
    }

    var body: some View {
        Group {
            if selectedSection == .map {
                iPadMapView(onBack: { selectedSection = .trees })
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    iPadSidebarView(
                        selection: $selectedSection,
                        treeCount: trees.count,
                        collectionCount: collections.count
                    )
                } content: {
                    contentColumn
                } detail: {
                    detailColumn
                }
            }
        }
        .sheet(isPresented: $showingCaptureSheet) {
            CaptureTreeView()
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportView(trees: trees, collections: collections)
        }
        .sheet(isPresented: $showingImportCollectionSheet) {
            ImportCollectionView()
        }
        .sheet(isPresented: $showingImportTreesSheet) {
            ImportTreesView()
        }
        .sheet(isPresented: $showingDuplicatesSheet) {
            DuplicateTreesView()
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
        .keyboardShortcut("n", modifiers: .command) { showingCaptureSheet = true }
        .keyboardShortcut("e", modifiers: .command) { showingExportSheet = true }
        .keyboardShortcut("1", modifiers: .command) { selectedSection = .trees }
        .keyboardShortcut("2", modifiers: .command) { selectedSection = .collections }
        .keyboardShortcut("3", modifiers: .command) { selectedSection = .map }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch selectedSection {
        case .trees:
            iPadTreeListView(
                selectedTree: $selectedTree,
                onCapture: { showingCaptureSheet = true },
                onExport: { showingExportSheet = true },
                onImport: { showingImportTreesSheet = true },
                onFindDuplicates: { showingDuplicatesSheet = true }
            )
        case .collections:
            iPadCollectionListView(
                selectedCollection: $selectedCollection,
                onImport: { showingImportCollectionSheet = true },
                onCreate: {
                    newCollectionName = ""
                    showingNewCollectionSheet = true
                }
            )
        case .map:
            EmptyView()
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let tree = selectedTree, selectedSection == .trees {
            TreeDetailView(tree: tree)
        } else if let collection = selectedCollection, selectedSection == .collections {
            CollectionDetailView(collection: collection)
        } else {
            ContentUnavailableView(
                "Select an Item",
                systemImage: selectedSection == .trees ? "tree.fill" : "folder.fill",
                description: Text(selectedSection == .trees ? "Choose a tree to view its details" : "Choose a collection to view its trees")
            )
        }
    }

    private func createCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let collection = Collection(name: name)
        modelContext.insert(collection)
        selectedCollection = collection
        newCollectionName = ""
    }
}

// Extension to add keyboard shortcuts more easily
extension View {
    func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers, action: @escaping () -> Void) -> some View {
        self.background(
            Button("") { action() }
                .keyboardShortcut(key, modifiers: modifiers)
                .hidden()
        )
    }
}

#Preview {
    iPadContentView()
        .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
