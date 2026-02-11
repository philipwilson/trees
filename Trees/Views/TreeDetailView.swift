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
    @State private var showingAddNote = false

    // Local editing state - only synced to tree on save
    @State private var editSpecies = ""
    @State private var editVariety = ""
    @State private var editRootstock = ""
    @State private var editCollection: Collection?

    // For adding photos during editing
    @State private var newPhotos: [Data] = []
    @State private var newPhotoDates: [Date?] = []

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
                } else {
                    LabeledContent("Species") {
                        Text(tree.species.isEmpty ? "Not specified" : tree.species)
                            .foregroundStyle(tree.species.isEmpty ? .secondary : .primary)
                    }
                    if let variety = tree.variety, !variety.isEmpty {
                        LabeledContent("Variety") {
                            Text(variety)
                        }
                    }
                    if let rootstock = tree.rootstock, !rootstock.isEmpty {
                        LabeledContent("Rootstock") {
                            Text(rootstock)
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
                    EditablePhotoGalleryView(photos: $newPhotos, photoDates: $newPhotoDates)
                    PhotosPicker(selectedPhotos: $newPhotos, photoDates: $newPhotoDates)
                } else {
                    PhotoGalleryView(photos: tree.treePhotos)
                }
            } header: {
                Text("Photos (\(isEditing ? newPhotos.count + tree.treePhotos.count : tree.treePhotos.count))")
            }

            Section {
                if tree.treeNotes.isEmpty && !isEditing {
                    ContentUnavailableView(
                        "No Notes",
                        systemImage: "note.text",
                        description: Text("Tap Add Note to record observations")
                    )
                } else {
                    ForEach(tree.treeNotes.sorted { $0.createdAt > $1.createdAt }) { note in
                        NoteRowView(note: note)
                    }
                    .onDelete(perform: deleteNotes)
                }

                Button {
                    showingAddNote = true
                } label: {
                    Label("Add Note", systemImage: "plus.circle")
                }
            } header: {
                Text("Notes (\(tree.treeNotes.count))")
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
                        saveEdits()
                    } else {
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
        .sheet(isPresented: $showingAddNote) {
            AddNoteView(tree: tree)
        }
    }

    private func loadEditState() {
        editSpecies = tree.species
        editVariety = tree.variety ?? ""
        editRootstock = tree.rootstock ?? ""
        editCollection = tree.collection
        newPhotos = []
        newPhotoDates = []
    }

    private func saveEdits() {
        tree.species = editSpecies
        tree.variety = editVariety.isEmpty ? nil : editVariety
        tree.rootstock = editRootstock.isEmpty ? nil : editRootstock

        // Update collection timestamps if collection changed
        if tree.collection?.id != editCollection?.id {
            tree.collection?.updatedAt = Date()
            editCollection?.updatedAt = Date()
        }
        tree.collection = editCollection

        // Add new photos as Photo entities
        for (index, photoData) in newPhotos.enumerated() {
            let captureDate = index < newPhotoDates.count ? newPhotoDates[index] : Date()
            tree.addPhoto(photoData, capturedAt: captureDate)
        }

        tree.updatedAt = Date()
        try? modelContext.save()
        newPhotos = []
        newPhotoDates = []
    }

    private func deleteNotes(at offsets: IndexSet) {
        let sortedNotes = tree.treeNotes.sorted { $0.createdAt > $1.createdAt }
        for index in offsets {
            let note = sortedNotes[index]
            tree.removeNote(note)
            modelContext.delete(note)
        }
    }
}

struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(note.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !note.notePhotos.isEmpty {
                    Label("\(note.notePhotos.count)", systemImage: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !note.text.isEmpty {
                Text(note.text)
                    .font(.body)
            }

            if !note.notePhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(note.notePhotos) { photo in
                            if let uiImage = ImageDownsampler.downsample(data: photo.imageData, maxDimension: 60) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddNoteView: View {
    let tree: Tree
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var photos: [Data] = []
    @State private var photoDates: [Date?] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What did you observe?", text: $text, axis: .vertical)
                        .lineLimit(3...10)
                } header: {
                    Text("Note")
                }

                Section {
                    if !photos.isEmpty {
                        EditablePhotoGalleryView(photos: $photos, photoDates: $photoDates)
                    }
                    PhotosPicker(selectedPhotos: $photos, photoDates: $photoDates)
                } header: {
                    Text("Photos")
                }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveNote()
                    }
                    .disabled(text.isEmpty && photos.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func saveNote() {
        let note = tree.addNote(text: text.trimmingCharacters(in: .whitespacesAndNewlines))

        for (index, photoData) in photos.enumerated() {
            let captureDate = index < photoDates.count ? photoDates[index] : Date()
            note.addPhoto(photoData, capturedAt: captureDate)
        }

        dismiss()
    }
}

#Preview {
    NavigationStack {
        TreeDetailView(tree: Tree(
            latitude: 45.123456,
            longitude: -122.654321,
            horizontalAccuracy: 4.5,
            altitude: 150.0,
            species: "Red Maple"
        ))
    }
    .modelContainer(for: [Tree.self, Collection.self, Photo.self, Note.self], inMemory: true)
}
