import SwiftUI
import SwiftData
import MapKit

struct TreeDetailView: View {
    @Bindable var tree: Tree
    /// Called after the tree is deleted. Needed on iPad, where this view is a
    /// split-view column and dismiss() can't clear the stale selection.
    var onDelete: (() -> Void)? = nil
    @Environment(PhotoViewerState.self) private var photoViewerState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Collection.name) private var collections: [Collection]
    @FocusState private var focusedField: EditableField?
    @State private var showingDeleteConfirmation = false
    @State private var showingAddNote = false
    @State private var noteBeingEdited: Note?
    @State private var showingUpdateLocation = false
    @State private var saveErrorMessage: String?

    @State private var newPhotos: [CapturedPhoto] = []
    /// The text field values as of the last save, tagged with their tree
    /// because iPad reuses this view when the selection changes
    @State private var committedFields: (treeID: UUID, values: FieldValues)?

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: tree.latitude, longitude: tree.longitude)
    }

    private var varietyBinding: Binding<String> {
        Binding(
            get: { tree.variety ?? "" },
            set: { tree.variety = $0.isEmpty ? nil : $0 }
        )
    }

    private var labelBinding: Binding<String> {
        Binding(
            get: { tree.label ?? "" },
            set: { tree.label = $0.isEmpty ? nil : $0 }
        )
    }

    private var rootstockBinding: Binding<String> {
        Binding(
            get: { tree.rootstock ?? "" },
            set: { tree.rootstock = $0.isEmpty ? nil : $0 }
        )
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
                // initialPosition is read once, so rebuild the map when the
                // tree's position is updated
                .id("\(tree.latitude),\(tree.longitude)")
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                SpeciesTextField(
                    text: $tree.species,
                    onFocusLost: { commitFieldEdit() }
                )
                .onSubmit { focusedField = .variety }

                InlineEditableField(
                    label: "Variety",
                    placeholder: "Not specified",
                    value: varietyBinding,
                    focusedField: $focusedField,
                    field: .variety,
                    nextField: .rootstock
                )

                InlineEditableField(
                    label: "Rootstock",
                    placeholder: "Not specified",
                    value: rootstockBinding,
                    focusedField: $focusedField,
                    field: .rootstock,
                    nextField: .label
                )

                InlineEditableField(
                    label: "Label",
                    placeholder: "e.g. Row 3, bush 4",
                    value: labelBinding,
                    focusedField: $focusedField,
                    field: .label,
                    nextField: nil
                )
            } header: {
                Text("Details")
            } footer: {
                Text("A label is your own name or tag for telling this plant apart from its neighbours.")
            }

            Section {
                Picker("Collection", selection: $tree.collection) {
                    Text("None").tag(nil as Collection?)
                    ForEach(collections) { collection in
                        Text(collection.name).tag(collection as Collection?)
                    }
                }
            } header: {
                Text("Collection")
            }

            Section {
                PhotoGalleryView(photos: tree.treePhotos)
                PhotosPicker(capturedPhotos: $newPhotos)
            } header: {
                Text("Photos (\(tree.treePhotos.count))")
            }

            Section {
                if tree.treeNotes.isEmpty {
                    ContentUnavailableView(
                        "No Notes",
                        systemImage: "note.text",
                        description: Text("Tap Add Note to record observations")
                    )
                } else {
                    ForEach(tree.treeNotes.sorted { $0.createdAt > $1.createdAt }) { note in
                        NoteRowView(note: note)
                            .swipeActions(edge: .leading) {
                                Button {
                                    noteBeingEdited = note
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button {
                                    noteBeingEdited = note
                                } label: {
                                    Label("Edit Note", systemImage: "pencil")
                                }
                            }
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
                Button {
                    let placemark = MKPlacemark(coordinate: coordinate)
                    let mapItem = MKMapItem(placemark: placemark)
                    mapItem.name = tree.species.isEmpty ? "Tree" : tree.species
                    mapItem.openInMaps(launchOptions: [
                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
                    ])
                } label: {
                    Label("Get Directions", systemImage: "arrow.triangle.turn.up.right.circle")
                }
                Button {
                    showingUpdateLocation = true
                } label: {
                    Label("Update Location", systemImage: "location.circle")
                }
            } header: {
                Text("Location")
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
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(tree.species.isEmpty ? "Tree Details" : tree.species)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !photoViewerState.isPresented {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .accessibilityLabel("Delete Tree")
                    }
                }
            }
        }
        .task(id: tree.id) {
            committedFields = (tree.id, FieldValues(species: tree.species, variety: tree.variety, rootstock: tree.rootstock, label: tree.label))
        }
        .onChange(of: focusedField) { oldField, _ in
            if oldField != nil {
                commitFieldEdit()
            }
        }
        .onChange(of: newPhotos.count) { _, count in
            guard count > 0 else { return }
            for photo in newPhotos {
                tree.addPhoto(photo.data, capturedAt: photo.captureDate)
            }
            newPhotos = []
            tree.updatedAt = Date()
            saveContext()
        }
        .onChange(of: tree.collection) { oldCollection, newCollection in
            if oldCollection?.id != newCollection?.id {
                oldCollection?.updatedAt = Date()
                newCollection?.updatedAt = Date()
                tree.updatedAt = Date()
                saveContext()
            }
        }
        .alert("Save Failed", isPresented: Binding(get: { saveErrorMessage != nil }, set: { if !$0 { saveErrorMessage = nil } })) {
            Button("OK") { saveErrorMessage = nil }
        } message: {
            if let msg = saveErrorMessage { Text(msg) }
        }
        .confirmationDialog("Delete Tree", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(tree)
                onDelete?()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(isPresented: $showingAddNote) {
            AddNoteView(tree: tree)
        }
        .sheet(item: $noteBeingEdited) { note in
            AddNoteView(tree: tree, editing: note)
        }
        .sheet(isPresented: $showingUpdateLocation) {
            UpdateLocationView(tree: tree)
        }
    }

    private func commitFieldEdit() {
        tree.species = tree.species.trimmingCharacters(in: .whitespacesAndNewlines)
        if let variety = tree.variety {
            let trimmed = variety.trimmingCharacters(in: .whitespacesAndNewlines)
            tree.variety = trimmed.isEmpty ? nil : trimmed
        }
        if let rootstock = tree.rootstock {
            let trimmed = rootstock.trimmingCharacters(in: .whitespacesAndNewlines)
            tree.rootstock = trimmed.isEmpty ? nil : trimmed
        }
        if let label = tree.label {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            tree.label = trimmed.isEmpty ? nil : trimmed
        }

        // Focus moving between fields calls this even when nothing was typed;
        // only stamp and save (and so trigger a sync) for a real change.
        let current = FieldValues(species: tree.species, variety: tree.variety, rootstock: tree.rootstock, label: tree.label)
        if let committed = committedFields, committed.treeID == tree.id, committed.values == current {
            return
        }
        tree.updatedAt = Date()
        if saveContext() {
            committedFields = (tree.id, current)
        }
    }

    private struct FieldValues: Equatable {
        let species: String
        let variety: String?
        let rootstock: String?
        let label: String?
    }

    @discardableResult
    private func saveContext() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            saveErrorMessage = "Could not save changes. Please try again."
            print("Failed to save tree edits for \(tree.id): \(error)")
            return false
        }
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
    @State private var viewerRequest: PhotoViewerRequest?

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
                        .accessibilityLabel("\(note.notePhotos.count) photo\(note.notePhotos.count == 1 ? "" : "s")")
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
                            PhotoThumbnail(photo: photo, maxDimension: 60)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .onTapGesture {
                                    viewerRequest = PhotoViewerRequest(id: photo.id)
                                }
                                .accessibilityLabel("Note photo")
                                .accessibilityHint("Opens the photo full screen")
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .fullScreenCover(item: $viewerRequest) { request in
            PhotoDetailView(photos: note.notePhotos, initialPhotoID: request.id)
        }
    }
}

