import SwiftUI
import SwiftData
import CoreLocation

struct CaptureTreeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Collection.name) private var collections: [Collection]
    @AppStorage("lastUsedCollectionID") private var lastUsedCollectionID: String?
    @State private var locationManager = LocationManager()

    var preselectedCollection: Collection?

    @State private var species = ""
    @State private var variety = ""
    @State private var rootstock = ""
    @State private var initialNote = ""
    @State private var photos: [Data] = []
    @State private var photoDates: [Date?] = []
    @State private var capturedLocation: CLLocation?
    @State private var showingPermissionAlert = false
    @State private var selectedCollection: Collection?

    private var canSave: Bool {
        capturedLocation != nil
    }

    private var currentAccuracy: Double? {
        locationManager.currentLocation?.horizontalAccuracy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LiveAccuracyView(
                        accuracy: currentAccuracy,
                        isUpdating: locationManager.isUpdatingLocation
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)

                    if let location = capturedLocation {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text("Location Captured")
                                    .font(.headline)
                                Text(String(format: "%.6f, %.6f", location.coordinate.latitude, location.coordinate.longitude))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Button {
                            captureLocation()
                        } label: {
                            HStack {
                                Image(systemName: "location.circle.fill")
                                Text("Capture Current Location")
                            }
                        }
                        .disabled(!locationManager.hasAcceptableAccuracy)
                    }
                } header: {
                    Text("Location")
                }

                Section {
                    SpeciesTextField(text: $species)
                    TextField("Variety (optional)", text: $variety)
                    TextField("Rootstock (optional)", text: $rootstock)
                } header: {
                    Text("Details")
                }

                Section {
                    Picker("Collection", selection: $selectedCollection) {
                        Text("None").tag(nil as Collection?)
                        ForEach(collections) { collection in
                            Text(collection.name).tag(collection as Collection?)
                        }
                    }
                } header: {
                    Text("Collection")
                } footer: {
                    Text("Optionally add this tree to a collection")
                }

                Section {
                    TextField("Initial notes (optional)", text: $initialNote, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Notes")
                }

                Section {
                    if !photos.isEmpty {
                        EditablePhotoGalleryView(photos: $photos, photoDates: $photoDates)
                    }
                    PhotosPicker(selectedPhotos: $photos, photoDates: $photoDates)
                } header: {
                    Text("Photos")
                } footer: {
                    if photos.isEmpty {
                        Text("Add photos to help identify the tree later")
                    }
                }
            }
            .navigationTitle("New Tree")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTree()
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                checkPermissionAndStartLocation()
                if selectedCollection == nil {
                    if let preselected = preselectedCollection {
                        selectedCollection = preselected
                    } else if let lastID = lastUsedCollectionID,
                              let lastUUID = UUID(uuidString: lastID),
                              let lastCollection = collections.first(where: { $0.id == lastUUID }) {
                        selectedCollection = lastCollection
                    }
                }
            }
            .onChange(of: locationManager.authorizationStatus) { _, newStatus in
                if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                    locationManager.startUpdatingLocation()
                }
            }
            .onDisappear {
                locationManager.stopUpdatingLocation()
            }
            .alert("Location Permission Required", isPresented: $showingPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("Please enable location access in Settings to capture tree locations.")
            }
        }
    }

    private func checkPermissionAndStartLocation() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestPermission()
        case .denied, .restricted:
            showingPermissionAlert = true
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        @unknown default:
            break
        }
    }

    private func captureLocation() {
        guard let location = locationManager.currentLocation else { return }
        capturedLocation = location
    }

    private func saveTree() {
        guard let location = capturedLocation else { return }

        let trimmedVariety = variety.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRootstock = rootstock.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = initialNote.trimmingCharacters(in: .whitespacesAndNewlines)

        let tree = Tree(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            altitude: location.altitude,
            species: species.trimmingCharacters(in: .whitespacesAndNewlines),
            variety: trimmedVariety.isEmpty ? nil : trimmedVariety,
            rootstock: trimmedRootstock.isEmpty ? nil : trimmedRootstock
        )

        tree.collection = selectedCollection
        lastUsedCollectionID = selectedCollection?.id.uuidString
        modelContext.insert(tree)

        // Add photos as Photo entities
        for (index, photoData) in photos.enumerated() {
            let captureDate = index < photoDates.count ? photoDates[index] : Date()
            tree.addPhoto(photoData, capturedAt: captureDate)
        }

        // Add initial note if provided
        if !trimmedNote.isEmpty {
            _ = tree.addNote(text: trimmedNote)
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to save new tree: \(error)")
        }

        dismiss()
    }
}

#Preview {
    CaptureTreeView()
        .modelContainer(for: [Tree.self, Collection.self, Photo.self, Note.self], inMemory: true)
}
