import SwiftUI
import SwiftData

struct DuplicateTreesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tree.createdAt, order: .reverse) private var trees: [Tree]

    @State private var duplicateGroups: [[Tree]] = []
    @State private var selectedForDeletion: Set<PersistentIdentifier> = []
    @State private var showingDeleteConfirmation = false

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
                            Text("Found \(duplicateGroups.count) group\(duplicateGroups.count == 1 ? "" : "s") of duplicate trees. Select which copies to delete.")
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

                    VStack(alignment: .leading, spacing: 4) {
                        Text(tree.species.isEmpty ? "Unknown Species" : tree.species)
                            .font(.headline)
                        if let variety = tree.variety, !variety.isEmpty {
                            Text(variety)
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

                    if let photo = tree.treePhotos.first,
                       let uiImage = ImageDownsampler.downsample(data: photo.imageData, maxDimension: 50) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
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
        for tree in trees where selectedForDeletion.contains(tree.persistentModelID) {
            modelContext.delete(tree)
        }
        selectedForDeletion.removeAll()
        findDuplicates()
    }

    private func findDuplicates() {
        // Group trees by rounded coordinates + species
        // Using 4 decimal places (~11 meter precision) to account for GPS accuracy
        var groups: [String: [Tree]] = [:]

        for tree in trees {
            let key = String(format: "%.4f,%.4f,%@",
                           tree.latitude,
                           tree.longitude,
                           tree.species.lowercased().trimmingCharacters(in: .whitespaces))
            groups[key, default: []].append(tree)
        }

        // Only keep groups with more than one tree (duplicates)
        duplicateGroups = groups.values
            .filter { $0.count > 1 }
            .sorted { ($0.first?.species ?? "") < ($1.first?.species ?? "") }
    }
}

#Preview {
    DuplicateTreesView()
        .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
