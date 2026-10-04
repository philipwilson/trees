import MapKit

/// Groups map items that would overlap at the current zoom into clusters.
///
/// SwiftUI's Map has no built-in clustering for custom annotations, so this
/// lays a grid over the visible region (anchored to the globe, so clusters
/// stay put while panning) and merges items that share a cell. Items outside
/// the visible area are left out entirely, which keeps the number of
/// annotation views small however many trees there are.
enum MapClusterer {
    struct Cluster<Item>: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let items: [Item]
    }

    struct Result<Item> {
        var singles: [Item] = []
        var clusters: [Cluster<Item>] = []
    }

    private struct Group<Item> {
        let cell: Cell
        var members: [(item: Item, coordinate: CLLocationCoordinate2D)]
        var latitude: Double
        var longitude: Double
    }

    private struct Cell: Hashable {
        let row: Int
        let column: Int
    }

    /// Below this visible height (about 65 m) everything is shown
    /// individually, so the closest trees can always be reached.
    static let minimumClusteringSpan: CLLocationDegrees = 0.0006

    /// Roughly how many pins fit across and down the map before they overlap.
    static let columns: Double = 7
    static let rows: Double = 10

    /// - Parameters:
    ///   - region: The visible region; nil (before the map reports one) falls
    ///     back to the area the items cover.
    ///   - isPinned: Items that must stay individually visible wherever they
    ///     are, such as the selected tree.
    static func cluster<Item>(
        _ items: [Item],
        in region: MKCoordinateRegion?,
        coordinate: (Item) -> CLLocationCoordinate2D,
        isPinned: (Item) -> Bool = { _ in false }
    ) -> Result<Item> {
        guard !items.isEmpty else { return Result() }
        let region = region ?? boundingRegion(of: items.map(coordinate))

        // Cull to the visible area plus a margin so pins don't pop at the edges
        let latMargin = region.span.latitudeDelta
        let lonMargin = region.span.longitudeDelta
        let latRange = (region.center.latitude - latMargin)...(region.center.latitude + latMargin)
        let lonRange = (region.center.longitude - lonMargin)...(region.center.longitude + lonMargin)

        var result = Result<Item>()
        var visible: [(item: Item, coordinate: CLLocationCoordinate2D)] = []
        for item in items {
            let position = coordinate(item)
            if isPinned(item) {
                result.singles.append(item)
            } else if latRange.contains(position.latitude), lonRange.contains(position.longitude) {
                visible.append((item, position))
            }
        }

        guard region.span.latitudeDelta >= minimumClusteringSpan else {
            result.singles.append(contentsOf: visible.map(\.item))
            return result
        }

        let latCell = region.span.latitudeDelta / rows
        let lonCell = region.span.longitudeDelta / columns
        guard latCell > 0, lonCell > 0 else {
            result.singles.append(contentsOf: visible.map(\.item))
            return result
        }

        var cells: [Cell: [(item: Item, coordinate: CLLocationCoordinate2D)]] = [:]
        var order: [Cell] = []
        for entry in visible {
            let cell = Cell(
                row: Int((entry.coordinate.latitude / latCell).rounded(.down)),
                column: Int((entry.coordinate.longitude / lonCell).rounded(.down))
            )
            if cells[cell] == nil { order.append(cell) }
            cells[cell, default: []].append(entry)
        }

        // A grid alone leaves neighbours that straddle a cell edge as two
        // overlapping pins, so merge groups whose centres are closer than a
        // pin's width.
        var groups: [Group<Item>] = []
        for cell in order {
            guard let members = cells[cell] else { continue }
            let count = Double(members.count)
            let latitude = members.reduce(0) { $0 + $1.coordinate.latitude } / count
            let longitude = members.reduce(0) { $0 + $1.coordinate.longitude } / count

            if let nearby = groups.firstIndex(where: {
                abs($0.latitude - latitude) < latCell * 0.6 && abs($0.longitude - longitude) < lonCell * 0.6
            }) {
                let existing = Double(groups[nearby].members.count)
                groups[nearby].latitude = (groups[nearby].latitude * existing + latitude * count) / (existing + count)
                groups[nearby].longitude = (groups[nearby].longitude * existing + longitude * count) / (existing + count)
                groups[nearby].members.append(contentsOf: members)
            } else {
                groups.append(Group(cell: cell, members: members, latitude: latitude, longitude: longitude))
            }
        }

        for group in groups {
            if group.members.count == 1 {
                result.singles.append(group.members[0].item)
            } else {
                result.clusters.append(Cluster(
                    id: "\(group.cell.row):\(group.cell.column):\(group.members.count)",
                    coordinate: CLLocationCoordinate2D(latitude: group.latitude, longitude: group.longitude),
                    items: group.members.map(\.item)
                ))
            }
        }
        return result
    }

    /// The smallest region containing every coordinate, padded so pins at the
    /// edge aren't clipped. Tight groups are widened enough to zoom into
    /// without the map refusing the span, but stay under the clustering
    /// threshold so zooming to a cluster always splits it.
    static func boundingRegion(
        of coordinates: [CLLocationCoordinate2D],
        padding: Double = 1.6,
        minimumSpan: CLLocationDegrees = minimumClusteringSpan * 0.8
    ) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * padding, minimumSpan),
                longitudeDelta: max((maxLon - minLon) * padding, minimumSpan)
            )
        )
    }
}
