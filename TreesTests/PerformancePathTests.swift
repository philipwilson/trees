import XCTest
import SwiftData
import ImageIO
import UniformTypeIdentifiers
@testable import Trees

/// Covers the pieces that keep heavy work off the main thread and out of
/// view bodies: the ID-keyed thumbnail cache, the background export worker,
/// the shared search matcher, and the unassigned-trees query.
@MainActor
final class PerformancePathTests: XCTestCase {

    // ModelContext does not keep its container alive, so tests must hold the
    // container itself; using a context whose container deallocated traps in SwiftData.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: TreesSchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeJPEG(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.jpegData(withCompressionQuality: 0.8) { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    // MARK: - Thumbnails

    func testThumbnailIsDownsampledAndCachedByID() async throws {
        let id = UUID()
        let data = makeJPEG(width: 800, height: 400)
        XCTAssertNil(ImageDownsampler.cachedThumbnail(id: id, maxDimension: 50))

        let generated = await ImageDownsampler.thumbnail(id: id, data: data, maxDimension: 50, scale: 2)
        let thumbnail = try XCTUnwrap(generated)
        XCTAssertEqual(thumbnail.cgImage?.width, 100)
        XCTAssertEqual(thumbnail.cgImage?.height, 50)

        // A cache hit needs only the ID: the lookup works with no data at all
        XCTAssertTrue(ImageDownsampler.cachedThumbnail(id: id, maxDimension: 50) === thumbnail)
        let again = await ImageDownsampler.thumbnail(id: id, data: Data(), maxDimension: 50, scale: 2)
        XCTAssertTrue(again === thumbnail)

        // Sizes and IDs are cached independently
        XCTAssertNil(ImageDownsampler.cachedThumbnail(id: id, maxDimension: 120))
        XCTAssertNil(ImageDownsampler.cachedThumbnail(id: UUID(), maxDimension: 50))
    }

    /// Two photos with identical bytes must not share a cache entry by accident
    /// of content; each ID gets its own.
    func testSameLengthPhotosDoNotCollide() async throws {
        let wide = makeJPEG(width: 600, height: 200)
        let tall = makeJPEG(width: 200, height: 600)
        let wideID = UUID(), tallID = UUID()

        let wideThumb = await ImageDownsampler.thumbnail(id: wideID, data: wide, maxDimension: 60, scale: 1)
        let tallThumb = await ImageDownsampler.thumbnail(id: tallID, data: tall, maxDimension: 60, scale: 1)

        XCTAssertEqual(wideThumb?.cgImage?.width, 60)
        XCTAssertEqual(tallThumb?.cgImage?.height, 60)
        XCTAssertFalse(wideThumb === tallThumb)
    }

    func testThumbnailOfInvalidDataIsNilAndNotCached() async {
        let id = UUID()
        let result = await ImageDownsampler.thumbnail(id: id, data: Data([1, 2, 3]), maxDimension: 50, scale: 2)
        XCTAssertNil(result)
        XCTAssertNil(ImageDownsampler.cachedThumbnail(id: id, maxDimension: 50))
    }

    // MARK: - Picked photo capture date

