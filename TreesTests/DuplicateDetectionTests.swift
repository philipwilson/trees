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
        offset: TimeInterval = 0
    ) -> Tree {
        let created = base.addingTimeInterval(offset)
        let tree = Tree(
            latitude: latitude, longitude: -0.12, horizontalAccuracy: 4.0,
            species: species, createdAt: created, updatedAt: created
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
