import SwiftUI

/// Toolbar menu for narrowing trees by collection and species, and (for
/// lists) choosing the sort order. The icon fills in while a filter is active.
struct TreeFilterMenu: View {
    @Binding var filter: TreeFilter
    var sortOrder: Binding<TreeSortOrder>? = nil
    let collections: [Collection]
    let speciesOptions: [String]

    var body: some View {
        Menu {
            if let sortOrder {
                Picker("Sort By", selection: sortOrder) {
                    ForEach(TreeSortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.menu)
            }

            Picker("Collection", selection: $filter.collection) {
                Text("All Collections").tag(CollectionFilter.all)
                Text("Not in a Collection").tag(CollectionFilter.unassigned)
                ForEach(collections) { collection in
                    Text(collection.name).tag(CollectionFilter.collection(collection.id))
                }
            }
            .pickerStyle(.menu)

            Picker("Species", selection: $filter.species) {
                Text("All Species").tag(nil as String?)
                ForEach(speciesOptions, id: \.self) { species in
                    Text(species).tag(species as String?)
                }
            }
            .pickerStyle(.menu)

            if filter.isActive {
                Divider()
                Button {
                    filter = TreeFilter()
                } label: {
                    Label("Clear Filters", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: filter.isActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(filter.isActive ? "Filter, active" : "Filter")
        .onChange(of: collections.map(\.id)) { _, ids in
            // The filtered collection was deleted; don't leave an empty list
            if case .collection(let id) = filter.collection, !ids.contains(id) {
                filter.collection = .all
            }
        }
    }
}

/// Shown in place of list rows when a search or filter leaves nothing.
struct NoMatchingTreesView: View {
    let searchText: String
    @Binding var filter: TreeFilter

    var body: some View {
        if filter.isActive {
            ContentUnavailableView {
                Label("No Matching Trees", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text(searchText.isEmpty
                     ? "No trees match the current filter."
                     : "No trees match “\(searchText)” with the current filter.")
            } actions: {
                Button("Clear Filters") {
                    filter = TreeFilter()
                }
            }
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }
}
