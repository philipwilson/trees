import SwiftUI
import SwiftData
import MapKit

struct TreeMapView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var trees: [Tree]
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedTree: Tree?
    @State private var showingCaptureSheet = false
    @State private var locationManager = LocationManager()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Map(position: $position, selection: $selectedTree) {
                    ForEach(trees) { tree in
                        Annotation(
                            tree.species.isEmpty ? "Tree" : tree.species,
                            coordinate: CLLocationCoordinate2D(
                                latitude: tree.latitude,
                                longitude: tree.longitude
                            ),
                            anchor: .bottom
                        ) {
                            TreeMapPin(tree: tree, isSelected: selectedTree?.id == tree.id)
                        }
                        .tag(tree)
                    }

                    UserAnnotation()
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }

                VStack(spacing: 12) {
                    Button {
                        centerOnUser()
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.title3)
                            .padding(12)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }

                    Button {
                        showingCaptureSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(16)
                            .background(.green)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                }
                .padding()
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingCaptureSheet) {
                CaptureTreeView()
            }
            .sheet(item: $selectedTree) { tree in
                NavigationStack {
                    TreeDetailView(tree: tree)
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                locationManager.requestPermission()
            }
        }
    }

    private func centerOnUser() {
        if let location = locationManager.currentLocation {
            position = .region(MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        } else {
            locationManager.startUpdatingLocation()
        }
    }
}

struct TreeMapPin: View {
    let tree: Tree
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(.green)
                    .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                    .shadow(radius: 2)

                Image(systemName: "tree.fill")
                    .foregroundStyle(.white)
                    .font(isSelected ? .title3 : .body)
            }

            Image(systemName: "triangle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
                .rotationEffect(.degrees(180))
                .offset(y: -3)
        }
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}

#Preview {
    TreeMapView()
        .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
