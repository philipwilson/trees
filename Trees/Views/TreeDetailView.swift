import SwiftUI
import SwiftData
import MapKit

struct TreeDetailView: View {
    @Bindable var tree: Tree
    @Environment(PhotoViewerState.self) private var photoViewerState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Collection.name) private var collections: [Collection]
    @FocusState private var focusedField: EditableField?
    @State private var showingDeleteConfirmation = false
    @State private var showingAddNote = false
    @State private var saveErrorMessage: String?

    @State private var newPhotos: [CapturedPhoto] = []

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: tree.latitude, longitude: tree.longitude)
    }

    private var varietyBinding: Binding<String> {
        Binding(
            get: { tree.variety ?? "" },
            set: { tree.variety = $0.isEmpty ? nil : $0 }
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
                    nextField: nil
                )
            } header: {
                Text("Details")
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
                    }
                }
            }
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
        tree.updatedAt = Date()
        saveContext()
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
    @State private var selectedPhoto: Photo?

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
                                    .onTapGesture {
                                        selectedPhoto = photo
                                    }
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .fullScreenCover(item: $selectedPhoto) { photo in
            PhotoDetailView(photos: note.notePhotos, initialPhoto: photo)
        }
    }
}

struct AddNoteView: View {
    let tree: Tree
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var capturedPhotos: [CapturedPhoto] = []

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
                    if !capturedPhotos.isEmpty {
                        EditablePhotoGalleryView(capturedPhotos: $capturedPhotos)
                    }
                    PhotosPicker(capturedPhotos: $capturedPhotos)
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
                    .disabled(text.isEmpty && capturedPhotos.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func saveNote() {
        let note = tree.addNote(text: text.trimmingCharacters(in: .whitespacesAndNewlines))

        for photo in capturedPhotos {
            note.addPhoto(photo.data, capturedAt: photo.captureDate)
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
    .environment(PhotoViewerState())
    .modelContainer(for: [Tree.self, Collection.self, Photo.self, Note.self], inMemory: true)
}
