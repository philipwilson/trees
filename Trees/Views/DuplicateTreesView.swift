import SwiftUI
import SwiftData
import CoreLocation

struct DuplicateTreesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tree.createdAt, order: .reverse) private var trees: [Tree]

    @State private var duplicateGroups: [[Tree]] = []
    @State private var selectedForDeletion: Set<PersistentIdentifier> = []
    @State private var showingDeleteConfirmation = false
    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if duplicateGroups.isEmpty {
                    ContentUnavailableView(
                        "No Duplicates Found",
                        systemImage: "checkmark.circle",
                        description: Text("All trees appear to be unique")
                    )
                } else {
                    List {
                        Section {
                            Text("Found \(duplicateGroups.count) group\(duplicateGroups.count == 1 ? "" : "s") of possible duplicates: same species, within \(Int(Self.duplicateDistanceMeters)) m, captured minutes apart. Check each before selecting copies to delete.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(duplicateGroups, id: \.first?.id) { group in
                            duplicateGroupSection(group)
                        }
                    }
                }
            }
            .navigationTitle("Duplicate Trees")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !duplicateGroups.isEmpty {
                        Menu {
                            Button {
                                selectAllButOldest()
                            } label: {
                                Label("Keep Oldest", systemImage: "clock")
                            }
                            Button {
                                selectAllButNewest()
                            } label: {
                                Label("Keep Newest", systemImage: "clock.fill")
                            }
                            Button {
                                selectedForDeletion.removeAll()
                            } label: {
                                Label("Clear Selection", systemImage: "xmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .accessibilityLabel("Selection Options")
                        }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if !selectedForDeletion.isEmpty {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Text("Delete \(selectedForDeletion.count) Selected")
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete \(selectedForDeletion.count) tree\(selectedForDeletion.count == 1 ? "" : "s")?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteSelected()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
            .alert("Delete Failed", isPresented: Binding(get: { saveErrorMessage != nil }, set: { if !$0 { saveErrorMessage = nil } })) {
                Button("OK") { saveErrorMessage = nil }
            } message: {
                if let msg = saveErrorMessage { Text(msg) }
            }
            .onAppear {
                findDuplicates()
            }
        }
    }

    @ViewBuilder
    private func duplicateGroupSection(_ group: [Tree]) -> some View {
        Section {
            ForEach(group) { tree in
                HStack {
                    Button {
                        toggleSelection(tree)
                    } label: {
                        Image(systemName: selectedForDeletion.contains(tree.persistentModelID) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedForDeletion.contains(tree.persistentModelID) ? .red : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(selectedForDeletion.contains(tree.persistentModelID) ? "Selected for deletion" : "Not selected")
                    .accessibilityHint("Toggles whether this copy will be deleted")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(tree.species.isEmpty ? "Unknown Species" : tree.species)
                            .font(.headline)
                        if let detail = tree.varietyAndLabel {
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("Created: \(tree.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("\(tree.treePhotos.count) photo\(tree.treePhotos.count == 1 ? "" : "s"), \(tree.treeNotes.count) note\(tree.treeNotes.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if let photo = tree.treePhotos.first {
                        PhotoThumbnail(photo: photo, maxDimension: 50)
                            .accessibilityHidden(true)
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleSelection(tree)
                }
            }
        } header: {
            Text("\(group.first?.species ?? "Unknown") at \(formatCoordinate(group.first))")
                .font(.caption)
        }
    }

    private func formatCoordinate(_ tree: Tree?) -> String {
        guard let tree = tree else { return "" }
        return String(format: "%.4f, %.4f", tree.latitude, tree.longitude)
    }

    private func toggleSelection(_ tree: Tree) {
        let identity = tree.persistentModelID
        if selectedForDeletion.contains(identity) {
            selectedForDeletion.remove(identity)
        } else {
            selectedForDeletion.insert(identity)
        }
    }

    private func selectAllButOldest() {
        selectedForDeletion.removeAll()
        for group in duplicateGroups {
            let sorted = group.sorted { $0.createdAt < $1.createdAt }
            // Keep the oldest (first), select the rest for deletion
            for tree in sorted.dropFirst() {
                selectedForDeletion.insert(tree.persistentModelID)
            }
        }
    }

    private func selectAllButNewest() {
        selectedForDeletion.removeAll()
        for group in duplicateGroups {
            let sorted = group.sorted { $0.createdAt > $1.createdAt }
            // Keep the newest (first), select the rest for deletion
            for tree in sorted.dropFirst() {
                selectedForDeletion.insert(tree.persistentModelID)
            }
        }
    }

    private func deleteSelected() {
        let deletedIDs = selectedForDeletion
        for tree in trees where deletedIDs.contains(tree.persistentModelID) {
            modelContext.delete(tree)
        }
        selectedForDeletion.removeAll()

        do {
            try modelContext.save()
        } catch {
            print("Failed to delete duplicate trees: \(error)")
            modelContext.rollback()
            saveErrorMessage = "Could not delete the selected trees. Please try again."
            return
        }

        // The @Query result still holds the deleted trees until the next view
        // update, so exclude them explicitly rather than regrouping stale models.
        duplicateGroups = Self.duplicateGroups(in: trees.filter { !deletedIDs.contains($0.persistentModelID) })
    }

    private func findDuplicates() {
        duplicateGroups = Self.duplicateGroups(in: trees)
    }

    /// Two captures of the same tree rarely share coordinates exactly: GPS
    /// drifts a metre or two between fixes. This is kept below typical
    /// planting distances so neighbouring trees in a row aren't flagged.
    static let duplicateDistanceMeters: CLLocationDistance = 2
    static let duplicateTimeWindow: TimeInterval = 300 // 5 minutes

    /// Finds trees that are likely the same tree recorded more than once
    /// (double-captures, sync or import copies) rather than neighbours:
    /// - same species (ignoring case and surrounding spaces)
    /// - varieties and labels don't contradict each other (both set and different)
    /// - within `duplicateDistanceMeters` of another tree in the group
    /// - created within `duplicateTimeWindow` of the previous tree in the group
    static func duplicateGroups(in trees: [Tree]) -> [[Tree]] {
        func normalized(_ text: String?) -> String {
            (text ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        }
        func location(_ tree: Tree) -> CLLocation {
            CLLocation(latitude: tree.latitude, longitude: tree.longitude)
        }
        /// Two values contradict each other only if both are set and differ
        func compatible(_ lhs: String?, _ rhs: String?) -> Bool {
            let left = normalized(lhs), right = normalized(rhs)
            return left.isEmpty || right.isEmpty || left == right
        }
        func varietiesCompatible(_ lhs: Tree, _ rhs: Tree) -> Bool {
            // Different labels mean the user has told these apart on purpose
            compatible(lhs.variety, rhs.variety) && compatible(lhs.label, rhs.label)
        }

        var result: [[Tree]] = []

        for sameSpecies in Dictionary(grouping: trees, by: { normalized($0.species) }).values where sameSpecies.count > 1 {
            var clusters: [[Tree]] = []

            for tree in sameSpecies.sorted(by: { $0.createdAt < $1.createdAt }) {
                let treeLocation = location(tree)
                let match = clusters.firstIndex { cluster in
                    guard let latest = cluster.last,
                          tree.createdAt.timeIntervalSince(latest.createdAt) <= duplicateTimeWindow else { return false }
                    return cluster.contains { member in
                        varietiesCompatible(member, tree) &&
                        location(member).distance(from: treeLocation) <= duplicateDistanceMeters
                    }
                }
                if let match {
                    clusters[match].append(tree)
                } else {
                    clusters.append([tree])
                }
            }

            result.append(contentsOf: clusters.filter { $0.count > 1 })
        }

        return result.sorted { ($0.first?.species ?? "") < ($1.first?.species ?? "") }
    }
}

#Preview {
    DuplicateTreesView()
        .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
