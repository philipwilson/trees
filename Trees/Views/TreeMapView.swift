import SwiftUI
import SwiftData
import MapKit

struct TreeMapView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var trees: [Tree]
    @Query(sort: \Collection.name) private var collections: [Collection]
    @State private var filter = TreeFilter()
    @AppStorage("mapShowVariety") private var showVariety = false
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedTree: Tree?
    @State private var showingCaptureSheet = false
    @State private var showingOfflineTip = false
    @State private var locationManager = LocationManager()

    private var visibleTrees: [Tree] {
        filter.apply(to: trees)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                TreeMapCanvas(
                    trees: visibleTrees,
                    position: $position,
                    selectedTree: $selectedTree,
                    showVariety: showVariety
                )

                VStack(spacing: 12) {
                    Button {
                        centerOnUser()
                    } label: {
                        Image(systemName: "location.fill")
                            .accessibilityLabel("Center on My Location")
                            .font(.title3)
                            .padding(12)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }

                    Button {
                        showingCaptureSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Capture Tree")
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if filter.isActive {
                        Text("\(visibleTrees.count) of \(trees.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    TreeFilterMenu(
                        filter: $filter,
                        collections: collections,
                        speciesOptions: TreeFilter.speciesOptions(in: trees)
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showVariety.toggle()
                        } label: {
                            Label(
                                showVariety ? "Show Species" : "Show Variety",
                                systemImage: showVariety ? "leaf.fill" : "leaf"
                            )
                        }
                        Button {
                            showingOfflineTip = true
                        } label: {
                            Label("Using the Map Offline", systemImage: "wifi.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("Map Options")
                    }
                }
            }
            .sheet(isPresented: $showingCaptureSheet) {
                CaptureTreeView()
            }
            .sheet(item: $selectedTree) { tree in
                NavigationStack {
                    TreeDetailView(tree: tree)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") {
                                    selectedTree = nil
                                }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                locationManager.requestPermission()
            }
            .alert("Using the Map Offline", isPresented: $showingOfflineTip) {
                Button("OK") {}
            } message: {
                Text("Capturing trees works with no signal: positions come from GPS and everything is saved on this device.\n\nThe map background needs a connection. Areas you viewed recently may still appear, but that isn't guaranteed, and maps downloaded in the Apple Maps app aren't available to other apps.")
            }
        }
    }

    private func centerOnUser() {
        // Tracks the map's own live user location rather than a stored fix
        position = .userLocation(fallback: .automatic)
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
