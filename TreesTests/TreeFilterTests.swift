import XCTest
import SwiftData
@testable import Trees

@MainActor
final class TreeFilterTests: XCTestCase {

    // ModelContext does not keep its container alive, so tests must hold the
    // container itself; using a context whose container deallocated traps in SwiftData.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: TreesSchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private struct Fixture {
        let container: ModelContainer
        let north: Trees.Collection
        let south: Trees.Collection
        let bramley: Tree   // Apple, North, 2026-10-04, 3 m
        let cox: Tree       // apple (lowercase), South, 2026-06-15, 12 m
        let pear: Tree      // Pear, no collection, 2025-03-01, 3 m
        let unnamed: Tree   // "", North, 2024-01-10, 20 m
        var all: [Tree] { [bramley, cox, pear, unnamed] }
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso + "T12:00:00Z")!
    }

    private func makeFixture() throws -> Fixture {
        let container = try makeContainer()
        let context = container.mainContext
        let north = Collection(name: "North Orchard")
        let south = Collection(name: "South Field")
        context.insert(north)
        context.insert(south)

        func tree(_ species: String, _ variety: String?, _ accuracy: Double, _ created: String, _ collection: Trees.Collection?) -> Tree {
            let when = date(created)
            let tree = Tree(latitude: 51.5, longitude: -0.12, horizontalAccuracy: accuracy,
                            species: species, variety: variety, createdAt: when, updatedAt: when)
            context.insert(tree)
            tree.collection = collection
            return tree
        }
        let fixture = Fixture(
            container: container, north: north, south: south,
            bramley: tree("Apple", "Bramley", 3, "2026-10-04", north),
            cox: tree("apple", "Cox", 12, "2026-06-15", south),
            pear: tree("Pear", nil, 3, "2025-03-01", nil),
            unnamed: tree("", nil, 20, "2024-01-10", north)
        )
        fixture.pear.rootstock = "Quince A"
        try context.save()
        return fixture
    }

    // MARK: - Filtering

    func testDefaultFilterIncludesEverything() throws {
        let f = try makeFixture()
        let filter = TreeFilter()
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.apply(to: f.all).map(\.id), f.all.map(\.id))
    }

    func testCollectionFilter() throws {
        let f = try makeFixture()
        XCTAssertEqual(Set(TreeFilter(collection: .collection(f.north.id)).apply(to: f.all).map(\.id)),
                       [f.bramley.id, f.unnamed.id])
        XCTAssertEqual(TreeFilter(collection: .unassigned).apply(to: f.all).map(\.id), [f.pear.id])
        XCTAssertTrue(TreeFilter(collection: .collection(UUID())).apply(to: f.all).isEmpty)
    }

    func testSpeciesFilterIgnoresCaseAndCombinesWithCollection() throws {
        let f = try makeFixture()
        XCTAssertEqual(Set(TreeFilter(species: "Apple").apply(to: f.all).map(\.id)), [f.bramley.id, f.cox.id])

        let both = TreeFilter(collection: .collection(f.south.id), species: "APPLE")
        XCTAssertTrue(both.isActive)
        XCTAssertEqual(both.apply(to: f.all).map(\.id), [f.cox.id])
    }

    func testSpeciesOptionsAreDistinctSortedAndSkipUnnamed() throws {
        let f = try makeFixture()
        XCTAssertEqual(TreeFilter.speciesOptions(in: f.all), ["Apple", "Pear"])
    }

    func testFilterSearchAndSortCompose() throws {
        let f = try makeFixture()
        let result = TreeFilter(species: "apple").apply(to: f.all, searchText: "orchard", sortOrder: .oldest)
        XCTAssertEqual(result.map(\.id), [f.bramley.id])
    }

    // MARK: - Sorting

    func testSortOrders() throws {
        let f = try makeFixture()
        XCTAssertEqual(TreeSortOrder.newest.sorted(f.all).map(\.id), [f.bramley.id, f.cox.id, f.pear.id, f.unnamed.id])
        XCTAssertEqual(TreeSortOrder.oldest.sorted(f.all).map(\.id), [f.unnamed.id, f.pear.id, f.cox.id, f.bramley.id])
        // Species ignores case, breaks ties by variety, and puts unnamed trees last
        XCTAssertEqual(TreeSortOrder.species.sorted(f.all).map(\.id), [f.bramley.id, f.cox.id, f.pear.id, f.unnamed.id])
        // Equal accuracy falls back to newest first
        XCTAssertEqual(TreeSortOrder.accuracy.sorted(f.all).map(\.id), [f.bramley.id, f.pear.id, f.cox.id, f.unnamed.id])
    }

    func testSortOrderRoundTripsThroughItsStoredValue() {
        for order in TreeSortOrder.allCases {
            XCTAssertEqual(TreeSortOrder(rawValue: order.rawValue), order)
        }
    }

    // MARK: - Search

    func testSearchMatchesCollectionRootstockAndDate() throws {
        let f = try makeFixture()
        XCTAssertTrue(f.bramley.matches(searchText: "north"))
        XCTAssertFalse(f.cox.matches(searchText: "north"))
        XCTAssertTrue(f.pear.matches(searchText: "quince"))

        XCTAssertTrue(f.bramley.matches(searchText: "2026-10-04"))
        XCTAssertTrue(f.bramley.matches(searchText: "2026"))
        XCTAssertTrue(f.cox.matches(searchText: "2026"))
        XCTAssertFalse(f.pear.matches(searchText: "2026"))
        XCTAssertTrue(f.pear.matches(searchText: "2025-03"))
    }
}
