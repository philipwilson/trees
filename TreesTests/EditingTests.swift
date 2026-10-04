import XCTest
import SwiftData
import CoreLocation
@testable import Trees

@MainActor
final class EditingTests: XCTestCase {

    // ModelContext does not keep its container alive, so tests must hold the
    // container itself; using a context whose container deallocated traps in SwiftData.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: TreesSchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private let longAgo = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeTree(in context: ModelContext) -> Tree {
        let tree = Tree(
            latitude: 51.5, longitude: -0.12, horizontalAccuracy: 18.0, altitude: 10,
            species: "Apple", createdAt: longAgo, updatedAt: longAgo
        )
        context.insert(tree)
        return tree
    }

    func testApplyLocationReplacesPositionAndStampsUpdate() throws {
        let container = try makeContainer()
        let tree = makeTree(in: container.mainContext)
        let fix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 51.50002, longitude: -0.12003),
            altitude: 42, horizontalAccuracy: 3.5, verticalAccuracy: 5, timestamp: Date()
        )

        tree.apply(location: fix)

        XCTAssertEqual(tree.latitude, 51.50002)
        XCTAssertEqual(tree.longitude, -0.12003)
        XCTAssertEqual(tree.horizontalAccuracy, 3.5)
        XCTAssertEqual(tree.altitude, 42)
        XCTAssertEqual(tree.createdAt, longAgo, "capture date is not rewritten")
        XCTAssertGreaterThan(tree.updatedAt, longAgo)
    }

    func testDistanceText() {
        XCTAssertEqual(UpdateLocationView.distanceText(3.24), "3.2 m")
        XCTAssertEqual(UpdateLocationView.distanceText(999.94), "999.9 m")
        XCTAssertEqual(UpdateLocationView.distanceText(1234), "1.23 km")
    }

    func testMoveBetweenCollectionsUpdatesMembershipAndTimestamps() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tree = makeTree(in: context)
        let north = Collection(name: "North", createdAt: longAgo, updatedAt: longAgo)
        let south = Collection(name: "South", createdAt: longAgo, updatedAt: longAgo)
        context.insert(north)
        context.insert(south)

        tree.move(to: north)
        try context.save()
        XCTAssertEqual(tree.collection?.name, "North")
        XCTAssertEqual(north.treeCount, 1)
        XCTAssertGreaterThan(north.updatedAt, longAgo)
        XCTAssertEqual(south.updatedAt, longAgo)

        tree.move(to: south)
        try context.save()
        XCTAssertEqual(north.treeCount, 0)
        XCTAssertEqual(south.treeCount, 1)
        XCTAssertGreaterThan(south.updatedAt, longAgo)

        tree.move(to: nil)
        try context.save()
        XCTAssertNil(tree.collection)
        XCTAssertEqual(south.treeCount, 0)
    }

    /// What the photo viewer's delete does: the photo row goes, and its owner
    /// no longer lists it.
    func testDeletingAPhotoRemovesItFromItsOwner() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tree = makeTree(in: context)
        tree.addPhoto(Data([1]))
        tree.addPhoto(Data([2]))
        let note = tree.addNote(text: "n", photos: [Data([3])])
        try context.save()

        context.delete(try XCTUnwrap(tree.treePhotos.first))
        context.delete(try XCTUnwrap(note.notePhotos.first))
        try context.save()

        XCTAssertEqual(tree.treePhotos.map(\.imageData), [Data([2])])
        XCTAssertTrue(note.notePhotos.isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Photo>()).count, 1)
        XCTAssertEqual(tree.treeNotes.count, 1, "deleting a note's photo leaves the note")
    }
}