    func testCaptureDateIsReadFromPhotoMetadata() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "exif-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try XCTUnwrap(UIImage(data: makeJPEG(width: 8, height: 8))?.cgImage)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2021:06:15 14:30:05"]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let date = try XCTUnwrap(ImagePicker.Coordinator.originalCaptureDate(ofImageAt: url))
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second],
                       [2021, 6, 15, 14, 30, 5])
    }

    func testCaptureDateIsNilWithoutMetadata() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "noexif-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try makeJPEG(width: 8, height: 8).write(to: url)

        XCTAssertNil(ImagePicker.Coordinator.originalCaptureDate(ofImageAt: url))
    }

    // MARK: - Background export

    func testExportWorkerExportsSavedModelsByIdentifier() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let collection = Collection(name: "Orchard")
        context.insert(collection)
        let apple = Tree(latitude: 51.5, longitude: -0.12, horizontalAccuracy: 4.0, species: "Apple")
        context.insert(apple)
        apple.collection = collection
        apple.addPhoto(Data([0xFF, 0xD8, 0x01]))
        let pear = Tree(latitude: 50.0, longitude: 1.0, horizontalAccuracy: 6.0, species: "Pear")
        context.insert(pear)
        let unexported = Tree(latitude: 49.0, longitude: 2.0, horizontalAccuracy: 6.0, species: "Plum")
        context.insert(unexported)
        try context.save()

        let treeIDs = [pear.persistentModelID, apple.persistentModelID]
        let collectionIDs = [collection.persistentModelID]

        let worker = ExportWorker(modelContainer: container)
        let exportedURL = await worker.export(
            format: .json, treeIDs: treeIDs, collectionIDs: collectionIDs, includePhotos: true, filePrefix: "worker-test"
        )
        let jsonURL = try XCTUnwrap(exportedURL)
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        let archive = try XCTUnwrap(TreeImportService.decode(try Data(contentsOf: jsonURL)))
        XCTAssertEqual(archive.trees.map(\.species), ["Pear", "Apple"], "order of the requested IDs is kept")
        XCTAssertEqual(archive.collections?.map(\.name), ["Orchard"])
        XCTAssertEqual(archive.trees[1].treePhotos?.count, 1)
        XCTAssertEqual(archive.trees[1].collectionId, collection.id.uuidString)

        let csvExportedURL = await worker.export(
            format: .csv, treeIDs: treeIDs, collectionIDs: [], includePhotos: false, filePrefix: "worker-test"
        )
        let csvURL = try XCTUnwrap(csvExportedURL)
        defer { try? FileManager.default.removeItem(at: csvURL) }
        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        XCTAssertTrue(csv.contains(",Pear,"))
        XCTAssertTrue(csv.contains(",Apple,"))
        XCTAssertFalse(csv.contains("Plum"))
    }

    // MARK: - Search

    func testSearchMatchesSpeciesVarietyAndNotesIgnoringCaseAndAccents() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tree = Tree(latitude: 51.5, longitude: -0.12, horizontalAccuracy: 4.0, species: "Apple", variety: "Belle de Boskoop")
        context.insert(tree)
        _ = tree.addNote(text: "Planted by the café wall")

        XCTAssertTrue(tree.matches(searchText: "app"))
        XCTAssertTrue(tree.matches(searchText: "BOSKOOP"))
        XCTAssertTrue(tree.matches(searchText: "cafe"))
        XCTAssertFalse(tree.matches(searchText: "pear"))

        let bare = Tree(latitude: 51.5, longitude: -0.12, horizontalAccuracy: 4.0, species: "Pear")
        context.insert(bare)
        XCTAssertFalse(bare.matches(searchText: "boskoop"))
    }

    // MARK: - Unassigned trees

    /// The predicate CollectionDetailView's query uses to find trees that can
    /// be added to a collection.
    func testUnassignedTreesPredicateExcludesTreesInACollection() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let collection = Collection(name: "Orchard")
        context.insert(collection)
        let assigned = Tree(latitude: 51.5, longitude: -0.12, horizontalAccuracy: 4.0, species: "Apple")
        context.insert(assigned)
        assigned.collection = collection
        let free = Tree(latitude: 50.0, longitude: 1.0, horizontalAccuracy: 6.0, species: "Pear")
        context.insert(free)
        try context.save()

        let descriptor = FetchDescriptor<Tree>(predicate: #Predicate<Tree> { $0.collection == nil })
        XCTAssertEqual(try context.fetch(descriptor).map(\.id), [free.id])

        assigned.collection = nil
        try context.save()
        XCTAssertEqual(Set(try context.fetch(descriptor).map(\.id)), [free.id, assigned.id])
    }
}
