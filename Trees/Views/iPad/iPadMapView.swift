import SwiftUI
import SwiftData
import MapKit

struct iPadMapView: View {
    var onBack: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query private var trees: [Tree]
    @AppStorage("mapShowVariety") private var showVariety = false
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedTree: Tree?
    @State private var showingCaptureSheet = false
    @State private var showingTreeList = true
    @State private var searchText = ""
    @State private var locationManager = LocationManager()

    var filteredTrees: [Tree] {
        if searchText.isEmpty {
            return trees
        }
        return trees.filter { tree in
            tree.species.localizedCaseInsensitiveContains(searchText) ||
            (tree.variety ?? "").localizedCaseInsensitiveContains(searchText) ||
            tree.treeNotes.contains { $0.text.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                Map(position: $position, selection: $selectedTree) {
                    ForEach(trees) { tree in
                        Annotation(
                            labelFor(tree),
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
                .ignoresSafeArea(edges: .bottom)

                // Floating panel
                if showingTreeList {
                    floatingPanel
                        .padding(.top, 8)
                        .padding(.trailing, 16)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                // Floating action buttons
                VStack(spacing: 12) {
                    Button {
                        withAnimation {
                            showingTreeList.toggle()
                        }
                    } label: {
                        Image(systemName: showingTreeList ? "sidebar.right" : "sidebar.left")
                            .font(.title3)
                            .padding(12)
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }

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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let onBack {
                        Button {
                            onBack()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showVariety.toggle()
                    } label: {
                        Label(
                            showVariety ? "Show Species" : "Show Variety",
                            systemImage: showVariety ? "leaf.fill" : "leaf"
                        )
                    }
                }
            }
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

    private var floatingPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search trees", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(.regularMaterial)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredTrees) { tree in
                        Button {
                            selectedTree = tree
                            position = .region(MKCoordinateRegion(
                                center: CLLocationCoordinate2D(
                                    latitude: tree.latitude,
                                    longitude: tree.longitude
                                ),
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            ))
                        } label: {
                            HStack(spacing: 12) {
                                if let firstPhoto = tree.treePhotos.first,
                                   let uiImage = UIImage(data: firstPhoto.imageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 40, height: 40)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                } else {
                                    Image(systemName: "tree.fill")
                                        .font(.title3)
                                        .foregroundStyle(.green)
                                        .frame(width: 40, height: 40)
                                        .background(Color.green.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tree.species.isEmpty ? "Unknown Species" : tree.species)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)

                                    if let variety = tree.variety, !variety.isEmpty {
                                        Text(variety)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)

                        if tree.id != filteredTrees.last?.id {
                            Divider()
                                .padding(.leading, 64)
                        }
                    }
                }
            }
            .frame(maxHeight: 400)
            .background(.regularMaterial)
        }
        .frame(width: 320)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    private func labelFor(_ tree: Tree) -> String {
        if showVariety, let variety = tree.variety, !variety.isEmpty {
            return variety
        }
        return tree.species.isEmpty ? "Tree" : tree.species
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

#Preview {
    iPadMapView()
        .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