/// Adds a note to a tree, or edits an existing one when `editing` is set.
struct AddNoteView: View {
    let tree: Tree
    let editing: Note?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var capturedPhotos: [CapturedPhoto] = []
    @State private var showingSaveError = false

    init(tree: Tree, editing: Note? = nil) {
        self.tree = tree
        self.editing = editing
        _text = State(initialValue: editing?.text ?? "")
    }

    private var existingPhotos: [Photo] {
        editing?.notePhotos ?? []
    }

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
                    if !existingPhotos.isEmpty {
                        PhotoGalleryView(photos: existingPhotos)
                    }
                    if !capturedPhotos.isEmpty {
                        EditablePhotoGalleryView(capturedPhotos: $capturedPhotos)
                    }
                    PhotosPicker(capturedPhotos: $capturedPhotos)
                } header: {
                    Text("Photos")
                } footer: {
                    if !existingPhotos.isEmpty {
                        Text("Tap a photo to view or delete it.")
                    }
                }
            }
            .navigationTitle(editing == nil ? "Add Note" : "Edit Note")
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
                    .disabled(trimmedText.isEmpty && capturedPhotos.isEmpty && existingPhotos.isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .alert("Save Failed", isPresented: $showingSaveError) {
                Button("OK") {}
            } message: {
                Text("Could not save the note. Please try again.")
            }
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveNote() {
        let note: Note
        if let editing {
            note = editing
            if note.text != trimmedText {
                note.text = trimmedText
                note.updatedAt = Date()
            }
            if !capturedPhotos.isEmpty || note.updatedAt > tree.updatedAt {
                tree.updatedAt = Date()
            }
        } else {
            note = tree.addNote(text: trimmedText)
        }

        for photo in capturedPhotos {
            note.addPhoto(photo.data, capturedAt: photo.captureDate)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save note for tree \(tree.id): \(error)")
            modelContext.rollback()
            showingSaveError = true
        }
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
    .environment(PhotoViewerState())
    .modelContainer(for: [Tree.self, Collection.self, Photo.self, Note.self], inMemory: true)
}
