import SwiftUI
import MapKit

/// The map itself, shared by the iPhone and iPad map screens: tree pins,
/// clusters where pins would overlap, and the user's location.
struct TreeMapCanvas: View {
    /// The trees to show, already filtered
    let trees: [Tree]
    @Binding var position: MapCameraPosition
    @Binding var selectedTree: Tree?
    let showVariety: Bool

    @State private var visibleRegion: MKCoordinateRegion?

    var body: some View {
        let selectedID = selectedTree?.id
        let layout = MapClusterer.cluster(
            trees,
            in: visibleRegion,
            coordinate: { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) },
            isPinned: { $0.id == selectedID }
        )

        Map(position: $position, selection: $selectedTree) {
            ForEach(layout.singles) { tree in
                Annotation(
                    label(for: tree),
                    coordinate: CLLocationCoordinate2D(latitude: tree.latitude, longitude: tree.longitude),
                    anchor: .bottom
                ) {
                    TreeMapPin(tree: tree, isSelected: selectedID == tree.id)
                }
                .tag(tree)
            }

            ForEach(layout.clusters) { cluster in
                Annotation("", coordinate: cluster.coordinate) {
                    TreeClusterPin(count: cluster.items.count)
                        .onTapGesture {
                            zoom(to: cluster)
                        }
                }
            }

            UserAnnotation()
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
        }
        .onAppear {
            frameAllTreesIfUnpositioned()
        }
    }

    /// The automatic camera fits the pins edge to edge, which leaves them
    /// under the floating buttons. Start with some room around them instead.
    private func frameAllTreesIfUnpositioned() {
        guard position == .automatic, !trees.isEmpty else { return }
        position = .region(MapClusterer.boundingRegion(
            of: trees.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) },
            padding: 1.8,
            minimumSpan: 0.004
        ))
    }

    private func label(for tree: Tree) -> String {
        if showVariety, let variety = tree.variety, !variety.isEmpty {
            return variety
        }
        return tree.species.isEmpty ? "Tree" : tree.species
    }

    private func zoom(to cluster: MapClusterer.Cluster<Tree>) {
        let region = MapClusterer.boundingRegion(of: cluster.items.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        })
        withAnimation {
            position = .region(region)
        }
    }
}

struct TreeClusterPin: View {
    let count: Int

    var body: some View {
        Text(count > 999 ? "999+" : "\(count)")
            .font(.footnote)
            .fontWeight(.bold)
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minWidth: 40, minHeight: 40)
            .background(Color.green.gradient, in: Capsule())
            .overlay(Capsule().stroke(.white, lineWidth: 2))
            .shadow(radius: 2)
            .contentShape(Capsule())
            .accessibilityLabel("\(count) trees")
            .accessibilityHint("Zooms in to show them")
            .accessibilityAddTraits(.isButton)
    }
}
