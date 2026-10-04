import XCTest
import SwiftData
@testable import Trees

@MainActor
final class JSONRoundTripTests: XCTestCase {

    // ModelContext does not keep its container alive, so tests must hold the
    // container itself; using a context whose container deallocated traps in SwiftData.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: TreesSchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private let treePhotoData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01])
    private let notePhotoData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x02])

    /// Exporting and re-importing a v2 file must preserve note structure, note
    /// dates, photo ownership (tree vs note), photo capture dates, and
    /// collection membership.
    func testV2RoundTripPreservesEverything() throws {
        let sourceContainer = try makeContainer()
        let sourceContext = sourceContainer.mainContext

        let collection = Collection(name: "Orchard")
        sourceContext.insert(collection)

        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let tree = Tree(
            latitude: 51.5, longitude: -0.12, horizontalAccuracy: 4.2,
            altitude: 33.0, species: "Apple", variety: "Bramley", rootstock: "M25",
            createdAt: createdAt, updatedAt: createdAt
        )
        tree.collection = collection
        sourceContext.insert(tree)

        let photoCapture = Date(timeIntervalSince1970: 1_700_001_000)
        tree.addPhoto(treePhotoData, capturedAt: photoCapture)

        let firstNoteDate = Date(timeIntervalSince1970: 1_700_002_000)
        let firstNote = Note(text: "First blossom", createdAt: firstNoteDate, updatedAt: firstNoteDate)
        firstNote.tree = tree
        tree.notes = [firstNote]
        firstNote.addPhoto(notePhotoData)

        let secondNoteDate = Date(timeIntervalSince1970: 1_700_003_000)
        let secondNote = Note(text: "Fruit set", createdAt: secondNoteDate, updatedAt: secondNoteDate)
        secondNote.tree = tree
        tree.notes?.append(secondNote)

        try sourceContext.save()

        let json = JSONExporter.export(trees: [tree], collections: [collection], includePhotos: true)
        let archive = try XCTUnwrap(TreeImportService.decode(Data(json.utf8)))
        XCTAssertEqual(archive.version, 2)

        let destContainer = try makeContainer()
        let destContext = destContainer.mainContext
        let service = TreeImportService(modelContext: destContext)
        let summary = try service.importArchive(archive, photoHandling: .immediate)

        XCTAssertEqual(summary.importedCount, 1)
        XCTAssertEqual(summary.collectionsCreated, 1)
        XCTAssertEqual(summary.photoCount, 2)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertEqual(summary.remappedIDCount, 0)

        let imported = try XCTUnwrap(try destContext.fetch(FetchDescriptor<Tree>()).first)
        XCTAssertEqual(imported.id, tree.id)
        XCTAssertEqual(imported.species, "Apple")
        XCTAssertEqual(imported.variety, "Bramley")
        XCTAssertEqual(imported.rootstock, "M25")
        XCTAssertEqual(imported.latitude, 51.5)
        XCTAssertEqual(imported.longitude, -0.12)
        XCTAssertEqual(imported.altitude, 33.0)
        // ISO8601 truncates to whole seconds
        XCTAssertEqual(imported.createdAt.timeIntervalSince1970, createdAt.timeIntervalSince1970, accuracy: 1.0)

        // Collection membership and identity
        let importedCollection = try XCTUnwrap(imported.collection)
        XCTAssertEqual(importedCollection.name, "Orchard")
        XCTAssertEqual(importedCollection.id, collection.id)

        // Note structure with original dates
        let notes = imported.treeNotes.sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(notes.map(\.text), ["First blossom", "Fruit set"])
        XCTAssertEqual(notes[0].createdAt.timeIntervalSince1970, firstNoteDate.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(notes[1].createdAt.timeIntervalSince1970, secondNoteDate.timeIntervalSince1970, accuracy: 1.0)

        // Photo ownership: one on the tree, one on the first note
        XCTAssertEqual(imported.treePhotos.count, 1)
        XCTAssertEqual(imported.treePhotos.first?.imageData, treePhotoData)
        let importedCaptureDate = try XCTUnwrap(imported.treePhotos.first?.captureDate)
        XCTAssertEqual(importedCaptureDate.timeIntervalSince1970, photoCapture.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(notes[0].notePhotos.count, 1)
        XCTAssertEqual(notes[0].notePhotos.first?.imageData, notePhotoData)
        XCTAssertEqual(notes[1].notePhotos.count, 0)
    }

    /// v1 files (no version field, combined notes string, flat photo arrays)
    /// must still import.
    func testV1FormatStillImports() throws {
        let photoBase64 = treePhotoData.base64EncodedString()
        let json = """
        {
          "collections": [{"id": "11111111-1111-1111-1111-111111111111", "name": "Old Orchard"}],
          "trees": [{
            "id": "22222222-2222-2222-2222-222222222222",
            "latitude": 51.0, "longitude": -1.0, "horizontalAccuracy": 5.0,
            "species": "Pear", "notes": "note one | note two",
            "photos": ["\(photoBase64)"],
            "photoDates": ["2026-01-02T03:04:05Z"],
            "collectionId": "11111111-1111-1111-1111-111111111111",
            "createdAt": "2026-01-01T00:00:00Z"
          }]
        }
        """

        let archive = try XCTUnwrap(TreeImportService.decode(Data(json.utf8)))
        XCTAssertNil(archive.version)

        let container = try makeContainer()
        let context = container.mainContext
        let summary = try TreeImportService(modelContext: context).importArchive(archive, photoHandling: .immediate)

        XCTAssertEqual(summary.importedCount, 1)
        let imported = try XCTUnwrap(try context.fetch(FetchDescriptor<Tree>()).first)
        XCTAssertEqual(imported.species, "Pear")
        XCTAssertEqual(imported.treeNotes.map(\.text), ["note one | note two"])
        XCTAssertEqual(imported.treePhotos.count, 1)
        XCTAssertEqual(imported.treePhotos.first?.captureDate, ImportDateParser.date(from: "2026-01-02T03:04:05Z"))
        XCTAssertEqual(imported.collection?.name, "Old Orchard")
    }

    /// The oldest format — a bare tree array — must still import.
    func testLegacyBareArrayImports() throws {
        let json = """
        [{"latitude": 50.0, "longitude": 0.5, "horizontalAccuracy": 3.0, "species": "Oak", "notes": ""}]
        """

        let archive = try XCTUnwrap(TreeImportService.decode(Data(json.utf8)))
        let container = try makeContainer()
        let context = container.mainContext
        let summary = try TreeImportService(modelContext: context).importArchive(archive, photoHandling: .none)

        XCTAssertEqual(summary.importedCount, 1)
        let imported = try XCTUnwrap(try context.fetch(FetchDescriptor<Tree>()).first)
        XCTAssertEqual(imported.species, "Oak")
        XCTAssertTrue(imported.treeNotes.isEmpty)
    }

    /// Dates with fractional seconds must parse instead of silently becoming "now".
    func testFractionalSecondDatesParse() throws {
        let parsed = try XCTUnwrap(ImportDateParser.date(from: "2026-01-02T03:04:05.123Z"))
        let expected = try XCTUnwrap(ImportDateParser.date(from: "2026-01-02T03:04:05Z"))
        XCTAssertEqual(parsed.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.5)

        let json = """
        [{"latitude": 50.0, "longitude": 0.5, "horizontalAccuracy": 3.0, "species": "Ash", "notes": "",
          "createdAt": "2026-01-02T03:04:05.123Z"}]
        """
        let archive = try XCTUnwrap(TreeImportService.decode(Data(json.utf8)))
        let container = try makeContainer()
        let context = container.mainContext
        _ = try TreeImportService(modelContext: context).importArchive(archive, photoHandling: .none)
        let imported = try XCTUnwrap(try context.fetch(FetchDescriptor<Tree>()).first)
        XCTAssertEqual(imported.createdAt.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1.0)
    }

    /// Re-importing the same archive must not duplicate collections, and under
    /// the remap policy trees whose IDs already exist are imported as copies.
    func testReimportDoesNotDuplicateCollections() throws {
        let json = """
        {
          "version": 2,
          "collections": [{"id": "33333333-3333-3333-3333-333333333333", "name": "Orchard"}],
          "trees": [{
            "id": "44444444-4444-4444-4444-444444444444",
            "latitude": 51.0, "longitude": -1.0, "horizontalAccuracy": 5.0,
            "species": "Plum", "notes": "",
            "collectionId": "33333333-3333-3333-3333-333333333333"
          }]
        }
        """
        let archive = try XCTUnwrap(TreeImportService.decode(Data(json.utf8)))
        let container = try makeContainer()
        let context = container.mainContext
        let service = TreeImportService(modelContext: context)

        let first = try service.importArchive(archive, photoHandling: .none)
        XCTAssertEqual(first.collectionsCreated, 1)
        XCTAssertEqual(first.remappedIDCount, 0)

        let second = try service.importArchive(archive, photoHandling: .none, existingIDPolicy: .remap)
        XCTAssertEqual(second.collectionsCreated, 0)
        XCTAssertEqual(second.remappedIDCount, 1)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Collection>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Tree>()).count, 2)
    }

    /// By default, re-importing the same archive leaves existing trees alone.
    func testReimportSkipsTreesAlreadyPresent() throws {
        let json = """
        {
          "version": 2,
          "collections": [],
          "trees": [
            {"id": "55555555-5555-5555-5555-555555555555",
             "latitude": 51.0, "longitude": -1.0, "horizontalAccuracy": 5.0, "species": "Plum", "notes": ""},
            {"id": "55555555-5555-5555-5555-555555555555",
             "latitude": 51.1, "longitude": -1.1, "horizontalAccuracy": 5.0, "species": "Plum copy", "notes": ""}
          ]
        }
        """
        let archive = try XCTUnwrap(TreeImportService.decode(Data(json.utf8)))
        let container = try makeContainer()
        let context = container.mainContext
        let service = TreeImportService(modelContext: context)

        // An ID repeated inside the file is still remapped on first import
        let first = try service.importArchive(archive, photoHandling: .none)
        XCTAssertEqual(first.importedCount, 2)
        XCTAssertEqual(first.remappedIDCount, 1)
        XCTAssertEqual(first.alreadyPresentCount, 0)

        let second = try service.importArchive(archive, photoHandling: .none)
        XCTAssertEqual(second.importedCount, 0)
        XCTAssertEqual(second.alreadyPresentCount, 2)
        XCTAssertEqual(second.remappedIDCount, 0)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Tree>()).count, 2)
    }

    /// Photo lists come back in the order the photos were added, and that order
    /// survives an export/import round trip.
    func testPhotoOrderIsStableAcrossRoundTrip() throws {
        let sourceContainer = try makeContainer()
        let sourceContext = sourceContainer.mainContext
        let tree = Tree(latitude: 51.5, longitude: -0.12, horizontalAccuracy: 4.0, species: "Apple")
        sourceContext.insert(tree)

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let payloads = (0..<6).map { Data([0xFF, 0xD8, UInt8($0)]) }
        // Insert in scrambled order; createdAt defines the expected order
        for index in [3, 0, 5, 1, 4, 2] {
            let photo = Photo(imageData: payloads[index], createdAt: base.addingTimeInterval(Double(index)))
            photo.tree = tree
            sourceContext.insert(photo)
        }
        try sourceContext.save()
        XCTAssertEqual(tree.treePhotos.map(\.imageData), payloads)

        let json = JSONExporter.export(trees: [tree], includePhotos: true)
        let archive = try XCTUnwrap(TreeImportService.decode(Data(json.utf8)))
        let destContainer = try makeContainer()
        let destContext = destContainer.mainContext
        _ = try TreeImportService(modelContext: destContext).importArchive(archive, photoHandling: .immediate)

        let imported = try XCTUnwrap(try destContext.fetch(FetchDescriptor<Tree>()).first)
        XCTAssertEqual(imported.treePhotos.map(\.imageData), payloads)
    }

    /// Deferred mode must hand photos back to the caller, addressed by tree
    /// and note ID, instead of attaching them.
    func testDeferredModeReturnsPhotosByTargetID() throws {
        let treeBase64 = treePhotoData.base64EncodedString()
        let noteBase64 = notePhotoData.base64EncodedString()
        let json = """
        {"version": 2, "collections": [], "trees": [{
          "latitude": 50.0, "longitude": 0.5, "horizontalAccuracy": 3.0, "species": "Oak", "notes": "n",
          "noteEntries": [{"text": "n", "photos": [{"data": "\(noteBase64)"}]}],
          "treePhotos": [{"data": "\(treeBase64)", "captureDate": "2026-01-02T03:04:05Z"}]
        }]}
        """
        let archive = try XCTUnwrap(TreeImportService.decode(Data(json.utf8)))
        let container = try makeContainer()
        let context = container.mainContext
        let summary = try TreeImportService(modelContext: context).importArchive(archive, photoHandling: .deferred)

        let imported = try XCTUnwrap(try context.fetch(FetchDescriptor<Tree>()).first)
        let note = try XCTUnwrap(imported.treeNotes.first)
        XCTAssertTrue(imported.allPhotos.isEmpty)

        XCTAssertEqual(summary.photoCount, 2)
        XCTAssertEqual(summary.deferredPhotos.count, 2)
        XCTAssertTrue(summary.deferredPhotos.allSatisfy { $0.treeID == imported.id })

        let notePhoto = try XCTUnwrap(summary.deferredPhotos.first { $0.noteID != nil })
        XCTAssertEqual(notePhoto.noteID, note.id)
        XCTAssertEqual(notePhoto.base64, noteBase64)

        let treePhoto = try XCTUnwrap(summary.deferredPhotos.first { $0.noteID == nil })
        XCTAssertEqual(treePhoto.base64, treeBase64)
        XCTAssertEqual(treePhoto.captureDate, ImportDateParser.date(from: "2026-01-02T03:04:05Z"))
    }

    /// Invalid coordinates are skipped, not imported.
    func testInvalidCoordinatesSkipped() throws {
        let json = """
        [{"latitude": 91.0, "longitude": 0.5, "horizontalAccuracy": 3.0, "species": "Bad", "notes": ""}]
        """
        let archive = try XCTUnwrap(TreeImportService.decode(Data(json.utf8)))
        let container = try makeContainer()
        let context = container.mainContext
        let summary = try TreeImportService(modelContext: context).importArchive(archive, photoHandling: .none)

        XCTAssertEqual(summary.importedCount, 0)
        XCTAssertEqual(summary.skippedCount, 1)
    }
}
