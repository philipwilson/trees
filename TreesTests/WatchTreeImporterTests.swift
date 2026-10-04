import XCTest
import SwiftData
@testable import Trees

@MainActor
final class WatchTreeImporterTests: XCTestCase {

    // ModelContext does not keep its container alive, so tests must hold the
    // container itself; using a context whose container deallocated traps in SwiftData.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentTreesSchema.self)
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

@MainActor
final class WatchTreeInboxTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "WatchTreeInboxTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // ModelContext does not keep its container alive, so tests must hold the
    // container itself; using a context whose container deallocated traps in SwiftData.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentTreesSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func payload(species: String, id: UUID = UUID()) throws -> Data {
        try JSONEncoder().encode(WatchTree(
            id: id, latitude: 51.5, longitude: -0.12, horizontalAccuracy: 6, species: species, notes: "from watch"
        ))
    }

    func testStoredTreesAreImportedInArrivalOrderAndCleared() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let inbox = WatchTreeInbox(directory: directory)
        XCTAssertTrue(inbox.store(try payload(species: "Apple")))
        XCTAssertTrue(inbox.store(try payload(species: "Pear")))
        XCTAssertEqual(inbox.pendingCount, 2)

        let importer = WatchTreeImporter(modelContext: context)
        let imported = inbox.processPending(importTree: importer.importOutcome)

        XCTAssertEqual(imported.map(\.species), ["Apple", "Pear"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Tree>()).count, 2)
        XCTAssertEqual(imported.first?.treeNotes.map(\.text), ["from watch"])
        XCTAssertEqual(inbox.pendingCount, 0)
    }

    /// The reason the inbox exists: a tree whose save fails must still be
    /// there to import later.
    func testFailedSaveKeepsTheTreeForALaterAttempt() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let inbox = WatchTreeInbox(directory: directory)
        inbox.store(try payload(species: "Apple"))
        inbox.store(try payload(species: "Pear"))

        // First attempt: the store rejects everything
        let nothing = inbox.processPending { _ in .failed }
        XCTAssertTrue(nothing.isEmpty)
        XCTAssertEqual(inbox.pendingCount, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Tree>()).count, 0)

        // Next launch: a new inbox over the same directory, store working
        let relaunched = WatchTreeInbox(directory: directory)
        let importer = WatchTreeImporter(modelContext: context)
        let imported = relaunched.processPending(importTree: importer.importOutcome)

        XCTAssertEqual(imported.map(\.species), ["Apple", "Pear"])
        XCTAssertEqual(relaunched.pendingCount, 0)
    }

    func testOneFailureDoesNotHoldBackOtherTrees() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let inbox = WatchTreeInbox(directory: directory)
        inbox.store(try payload(species: "Stuck"))
        inbox.store(try payload(species: "Fine"))

        let importer = WatchTreeImporter(modelContext: context)
        let imported = inbox.processPending { tree in
            tree.species == "Stuck" ? .failed : importer.importOutcome(tree)
        }

        XCTAssertEqual(imported.map(\.species), ["Fine"])
        XCTAssertEqual(inbox.pendingCount, 1)
    }

    func testTreeAlreadyInTheStoreIsClearedWithoutDuplicating() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let importer = WatchTreeImporter(modelContext: context)
        let id = UUID()
        _ = importer.importTree(WatchTree(id: id, latitude: 1, longitude: 2, horizontalAccuracy: 3, species: "Apple"))

        let inbox = WatchTreeInbox(directory: directory)
        inbox.store(try payload(species: "Apple", id: id))
        let imported = inbox.processPending(importTree: importer.importOutcome)

        XCTAssertTrue(imported.isEmpty)
        XCTAssertEqual(inbox.pendingCount, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Tree>()).count, 1)
    }

    /// A payload this build can't decode (e.g. from a newer watch app) is
    /// kept rather than discarded, and doesn't block the rest.
    func testUndecodablePayloadIsKeptAndSkipped() throws {
        let container = try makeContainer()
        let inbox = WatchTreeInbox(directory: directory)
        inbox.store(Data("{\"future\": true}".utf8))
        inbox.store(try payload(species: "Apple"))

        let importer = WatchTreeImporter(modelContext: container.mainContext)
        let imported = inbox.processPending(importTree: importer.importOutcome)

        XCTAssertEqual(imported.map(\.species), ["Apple"])
        XCTAssertEqual(inbox.pendingCount, 1)
    }

    func testImportOutcomeDistinguishesDuplicateFromImported() throws {
        let container = try makeContainer()
        let importer = WatchTreeImporter(modelContext: container.mainContext)
        let tree = WatchTree(latitude: 1, longitude: 2, horizontalAccuracy: 3, species: "Apple")

        guard case .imported = importer.importOutcome(tree) else { return XCTFail("expected imported") }
        guard case .alreadyPresent = importer.importOutcome(tree) else { return XCTFail("expected alreadyPresent") }
    }

    func testEmptyInbox() throws {
        let container = try makeContainer()
        let inbox = WatchTreeInbox(directory: directory)
        let importer = WatchTreeImporter(modelContext: container.mainContext)

        XCTAssertEqual(inbox.pendingCount, 0)
        XCTAssertTrue(inbox.processPending(importTree: importer.importOutcome).isEmpty)
    }
}
