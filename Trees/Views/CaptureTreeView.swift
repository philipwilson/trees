import SwiftUI
import SwiftData
import CoreLocation

struct CaptureTreeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var locationManager = LocationManager()

    @State private var species = ""
    @State private var variety = ""
    @State private var rootstock = ""
    @State private var notes = ""
    @State private var photos: [Data] = []
    @State private var capturedLocation: CLLocation?
    @State private var showingPermissionAlert = false

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
                    TextField("Species", text: $species)
                    TextField("Variety (optional)", text: $variety)
                    TextField("Rootstock (optional)", text: $rootstock)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Details")
                }

                Section {
                    if !photos.isEmpty {
                        EditablePhotoGalleryView(photos: $photos)
                    }
                    PhotosPicker(selectedPhotos: $photos)
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

        let tree = Tree(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            altitude: location.altitude,
            species: species.trimmingCharacters(in: .whitespacesAndNewlines),
            variety: trimmedVariety.isEmpty ? nil : trimmedVariety,
            rootstock: trimmedRootstock.isEmpty ? nil : trimmedRootstock,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            photos: photos
        )

        modelContext.insert(tree)
        dismiss()
    }
}

#Preview {
    CaptureTreeView()
        .modelContainer(for: Tree.self, inMemory: true)
}
