import SwiftUI
import SwiftData
import MapKit

struct TreeDetailView: View {
    @Bindable var tree: Tree
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Collection.name) private var collections: [Collection]
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false

    // Local editing state - only synced to tree on save
    @State private var editSpecies = ""
    @State private var editVariety = ""
    @State private var editRootstock = ""
    @State private var editNotes = ""
    @State private var editCollection: Collection?
    @State private var editPhotos: [Data] = []
    @State private var editPhotoDates: [Date]? = []

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: tree.latitude, longitude: tree.longitude)
    }

    var body: some View {
        List {
            Section {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                ))) {
                    Marker(tree.species.isEmpty ? "Tree" : tree.species, coordinate: coordinate)
                        .tint(.green)
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("Latitude") {
                    Text(String(format: "%.6f", tree.latitude))
                        .textSelection(.enabled)
                }
                LabeledContent("Longitude") {
                    Text(String(format: "%.6f", tree.longitude))
                        .textSelection(.enabled)
                }
                LabeledContent("Accuracy") {
                    AccuracyBadge(accuracy: tree.horizontalAccuracy)
                }
                if let altitude = tree.altitude {
                    LabeledContent("Altitude") {
                        Text(String(format: "%.1f m", altitude))
                    }
                }
            } header: {
                Text("Location")
            }

            Section {
                if isEditing {
                    SpeciesTextField(text: $editSpecies)
                    TextField("Variety", text: $editVariety)
                    TextField("Rootstock", text: $editRootstock)
                    TextField("Notes", text: $editNotes, axis: .vertical)
                        .lineLimit(3...10)
                } else {
                    LabeledContent("Species") {
                        Text(tree.species.isEmpty ? "Not specified" : tree.species)
                            .foregroundStyle(tree.species.isEmpty ? .secondary : .primary)
                    }
                    if let variety = tree.variety {
                        LabeledContent("Variety") {
                            Text(variety)
                        }
                    }
                    if let rootstock = tree.rootstock {
                        LabeledContent("Rootstock") {
                            Text(rootstock)
                        }
                    }
                    if !tree.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(tree.notes)
                        }
                    }
                }
            } header: {
                Text("Details")
            }

            Section {
                if isEditing {
                    Picker("Collection", selection: $editCollection) {
                        Text("None").tag(nil as Collection?)
                        ForEach(collections) { collection in
                            Text(collection.name).tag(collection as Collection?)
                        }
                    }
                } else {
                    LabeledContent("Collection") {
                        Text(tree.collection?.name ?? "None")
                            .foregroundStyle(tree.collection == nil ? .secondary : .primary)
                    }
                }
            } header: {
                Text("Collection")
            }

            Section {
                if isEditing {
                    EditablePhotoGalleryView(photos: $editPhotos, photoDates: $editPhotoDates)
                    PhotosPicker(selectedPhotos: $editPhotos, photoDates: $editPhotoDates)
                } else {
                    PhotoGalleryView(photos: tree.photos, photoDates: tree.photoDates)
                }
            } header: {
                Text("Photos (\(isEditing ? editPhotos.count : tree.photos.count))")
            }

            Section {
                LabeledContent("Created") {
                    Text(tree.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Updated") {
                    Text(tree.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            } header: {
                Text("Timestamps")
            }

            if isEditing {
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Tree")
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(tree.species.isEmpty ? "Tree Details" : tree.species)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        // Save local state back to tree
                        saveEdits()
                    } else {
                        // Load tree data into local state
                        loadEditState()
                    }
                    isEditing.toggle()
                }
            }
        }
        .confirmationDialog("Delete Tree", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(tree)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func loadEditState() {
        editSpecies = tree.species
        editVariety = tree.variety ?? ""
        editRootstock = tree.rootstock ?? ""
        editNotes = tree.notes
        editCollection = tree.collection
        editPhotos = tree.photos
        editPhotoDates = tree.photoDates
    }

    private func saveEdits() {
        tree.species = editSpecies
        tree.variety = editVariety.isEmpty ? nil : editVariety
        tree.rootstock = editRootstock.isEmpty ? nil : editRootstock
        tree.notes = editNotes
        tree.collection = editCollection
        tree.photos = editPhotos
        tree.photoDates = editPhotoDates
        tree.updatedAt = Date()
    }
}

#Preview {
    NavigationStack {
        TreeDetailView(tree: Tree(
            latitude: 45.123456,
            longitude: -122.654321,
            horizontalAccuracy: 4.5,
            altitude: 150.0,
            species: "Red Maple",
            notes: "Large tree near the parking lot. Has distinctive red leaves in autumn."
        ))
    }
    .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
