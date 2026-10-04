import SwiftUI
import SwiftData
import CoreLocation

/// Replaces a tree's saved position with a fresh GPS fix, for when the
/// original capture was inaccurate or taken from the wrong spot.
struct UpdateLocationView: View {
    @Bindable var tree: Tree
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var locationManager = LocationManager()
    @State private var showingSaveError = false

    private var savedLocation: CLLocation {
        CLLocation(latitude: tree.latitude, longitude: tree.longitude)
    }

    private var locationAccessDenied: Bool {
        locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Position") {
                        Text(tree.coordinateString)
                    }
                    LabeledContent("Accuracy") {
                        AccuracyBadge(accuracy: tree.horizontalAccuracy)
                    }
                } header: {
                    Text("Saved Location")
                }

                Section {
                    LocationProblemNotice(locationManager: locationManager)

                    if !locationAccessDenied {
                        LiveAccuracyView(
                            accuracy: locationManager.currentLocation?.horizontalAccuracy,
                            isUpdating: locationManager.isUpdatingLocation
                        )
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)

                        if let current = locationManager.currentLocation {
                            LabeledContent("Position") {
                                Text(String(format: "%.6f, %.6f", current.coordinate.latitude, current.coordinate.longitude))
                            }
                            LabeledContent("Distance from saved") {
                                Text(Self.distanceText(current.distance(from: savedLocation)))
                            }
                        }
                    }
                } header: {
                    Text("Current Location")
                } footer: {
                    Text("Stand at the tree and wait for the accuracy to settle before updating.")
                }

                Section {
                    Button {
                        useCurrentLocation()
                    } label: {
                        Label("Use Current Location", systemImage: "location.circle.fill")
                    }
                    .disabled(!locationManager.hasAcceptableAccuracy)
                }
            }
            .navigationTitle("Update Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                switch locationManager.authorizationStatus {
                case .notDetermined:
                    locationManager.requestPermission()
                case .authorizedWhenInUse, .authorizedAlways:
                    locationManager.startUpdatingLocation()
                default:
                    break
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
            .alert("Save Failed", isPresented: $showingSaveError) {
                Button("OK") {}
            } message: {
                Text("Could not update the location. Please try again.")
            }
        }
    }

    static func distanceText(_ meters: CLLocationDistance) -> String {
        meters < 1000 ? String(format: "%.1f m", meters) : String(format: "%.2f km", meters / 1000)
    }

    private func useCurrentLocation() {
        // Rechecked at the moment of use: the fix must still be fresh
        guard let location = locationManager.capturableLocation() else { return }
        tree.apply(location: location)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to update location for tree \(tree.id): \(error)")
            modelContext.rollback()
            showingSaveError = true
        }
    }
}

extension Tree {
    /// Replaces the stored position with the given fix.
    func apply(location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracy = location.horizontalAccuracy
        altitude = location.altitude
        updatedAt = Date()
    }
}
