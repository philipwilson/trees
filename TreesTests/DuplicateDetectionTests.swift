import XCTest
import SwiftData
@testable import Trees

@MainActor
final class DuplicateDetectionTests: XCTestCase {

    // ModelContext does not keep its container alive, so tests must hold the
    // container itself; using a context whose container deallocated traps in SwiftData.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: TreesSchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeTree(
        in context: ModelContext,
        species: String,
        latitude: Double = 51.5,
        metersNorth: Double = 0,
        variety: String? = nil,
        offset: TimeInterval = 0
    ) -> Tree {
        let created = base.addingTimeInterval(offset)
        // One degree of latitude is about 111,320 m
        let tree = Tree(
            latitude: latitude + metersNorth / 111_320, longitude: -0.12, horizontalAccuracy: 4.0,
            species: species, variety: variety, createdAt: created, updatedAt: created
        )
        context.insert(tree)
        return tree
    }

    func testGroupsSameSpeciesSamePlaceCloseInTime() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = makeTree(in: context, species: "Apple")
        let second = makeTree(in: context, species: "apple ", offset: 60)
        _ = makeTree(in: context, species: "Pear")
        _ = makeTree(in: context, species: "Apple", latitude: 51.6)
        _ = makeTree(in: context, species: "Apple", offset: 3600)

        let groups = DuplicateTreesView.duplicateGroups(in: try context.fetch(FetchDescriptor<Tree>()))

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].map(\.id)), [first.id, second.id])
    }

    /// A second capture of the same tree lands a metre or so away because of
    /// GPS drift; it must still be found.
    func testGroupsCapturesSeparatedByGPSJitter() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = makeTree(in: context, species: "Apple")
        let second = makeTree(in: context, species: "Apple", metersNorth: 1.2, offset: 45)
        let third = makeTree(in: context, species: "Apple", metersNorth: -0.8, offset: 90)

        let groups = DuplicateTreesView.duplicateGroups(in: try context.fetch(FetchDescriptor<Tree>()))

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].map(\.id)), [first.id, second.id, third.id])
    }

    /// Walking a row and capturing each tree gives the same species minutes
    /// apart, a planting distance away. Those are not duplicates.
    func testNeighbouringTreesInARowAreNotGrouped() throws {
        let container = try makeContainer()
        let context = container.mainContext
        for index in 0..<5 {
            _ = makeTree(in: context, species: "Apple", metersNorth: Double(index) * 3, offset: Double(index) * 60)
        }

        let groups = DuplicateTreesView.duplicateGroups(in: try context.fetch(FetchDescriptor<Tree>()))

        XCTAssertTrue(groups.isEmpty)
    }

    func testDifferentVarietiesAtTheSameSpotAreNotGrouped() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = makeTree(in: context, species: "Apple", variety: "Bramley")
        _ = makeTree(in: context, species: "Apple", variety: "Cox", offset: 30)

        XCTAssertTrue(DuplicateTreesView.duplicateGroups(in: try context.fetch(FetchDescriptor<Tree>())).isEmpty)
    }

    /// A capture with the variety filled in and one without can still be the
    /// same tree.
    func testMissingVarietyDoesNotPreventGrouping() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = makeTree(in: context, species: "Apple", variety: "Bramley")
        _ = makeTree(in: context, species: "Apple", variety: nil, offset: 30)
        _ = makeTree(in: context, species: "Apple", variety: " bramley", offset: 60)

        let groups = DuplicateTreesView.duplicateGroups(in: try context.fetch(FetchDescriptor<Tree>()))

        XCTAssertEqual(groups.map(\.count), [3])
    }

    /// After deleting one of a pair, regrouping the remaining trees must not
    /// report the group any more.
    func testGroupDisappearsOnceDuplicateIsExcluded() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let keep = makeTree(in: context, species: "Apple")
        let remove = makeTree(in: context, species: "Apple", offset: 30)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Tree>())
        XCTAssertEqual(DuplicateTreesView.duplicateGroups(in: all).count, 1)

        let remaining = all.filter { $0.persistentModelID != remove.persistentModelID }
        XCTAssertEqual(remaining.map(\.id), [keep.id])
        XCTAssertTrue(DuplicateTreesView.duplicateGroups(in: remaining).isEmpty)
    }
}
