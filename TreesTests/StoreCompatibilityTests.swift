import XCTest
import SwiftData
import CoreData
@testable import Trees

/// Guards against schema changes that strand existing users' data.
///
/// The current schema is version 2, so opening this fixture runs the real
/// V1 → V2 migration.
///
/// `Fixtures/TreesSchemaV1.store` is a real on-disk store written by the app's
/// models as they were at schema V1 (October 2026). The fixtures must never be
/// regenerated: every future schema version has to open them through
/// `TreesMigrationPlan` and still find this data. When a new schema version
/// ships, add a frozen fixture for it alongside these.
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
        XCTAssertNil(apple.label, "fields added after V1 start out empty")
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

    /// `Fixtures/TreesSchemaV2.store` was written by schema version 2 (which
    /// added `Tree.label`), frozen in October 2026. Contents: collection
    /// "Fruit Cage"; "Blackcurrant" (Ben Sarek, label "Row 3, bush 4") in it
    /// with one photo and one note; "Honeyberry" with no label, collection,
    /// or known accuracy.
    func testV2StoreOpensWithCurrentSchemaAndKeepsItsData() throws {
        let container = try openCopyOfFixture("TreesSchemaV2")
        let context = container.mainContext

        let trees = try context.fetch(FetchDescriptor<Tree>(sortBy: [SortDescriptor(\.createdAt)]))
        XCTAssertEqual(trees.map(\.species), ["Blackcurrant", "Honeyberry"])

        let currant = trees[0]
        XCTAssertEqual(currant.id, UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000011"))
        XCTAssertEqual(currant.label, "Row 3, bush 4")
        XCTAssertEqual(currant.variety, "Ben Sarek")
        XCTAssertNil(currant.rootstock)
        XCTAssertEqual(currant.horizontalAccuracy, 3.1)
        XCTAssertEqual(currant.altitude, 20.0)
        XCTAssertEqual(currant.createdAt, Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertEqual(currant.collection?.name, "Fruit Cage")
        XCTAssertEqual(currant.treePhotos.map(\.imageData), [Data([0xFF, 0xD8, 0x11])])
        XCTAssertEqual(currant.treeNotes.map(\.text), ["First fruit"])

        let honeyberry = trees[1]
        XCTAssertNil(honeyberry.label)
        XCTAssertNil(honeyberry.collection)
        XCTAssertFalse(honeyberry.hasKnownAccuracy)

        honeyberry.label = "By the gate"
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Tree>(predicate: #Predicate { $0.label == "By the gate" })).count, 1)
    }

    /// The opened store must also be writable: a migration that leaves the
    /// store readable but unsaveable would still break the app.
    func testV1StoreAcceptsNewDataAfterOpening() throws {
        let container = try openCopyOfFixture("TreesSchemaV1")
        let context = container.mainContext

        let apple = try XCTUnwrap(try context.fetch(FetchDescriptor<Tree>()).first { $0.species == "Apple" })
        _ = apple.addNote(text: "Added after upgrade", photos: [Data([0xFF, 0xD8, 0x03])])
        apple.label = "Row 1, tree 1"
        context.insert(Tree(latitude: 1, longitude: 2, horizontalAccuracy: 3, species: "Plum"))
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Tree>()).count, 3)
        XCTAssertEqual(apple.treeNotes.count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Photo>()).count, 3)

        // A field added by a later schema version can be written and read back
        let labelled = FetchDescriptor<Tree>(predicate: #Predicate { $0.label == "Row 1, tree 1" })
        XCTAssertEqual(try context.fetch(labelled).map(\.species), ["Apple"])
    }
}

/// The model handed to CloudKit schema initialisation must describe the same
/// entities and stored fields the app uses, or the deployed schema would be
/// missing some.
final class CloudKitSchemaModelTests: XCTestCase {
    func testManagedObjectModelCoversEveryEntityAndField() throws {
        let model = try XCTUnwrap(CloudKitSchemaInitializer.makeManagedObjectModel())
        let entities = Dictionary(uniqueKeysWithValues: model.entities.compactMap { entity in
            entity.name.map { ($0, entity) }
        })

        XCTAssertEqual(Set(entities.keys), ["Tree", "Note", "Photo", "Collection"])

        func fields(_ name: String) -> Set<String> {
            Set(entities[name]?.propertiesByName.keys.map { $0 } ?? [])
        }
        XCTAssertEqual(fields("Tree"), [
            "id", "latitude", "longitude", "horizontalAccuracy", "altitude", "species", "variety",
            "rootstock", "label", "createdAt", "updatedAt", "collection", "photos", "notes",
        ])
        XCTAssertEqual(fields("Note"), ["id", "text", "createdAt", "updatedAt", "tree", "photos"])
        XCTAssertEqual(fields("Photo"), ["id", "imageData", "captureDate", "createdAt", "tree", "note"])
        XCTAssertEqual(fields("Collection"), ["id", "name", "createdAt", "updatedAt", "trees"])
    }

    /// CloudKit requires every relationship to be optional and to have an inverse.
    func testEveryRelationshipIsOptionalWithAnInverse() throws {
        let model = try XCTUnwrap(CloudKitSchemaInitializer.makeManagedObjectModel())
        for entity in model.entities {
            for (name, relationship) in entity.relationshipsByName {
                XCTAssertTrue(relationship.isOptional, "\(entity.name ?? "?").\(name) must be optional")
                XCTAssertNotNil(relationship.inverseRelationship, "\(entity.name ?? "?").\(name) needs an inverse")
            }
        }
    }

    @MainActor
    func testExportFileNamesUseA24HourTimestamp() throws {
        let schema = Schema(versionedSchema: CurrentTreesSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let tree = Tree(latitude: 51.5, longitude: -0.12, horizontalAccuracy: 4, species: "Oak")
        container.mainContext.insert(tree)

        let url = try XCTUnwrap(CSVExporter.exportToFile(trees: [tree], filePrefix: "name-test"))
        defer { try? FileManager.default.removeItem(at: url) }

        let name = url.lastPathComponent
        XCTAssertNotNil(name.range(of: #"^name-test_\d{4}-\d{2}-\d{2}_\d{6}_\d{3}\.csv$"#, options: .regularExpression), name)
    }
}
