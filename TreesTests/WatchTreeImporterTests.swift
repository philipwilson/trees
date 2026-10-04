import XCTest
import SwiftData
@testable import Trees

@MainActor
final class WatchTreeImporterTests: XCTestCase {

    // ModelContext does not keep its container alive, so tests must hold the
    // container itself; using a context whose container deallocated traps in SwiftData.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: TreesSchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func watchTree(id: UUID = UUID(), species: String = "Apple", notes: String = "") -> WatchTree {
        WatchTree(
            id: id, latitude: 51.5, longitude: -0.12, horizontalAccuracy: 6.5, altitude: 42.0,
            species: species, notes: notes, capturedAt: capturedAt
        )
    }

    func testImportCopiesFieldsAndKeepsWatchIDAndCaptureTime() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let source = watchTree(notes: "by the gate")

        let returned = try XCTUnwrap(WatchTreeImporter(modelContext: context).importTree(source))

        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<Tree>()).first)
        XCTAssertEqual(stored.id, returned.id)
        XCTAssertEqual(stored.id, source.id)
        XCTAssertEqual(stored.latitude, 51.5)
        XCTAssertEqual(stored.longitude, -0.12)
        XCTAssertEqual(stored.horizontalAccuracy, 6.5)
        XCTAssertEqual(stored.altitude, 42.0)
        XCTAssertEqual(stored.species, "Apple")
        XCTAssertNil(stored.variety)
        XCTAssertNil(stored.collection)
        XCTAssertEqual(stored.createdAt, capturedAt)
        XCTAssertEqual(stored.treeNotes.map(\.text), ["by the gate"])
        XCTAssertFalse(context.hasChanges, "import should save")
    }

    func testEmptyWatchNoteCreatesNoNote() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let tree = try XCTUnwrap(WatchTreeImporter(modelContext: context).importTree(watchTree(notes: "")))

        XCTAssertTrue(tree.treeNotes.isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Note>()).count, 0)
    }

    /// transferUserInfo can redeliver, and the watch retries its pending queue,
    /// so the same tree may arrive more than once.
    func testSameIDIsImportedOnlyOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let importer = WatchTreeImporter(modelContext: context)
        let id = UUID()

        XCTAssertNotNil(importer.importTree(watchTree(id: id, species: "Apple", notes: "first")))
        XCTAssertNil(importer.importTree(watchTree(id: id, species: "Changed", notes: "second")))

        let trees = try context.fetch(FetchDescriptor<Tree>())
        XCTAssertEqual(trees.count, 1)
        XCTAssertEqual(trees.first?.species, "Apple")
        XCTAssertEqual(trees.first?.treeNotes.map(\.text), ["first"])
    }

    func testBatchImportReturnsOnlyNewTrees() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let importer = WatchTreeImporter(modelContext: context)
        let existing = watchTree(species: "Pear")
        _ = importer.importTree(existing)

        let fresh = watchTree(species: "Plum")
        let repeated = watchTree(species: "Cherry")
        let imported = importer.importTrees([existing, fresh, repeated, repeated])

        XCTAssertEqual(imported.map(\.id), [fresh.id, repeated.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Tree>()).count, 3)
    }
}
