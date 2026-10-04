import XCTest
import MapKit
@testable import Trees

final class MapClustererTests: XCTestCase {
    private struct Pin: Equatable {
        let name: String
        let latitude: Double
        let longitude: Double
    }

    private func coordinate(_ pin: Pin) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)
    }

    private func region(latitude: Double = 51.5, longitude: Double = -0.12, span: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
    }

    // An orchard: 3 trees a few metres apart, plus one tree 5 km north
    private let orchard = [
        Pin(name: "a", latitude: 51.50000, longitude: -0.12000),
        Pin(name: "b", latitude: 51.50003, longitude: -0.12002),
        Pin(name: "c", latitude: 51.50005, longitude: -0.12004),
    ]
    private let distant = Pin(name: "far", latitude: 51.545, longitude: -0.12)

    func testZoomedOutNearbyItemsMergeAndDistantOnesStayApart() {
        let result = MapClusterer.cluster(orchard + [distant], in: region(latitude: 51.52, span: 0.1), coordinate: coordinate)

        XCTAssertEqual(result.singles, [distant])
        XCTAssertEqual(result.clusters.count, 1)
        XCTAssertEqual(result.clusters.first?.items, orchard)
        let center = try? XCTUnwrap(result.clusters.first?.coordinate)
        XCTAssertEqual(center?.latitude ?? 0, 51.500027, accuracy: 0.00001)
    }

    /// Two trees a few metres apart can fall either side of a grid line; they
    /// must still merge rather than draw as overlapping pins.
    func testNeighboursAcrossAGridLineStillMerge() {
        // With a 0.1° span the grid lines are 0.01° apart in latitude
        let straddling = [
            Pin(name: "below", latitude: 51.49999, longitude: -0.115),
            Pin(name: "above", latitude: 51.50001, longitude: -0.115),
        ]
        let result = MapClusterer.cluster(straddling, in: region(span: 0.1), coordinate: coordinate)

        XCTAssertTrue(result.singles.isEmpty)
        XCTAssertEqual(result.clusters.first?.items, straddling)
    }

    func testZoomedInEverythingIsIndividual() {
        let result = MapClusterer.cluster(orchard, in: region(span: 0.0004), coordinate: coordinate)

        XCTAssertEqual(result.singles, orchard)
        XCTAssertTrue(result.clusters.isEmpty)
    }

    func testItemsOutsideTheVisibleAreaAreLeftOut() {
        let result = MapClusterer.cluster(orchard + [distant], in: region(span: 0.002), coordinate: coordinate)

        let shown = result.singles + result.clusters.flatMap(\.items)
        XCTAssertFalse(shown.contains(distant))
        XCTAssertEqual(Set(shown.map(\.name)), ["a", "b", "c"])
    }

    /// The selected tree is never merged or culled, so its detail sheet
    /// doesn't lose its pin.
    func testPinnedItemStaysIndividualEvenWhenClusteredOrOffscreen() {
        let clustered = MapClusterer.cluster(
            orchard, in: region(span: 0.1), coordinate: coordinate, isPinned: { $0.name == "b" }
        )
        XCTAssertEqual(clustered.singles.map(\.name), ["b"])
        XCTAssertEqual(clustered.clusters.first?.items.map(\.name), ["a", "c"])

        let offscreen = MapClusterer.cluster(
            orchard + [distant], in: region(span: 0.002), coordinate: coordinate, isPinned: { $0.name == "far" }
        )
        XCTAssertTrue(offscreen.singles.contains(distant))
    }

    func testClusterIdentityIsStableWhilePanning() {
        let before = MapClusterer.cluster(orchard, in: region(latitude: 51.50, span: 0.1), coordinate: coordinate)
        let after = MapClusterer.cluster(orchard, in: region(latitude: 51.51, span: 0.1), coordinate: coordinate)

        XCTAssertEqual(before.clusters.map(\.id), after.clusters.map(\.id))
    }

    func testNoRegionYetFallsBackToTheAreaTheItemsCover() {
        let result = MapClusterer.cluster(orchard + [distant], in: nil, coordinate: coordinate)

        let shown = result.singles + result.clusters.flatMap(\.items)
        XCTAssertEqual(shown.count, 4, "nothing is culled before the map reports its region")
        XCTAssertEqual(result.clusters.first?.items, orchard)
    }

    func testEmptyInput() {
        let result = MapClusterer.cluster([Pin](), in: nil, coordinate: coordinate)
        XCTAssertTrue(result.singles.isEmpty)
        XCTAssertTrue(result.clusters.isEmpty)
    }

    /// Tapping a cluster zooms to its bounding region; that must be tight
    /// enough to split the cluster, or the tap would do nothing.
    func testZoomingToAClusterSplitsIt() {
        let zoomed = MapClusterer.boundingRegion(of: orchard.map(coordinate))
        XCTAssertLessThan(zoomed.span.latitudeDelta, MapClusterer.minimumClusteringSpan)

        let result = MapClusterer.cluster(orchard, in: zoomed, coordinate: coordinate)
        XCTAssertEqual(result.singles, orchard)

        // A widely spread cluster zooms to its extent with padding
        let wide = MapClusterer.boundingRegion(of: (orchard + [distant]).map(coordinate))
        XCTAssertEqual(wide.span.latitudeDelta, 0.045 * 1.6, accuracy: 0.0001)
        XCTAssertEqual(wide.center.latitude, 51.5225, accuracy: 0.0001)
    }
}
