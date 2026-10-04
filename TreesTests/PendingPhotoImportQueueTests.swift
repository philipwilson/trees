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

    private func filesOnDisk() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    private struct StoreUnavailable: Error {}

    // MARK: - Normal operation

    func testDrainAttachesPhotosToTreesAndNotes() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = makeTree(in: context)
        let note = first.addNote(text: "blossom")
        let second = makeTree(in: context, species: "Pear")
        try context.save()

        let captured = Date(timeIntervalSince1970: 1_700_000_000)
        let queue = makeQueue(container)
        let outcome = await queue.enqueue([
            deferred([1], tree: first.id, captured: captured),
            deferred([2], tree: first.id, note: note.id),
            deferred([3], tree: second.id),
        ])
        XCTAssertEqual(outcome, .init(queued: 3, unreadable: 0, failed: 0))
        await queue.waitUntilIdle()

        XCTAssertFalse(queue.isRunning)
        XCTAssertNil(queue.failureMessage)
        XCTAssertEqual(first.treePhotos.map(\.imageData), [Data([1])])
        XCTAssertEqual(first.treePhotos.first?.captureDate, captured)
        XCTAssertEqual(note.notePhotos.map(\.imageData), [Data([2])])
        XCTAssertEqual(second.treePhotos.map(\.imageData), [Data([3])])
        XCTAssertEqual(filesOnDisk(), [])
    }

    func testInvalidPhotoDataIsCountedAsUnreadable() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tree = makeTree(in: context)
        try context.save()

        let queue = makeQueue(container)
        let outcome = await queue.enqueue([
            TreeImportService.DeferredPhoto(treeID: tree.id, noteID: nil, base64: "not base64!", captureDate: nil),
            deferred([7], tree: tree.id),
        ])
        XCTAssertEqual(outcome, .init(queued: 1, unreadable: 1, failed: 0))
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
        XCTAssertEqual(filesOnDisk(), [])
    }

    // MARK: - File names carry the target

    func testEntryRoundTripsThroughItsFileName() throws {
        let tree = UUID(), note = UUID()
        let captured = Date(timeIntervalSince1970: 1_700_000_000.25)

        let onNote = PendingPhotoImportQueue.Entry(order: "0001", treeID: tree, noteID: note, captureDate: captured)
        let parsed = try XCTUnwrap(PendingPhotoImportQueue.Entry(fileName: onNote.fileName))
        XCTAssertEqual(parsed.treeID, tree)
        XCTAssertEqual(parsed.noteID, note)
        XCTAssertEqual(parsed.captureDate, captured)

        let onTree = PendingPhotoImportQueue.Entry(order: "0002", treeID: tree, noteID: nil, captureDate: nil)
        let parsedTree = try XCTUnwrap(PendingPhotoImportQueue.Entry(fileName: onTree.fileName))
        XCTAssertNil(parsedTree.noteID)
        XCTAssertNil(parsedTree.captureDate)
    }

    func testUnrelatedFileNamesAreNotEntries() {
        for name in ["manifest.json", "notes.txt", "random.photo", "a~b~c~d.photo", ".DS_Store"] {
            XCTAssertNil(PendingPhotoImportQueue.Entry(fileName: name), name)
        }
    }

    // MARK: - Recovery

    /// Photos spooled in an earlier session are attached by resume(), in the
    /// order they were queued, with nothing in memory to go on.
    func testResumeContinuesInterruptedImport() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tree = makeTree(in: context)
        try context.save()

        let (entries, _) = PendingPhotoImportQueue.spool(
            [deferred([1], tree: tree.id), deferred([2], tree: tree.id)],
            into: directory
        )
        XCTAssertEqual(entries.count, 2)

        let queue = makeQueue(container)
        queue.resume()
        XCTAssertTrue(queue.isRunning)
        XCTAssertEqual(queue.totalCount, 2)
        await queue.waitUntilIdle()

        XCTAssertEqual(tree.treePhotos.map(\.imageData), [Data([1]), Data([2])])
        XCTAssertEqual(filesOnDisk(), [])
    }

    func testResumeWithNothingPendingDoesNothing() throws {
        let container = try makeContainer()
        let queue = makeQueue(container)
        queue.resume()
        XCTAssertFalse(queue.isRunning)
        XCTAssertEqual(queue.totalCount, 0)
        XCTAssertNil(queue.failureMessage)
    }

    /// Files the queue didn't create must never be deleted by it.
    func testResumeLeavesUnrelatedFilesAlone() async throws {
        let container = try makeContainer()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([9]).write(to: directory.appending(path: "something-else.photo"))
        try Data([9]).write(to: directory.appending(path: "notes.txt"))

        let queue = makeQueue(container)
        queue.resume()
        await queue.waitUntilIdle()

        XCTAssertEqual(filesOnDisk(), ["notes.txt", "something-else.photo"])
    }

    // MARK: - Failures keep the photos

    /// If the store can't be queried, that is not the same as the tree being
    /// gone: the photos stay on disk and are attached on a later launch.
    func testStoreLookupFailureKeepsPhotosForRetry() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tree = makeTree(in: context)
        try context.save()

        let failing = makeQueue(container)
        failing.fetchTree = { _, _ in throw StoreUnavailable() }
        await failing.enqueue([deferred([1], tree: tree.id), deferred([2], tree: tree.id)])
        await failing.waitUntilIdle()

        XCTAssertNotNil(failing.failureMessage)
        XCTAssertTrue(tree.treePhotos.isEmpty)
        XCTAssertEqual(filesOnDisk().count, 2, "photos must survive a failed lookup")

        // Next launch, with the store working again
        let recovered = makeQueue(container)
        recovered.resume()
        await recovered.waitUntilIdle()

        XCTAssertNil(recovered.failureMessage)
        XCTAssertEqual(tree.treePhotos.map(\.imageData), [Data([1]), Data([2])])
        XCTAssertEqual(filesOnDisk(), [])
    }

    /// One tree failing must not stop the others in the same run.
    func testFailureForOneTreeDoesNotBlockOthers() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let bad = makeTree(in: context, species: "Bad")
        let good = makeTree(in: context, species: "Good")
        try context.save()
        let badID = bad.id

        let queue = makeQueue(container)
        queue.fetchTree = { id, context in
            if id == badID { throw StoreUnavailable() }
            return try context.fetch(FetchDescriptor<Tree>(predicate: #Predicate { $0.id == id })).first
        }
        await queue.enqueue([deferred([1], tree: bad.id), deferred([2], tree: good.id)])
        await queue.waitUntilIdle()

        XCTAssertEqual(good.treePhotos.map(\.imageData), [Data([2])])
        XCTAssertTrue(bad.treePhotos.isEmpty)
        XCTAssertEqual(filesOnDisk().count, 1)
        XCTAssertTrue(queue.failureMessage?.hasPrefix("1 imported photo ") ?? false)
    }

    /// When photos can't be written at all, the caller is told how many were
    /// lost rather than getting a silent zero.
    func testSpoolingFailureIsReported() async throws {
        let container = try makeContainer()
        let tree = makeTree(in: container.mainContext)
        try container.mainContext.save()

        // A file where the directory should be makes it impossible to create
        try Data([0]).write(to: directory)

        let queue = makeQueue(container)
        let outcome = await queue.enqueue([deferred([1], tree: tree.id), deferred([2], tree: tree.id)])

        XCTAssertEqual(outcome, .init(queued: 0, unreadable: 0, failed: 2))
        XCTAssertFalse(queue.isRunning)

        let summary = ImportTreesView.photoQueueSummary(outcome)
        XCTAssertTrue(summary.contains("2 photos could not be stored"), summary)
        XCTAssertFalse(summary.contains("Adding"), summary)
    }

    func testImportSummaryWording() {
        XCTAssertEqual(ImportTreesView.photoQueueSummary(.init()), "")
        let mixed = ImportTreesView.photoQueueSummary(.init(queued: 5, unreadable: 1, failed: 0))
        XCTAssertTrue(mixed.contains("Adding 5 photos in the background"), mixed)
        XCTAssertTrue(mixed.contains("1 photo in the file was damaged"), mixed)
    }

    // MARK: - Legacy manifest (first version of the queue)

    private func writeLegacy(fileNames: [String], manifest: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, name) in fileNames.enumerated() {
            try Data([UInt8(index + 1)]).write(to: directory.appending(path: name))
        }
        try Data(manifest.utf8).write(to: directory.appending(path: PendingPhotoImportQueue.legacyManifestName))
    }

    func testLegacyManifestIsMigratedAndItsPhotosAttached() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tree = makeTree(in: context)
        try context.save()

        try writeLegacy(fileNames: ["AAA.photo", "BBB.photo"], manifest: """
        [{"fileName": "AAA.photo", "treeID": "\(tree.id.uuidString)"},
         {"fileName": "BBB.photo", "treeID": "\(tree.id.uuidString)"}]
        """)

        let queue = makeQueue(container)
        queue.resume()
        await queue.waitUntilIdle()

        XCTAssertNil(queue.failureMessage)
        XCTAssertEqual(tree.treePhotos.map(\.imageData), [Data([1]), Data([2])])
        XCTAssertEqual(filesOnDisk(), [])
    }

    /// A damaged manifest used to read as "nothing pending", after which the
    /// clean-up deleted every photo. The photos must be left on disk and the
    /// user told.
    func testCorruptLegacyManifestKeepsPhotosAndReports() async throws {
        let container = try makeContainer()
        try writeLegacy(fileNames: ["AAA.photo", "BBB.photo"], manifest: "{ this is not json")

        let queue = makeQueue(container)
        queue.resume()
        await queue.waitUntilIdle()

        XCTAssertTrue(queue.failureMessage?.hasPrefix("2 photos from an interrupted import") ?? false)
        let remaining = filesOnDisk()
        XCTAssertTrue(remaining.contains("AAA.photo"))
        XCTAssertTrue(remaining.contains("BBB.photo"))

        // Not reported again on the next launch
        let next = makeQueue(container)
        next.resume()
        XCTAssertNil(next.failureMessage)
        XCTAssertTrue(filesOnDisk().contains("AAA.photo"))
    }
}
