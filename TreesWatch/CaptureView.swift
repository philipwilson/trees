import SwiftUI
import CoreLocation

struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var locationManager = WatchLocationManager()
    @State private var capturedLocation: CLLocation?
    @State private var selectedSpecies = ""
    @State private var notes = ""
    @State private var showingSpeciesPicker = false

    var onCapture: (WatchTree) -> Void

    private var canSave: Bool {
        capturedLocation != nil && !selectedSpecies.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Accuracy Display
                    AccuracyRingView(
                        accuracy: locationManager.currentLocation?.horizontalAccuracy,
                        isUpdating: locationManager.isRequestingLocation
                    )

                    // Capture/Captured Location
                    if let location = capturedLocation {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Location captured")
                                .font(.caption)
                        }
                    } else {
                        Button {
                            captureLocation()
                        } label: {
                            Label("Capture Location", systemImage: "location.fill")
                        }
                        .disabled(!locationManager.hasAcceptableAccuracy)
                    }

                    Divider()

                    // Species Selection
                    Button {
                        showingSpeciesPicker = true
                    } label: {
                        HStack {
                            Text(selectedSpecies.isEmpty ? "Select Species" : selectedSpecies)
                                .foregroundStyle(selectedSpecies.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    // Notes (optional)
                    TextField("Notes (optional)", text: $notes)
                        .textContentType(.none)
                }
                .padding()
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
            .sheet(isPresented: $showingSpeciesPicker) {
                SpeciesPickerView(selectedSpecies: $selectedSpecies)
            }
            .onAppear {
                checkPermissionAndStartLocation()
            }
            .onChange(of: locationManager.authorizationStatus) { _, newStatus in
                if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
                    locationManager.startUpdatingLocation()
                }
            }
            .onDisappear {
                locationManager.stopUpdatingLocation()
            }
        }
    }

    private func checkPermissionAndStartLocation() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestPermission()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        default:
            break
        }
    }

    private func captureLocation() {
        guard let location = locationManager.currentLocation else { return }
        capturedLocation = location
    }

    private func saveTree() {
        guard let location = capturedLocation else { return }

        let tree = WatchTree(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            altitude: location.altitude,
            species: selectedSpecies,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        WatchConnectivityManager.shared.sendTree(tree)
        onCapture(tree)
        dismiss()
    }
}

struct AccuracyRingView: View {
    let accuracy: Double?
    let isUpdating: Bool

    private var accuracyColor: Color {
        guard let accuracy = accuracy, accuracy > 0 else { return .gray }
        if accuracy < 5 { return .green }
        if accuracy < 15 { return .yellow }
        if accuracy < 25 { return .orange }
        return .red
    }

    private var progress: Double {
        guard let accuracy = accuracy, accuracy > 0 else { return 0 }
        return min(1, max(0, (50 - accuracy) / 50))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.gray.opacity(0.3), lineWidth: 8)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(accuracyColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)

            VStack(spacing: 2) {
                if let accuracy = accuracy, accuracy > 0 {
                    Text(String(format: "%.0f", accuracy))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("meters")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if isUpdating {
                    ProgressView()
                } else {
                    Text("—")
                        .font(.title2)
                }
            }
        }
        .frame(width: 100, height: 100)
    }
}

struct SpeciesPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedSpecies: String
    @State private var searchText = ""
    @State private var dictatedSpecies = ""

    private var filteredSpecies: [String] {
        if searchText.isEmpty {
            return commonSpecies
        }
        return commonSpecies.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Dictation section at top
                Section {
                    TextField("Dictate or type species", text: $dictatedSpecies)

                    if !dictatedSpecies.isEmpty {
                        Button {
                            let formatted = dictatedSpecies.prefix(1).uppercased() + dictatedSpecies.dropFirst().lowercased()
                            selectedSpecies = formatted
                            dismiss()
                        } label: {
                            HStack {
                                Text("Use \"\(dictatedSpecies)\"")
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                } header: {
                    Label("Voice Input", systemImage: "mic.fill")
                }

                // Common species section
                Section("Common Species") {
                    if !searchText.isEmpty && !filteredSpecies.contains(where: { $0.lowercased() == searchText.lowercased() }) {
                        Button {
                            selectedSpecies = searchText
                            dismiss()
                        } label: {
                            HStack {
                                Text("Use \"\(searchText)\"")
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }

                    ForEach(filteredSpecies, id: \.self) { species in
                        Button {
                            selectedSpecies = species
                            dismiss()
                        } label: {
                            HStack {
                                Text(species)
                                Spacer()
                                if species == selectedSpecies {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Filter list")
            .navigationTitle("Species")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    CaptureView { _ in }
}
