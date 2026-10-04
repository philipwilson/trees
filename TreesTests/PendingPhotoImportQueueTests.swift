import XCTest
import SwiftData
@testable import Trees

@MainActor
final class PendingPhotoImportQueueTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "PendingPhotoImportQueueTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // ModelContext does not keep its container alive, so tests must hold the
    // container itself; using a context whose container deallocated traps in SwiftData.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: TreesSchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeQueue(_ container: ModelContainer) -> PendingPhotoImportQueue {
        PendingPhotoImportQueue(modelContainer: container, directory: directory, delayBetweenTrees: .zero)
    }

    private func makeTree(in context: ModelContext, species: String = "Apple") -> Tree {
        let tree = Tree(latitude: 51.5, longitude: -0.12, horizontalAccuracy: 4.0, species: species)
        context.insert(tree)
        return tree
    }

    private func deferred(_ bytes: [UInt8], tree: UUID, note: UUID? = nil, captured: Date? = nil) -> TreeImportService.DeferredPhoto {
        TreeImportService.DeferredPhoto(
            treeID: tree, noteID: note, base64: Data(bytes).base64EncodedString(), captureDate: captured
        )
    }

    private func spooledFileNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    func testDrainAttachesPhotosToTreesAndNotes() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = makeTree(in: context)
        let note = first.addNote(text: "blossom")
        let second = makeTree(in: context, species: "Pear")
        try context.save()

        let captured = Date(timeIntervalSince1970: 1_700_000_000)
        let queue = makeQueue(container)
        let accepted = await queue.enqueue([
            deferred([1], tree: first.id, captured: captured),
            deferred([2], tree: first.id, note: note.id),
            deferred([3], tree: second.id),
        ])
        XCTAssertEqual(accepted, 3)
        await queue.waitUntilIdle()

        XCTAssertFalse(queue.isRunning)
        XCTAssertNil(queue.failureMessage)
        XCTAssertEqual(first.treePhotos.map(\.imageData), [Data([1])])
        XCTAssertEqual(first.treePhotos.first?.captureDate, captured)
        XCTAssertEqual(note.notePhotos.map(\.imageData), [Data([2])])
        XCTAssertEqual(second.treePhotos.map(\.imageData), [Data([3])])
        XCTAssertEqual(spooledFileNames(), [])
    }

    func testInvalidPhotoDataIsDropped() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tree = makeTree(in: context)
        try context.save()

        let queue = makeQueue(container)
        let accepted = await queue.enqueue([
            TreeImportService.DeferredPhoto(treeID: tree.id, noteID: nil, base64: "not base64!", captureDate: nil),
            deferred([7], tree: tree.id),
        ])
        XCTAssertEqual(accepted, 1)
        await queue.waitUntilIdle()

        XCTAssertEqual(tree.treePhotos.map(\.imageData), [Data([7])])
    }

    /// A tree or note deleted before its turn is skipped, not an error, and
    /// its spooled files are cleaned up.
    func testMissingTargetsAreSkipped() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tree = makeTree(in: context)
        let doomed = makeTree(in: context, species: "Plum")
        let doomedID = doomed.id
        try context.save()
        context.delete(doomed)
        try context.save()

        let queue = makeQueue(container)
        await queue.enqueue([
            deferred([1], tree: doomedID),
            deferred([2], tree: UUID()),
            deferred([3], tree: tree.id, note: UUID()),
            deferred([4], tree: tree.id),
        ])
        await queue.waitUntilIdle()

        XCTAssertNil(queue.failureMessage)
        XCTAssertEqual(tree.treePhotos.map(\.imageData), [Data([4])])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Photo>()).count, 1)
        XCTAssertEqual(spooledFileNames(), [])
    }

    /// Photos spooled in an earlier session (manifest on disk, nothing in
    /// memory) are attached by resume(); files the manifest doesn't know
    /// about are removed.
    func testResumeContinuesInterruptedImport() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tree = makeTree(in: context)
        try context.save()

        let entries = PendingPhotoImportQueue.spool(
            [deferred([1], tree: tree.id), deferred([2], tree: tree.id)],
            into: directory
        )
        PendingPhotoImportQueue.writeManifest(entries, in: directory)
        let orphan = directory.appending(path: "orphan.photo")
        try Data([9]).write(to: orphan)

        let queue = makeQueue(container)
        queue.resume()
        XCTAssertTrue(queue.isRunning)
        XCTAssertEqual(queue.totalCount, 2)
        await queue.waitUntilIdle()

        XCTAssertEqual(tree.treePhotos.map(\.imageData), [Data([1]), Data([2])])
        XCTAssertEqual(spooledFileNames(), [])
    }

    func testResumeWithNothingPendingDoesNothing() throws {
        let container = try makeContainer()
        let queue = makeQueue(container)
        queue.resume()
        XCTAssertFalse(queue.isRunning)
        XCTAssertEqual(queue.totalCount, 0)
    }
}
