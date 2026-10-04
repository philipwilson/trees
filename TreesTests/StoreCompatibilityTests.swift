import XCTest
import SwiftData
@testable import Trees

/// Guards against schema changes that strand existing users' data.
///
/// `Fixtures/TreesSchemaV1.store` is a real on-disk store written by the app's
/// models as they were at schema V1 (October 2026). It must never be
/// regenerated: every future schema version has to open it through
/// `TreesMigrationPlan` and still find this data. When a new schema version
/// ships, add a frozen fixture for it alongside this one.
///
/// Fixture contents:
/// - Collection "Orchard"
/// - Tree "Apple" (Bramley / M25) in Orchard, with one photo of its own and
///   one note, "First blossom", which has one photo
/// - Tree "Pear" with no collection, variety, rootstock, altitude, notes or photos
@MainActor
final class StoreCompatibilityTests: XCTestCase {
    private var workingDirectory: URL!

    override func setUp() async throws {
        workingDirectory = FileManager.default.temporaryDirectory
            .appending(path: "StoreCompatibilityTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: workingDirectory)
    }

    /// Opens a copy of the fixture the way the app opens its store: latest
    /// schema, with the migration plan. Returns the container; tests must hold it.
    private func openCopyOfFixture(_ name: String) throws -> ModelContainer {
        let fixture = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "store"),
            "Fixture \(name).store is missing from the test bundle"
        )
        let copy = workingDirectory.appending(path: "\(name).store")
        try FileManager.default.copyItem(at: fixture, to: copy)

        let latest = try XCTUnwrap(TreesMigrationPlan.schemas.last)
        let schema = Schema(versionedSchema: latest)
        let config = ModelConfiguration(schema: schema, url: copy, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: TreesMigrationPlan.self, configurations: [config])
    }

    func testV1StoreOpensWithCurrentSchemaAndKeepsItsData() throws {
        let container = try openCopyOfFixture("TreesSchemaV1")
        let context = container.mainContext

        let collections = try context.fetch(FetchDescriptor<Trees.Collection>())
        XCTAssertEqual(collections.map(\.name), ["Orchard"])
        XCTAssertEqual(collections.first?.id, UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001"))

        let trees = try context.fetch(FetchDescriptor<Tree>(sortBy: [SortDescriptor(\.createdAt)]))
        XCTAssertEqual(trees.map(\.species), ["Apple", "Pear"])

        let apple = trees[0]
        XCTAssertEqual(apple.id, UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001"))
        XCTAssertEqual(apple.latitude, 51.5)
        XCTAssertEqual(apple.longitude, -0.12)
        XCTAssertEqual(apple.horizontalAccuracy, 4.2)
        XCTAssertEqual(apple.altitude, 33.0)
        XCTAssertEqual(apple.variety, "Bramley")
        XCTAssertEqual(apple.rootstock, "M25")
        XCTAssertEqual(apple.createdAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(apple.updatedAt, Date(timeIntervalSince1970: 1_700_005_000))
        XCTAssertEqual(apple.collection?.name, "Orchard")
        XCTAssertEqual(collections.first?.treeCount, 1)

        XCTAssertEqual(apple.treePhotos.map(\.imageData), [Data([0xFF, 0xD8, 0x01])])
        XCTAssertEqual(apple.treePhotos.first?.captureDate, Date(timeIntervalSince1970: 1_700_001_000))

        let note = try XCTUnwrap(apple.treeNotes.first)
        XCTAssertEqual(apple.treeNotes.count, 1)
        XCTAssertEqual(note.text, "First blossom")
        XCTAssertEqual(note.createdAt, Date(timeIntervalSince1970: 1_700_002_000))
        XCTAssertEqual(note.notePhotos.map(\.imageData), [Data([0xFF, 0xD8, 0x02])])
        XCTAssertNil(note.notePhotos.first?.captureDate)

        let pear = trees[1]
        XCTAssertEqual(pear.id, UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002"))
        XCTAssertEqual(pear.latitude, -33.9)
        XCTAssertEqual(pear.longitude, 151.2)
        XCTAssertNil(pear.altitude)
        XCTAssertNil(pear.variety)
        XCTAssertNil(pear.rootstock)
        XCTAssertNil(pear.collection)
        XCTAssertTrue(pear.allPhotos.isEmpty)
        XCTAssertTrue(pear.treeNotes.isEmpty)
    }

    /// The opened store must also be writable: a migration that leaves the
    /// store readable but unsaveable would still break the app.
    func testV1StoreAcceptsNewDataAfterOpening() throws {
        let container = try openCopyOfFixture("TreesSchemaV1")
        let context = container.mainContext

        let apple = try XCTUnwrap(try context.fetch(FetchDescriptor<Tree>()).first { $0.species == "Apple" })
        _ = apple.addNote(text: "Added after upgrade", photos: [Data([0xFF, 0xD8, 0x03])])
        context.insert(Tree(latitude: 1, longitude: 2, horizontalAccuracy: 3, species: "Plum"))
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Tree>()).count, 3)
        XCTAssertEqual(apple.treeNotes.count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Photo>()).count, 3)
    }
}
