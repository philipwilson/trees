import XCTest
import SwiftData
@testable import Trees

@MainActor
final class CSVImportTests: XCTestCase {

    // ModelContext does not keep its container alive, so tests must hold the
    // container itself; using a context whose container deallocated traps in SwiftData.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentTreesSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Row parsing

    func testParseRowsHandlesQuotesDelimitersAndLineBreaksInFields() {
        let text = "a,b,c\r\n\"x, y\",\"say \"\"hi\"\"\",\"line1\nline2\"\n,,\nlast,row,\"\""
        XCTAssertEqual(CSVTreeParser.parseRows(text), [
            ["a", "b", "c"],
            ["x, y", "say \"hi\"", "line1\nline2"],
            ["", "", ""],
            ["last", "row", ""],
        ])
    }

    func testParseRowsIgnoresTrailingNewline() {
        XCTAssertEqual(CSVTreeParser.parseRows("a,b\n1,2\n"), [["a", "b"], ["1", "2"]])
        XCTAssertEqual(CSVTreeParser.parseRows(""), [])
    }

    // MARK: - Archive building

    /// The app's own CSV export must import back with the same trees.
    func testOwnExportRoundTrips() throws {
        let source = try makeContainer()
        let sourceContext = source.mainContext
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let apple = Tree(
            latitude: 51.5, longitude: -0.12, horizontalAccuracy: 4.2, altitude: 33.5,
            species: "Apple, \"Heritage\"", variety: "Bramley", rootstock: "M25",
            createdAt: created, updatedAt: created
        )
        sourceContext.insert(apple)
        _ = apple.addNote(text: "Line one\nLine two")
        let odd = Tree(latitude: -33.9, longitude: 151.2, horizontalAccuracy: 12, species: "-unknown", createdAt: created, updatedAt: created)
        sourceContext.insert(odd)
        try sourceContext.save()

        let csv = CSVExporter.export(trees: [apple, odd])
        let archive = try XCTUnwrap(TreeImportService.decode(Data(csv.utf8)))

        let dest = try makeContainer()
        let destContext = dest.mainContext
        let summary = try TreeImportService(modelContext: destContext).importArchive(archive, photoHandling: .none)
        XCTAssertEqual(summary.importedCount, 2)
        XCTAssertEqual(summary.skippedCount, 0)

        let imported = try destContext.fetch(FetchDescriptor<Tree>())
        let importedApple = try XCTUnwrap(imported.first { $0.id == apple.id })
        XCTAssertEqual(importedApple.species, "Apple, \"Heritage\"")
        XCTAssertEqual(importedApple.variety, "Bramley")
        XCTAssertEqual(importedApple.rootstock, "M25")
        XCTAssertEqual(importedApple.latitude, 51.5)
        XCTAssertEqual(importedApple.longitude, -0.12)
        XCTAssertEqual(importedApple.horizontalAccuracy, 4.2)
        XCTAssertEqual(importedApple.altitude, 33.5)
        XCTAssertEqual(importedApple.createdAt, created)
        XCTAssertEqual(importedApple.treeNotes.map(\.text), ["Line one\nLine two"])

        let importedOdd = try XCTUnwrap(imported.first { $0.id == odd.id })
        XCTAssertEqual(importedOdd.species, "-unknown", "the export's formula guard is removed again")
        XCTAssertEqual(importedOdd.latitude, -33.9)
        XCTAssertNil(importedOdd.altitude)
        XCTAssertTrue(importedOdd.treeNotes.isEmpty)
    }

    func testSpreadsheetWithAliasHeadersAndNoOptionalColumns() throws {
        let csv = "\u{FEFF}Name,Lat,Lng,Cultivar,Date\nOak,51.1,-1.2,,2024-05-06\nPear,50.5,-0.5,Conference,2024-05-07 08:30:00\n\n"
        let archive = try XCTUnwrap(CSVTreeParser.archive(from: Data(csv.utf8)))

        XCTAssertEqual(archive.trees.count, 2)
        XCTAssertEqual(archive.trees[0].species, "Oak")
        XCTAssertNil(archive.trees[0].variety)
        XCTAssertNil(archive.trees[0].id)
        XCTAssertEqual(archive.trees[0].horizontalAccuracy, Tree.unknownAccuracy)
        XCTAssertEqual(archive.trees[1].variety, "Conference")
        XCTAssertEqual(archive.trees[1].latitude, 50.5)

        let calendar = Calendar.current
        let first = try XCTUnwrap(archive.trees[0].parsedCreatedAt)
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: first), DateComponents(year: 2024, month: 5, day: 6))
        let second = try XCTUnwrap(archive.trees[1].parsedCreatedAt)
        XCTAssertEqual(calendar.dateComponents([.hour, .minute], from: second), DateComponents(hour: 8, minute: 30))
    }

    func testSemicolonDelimiterWithDecimalCommas() throws {
        let csv = "species;latitude;longitude;accuracy\nApfel;48,137;11,575;3,5\n"
        let archive = try XCTUnwrap(CSVTreeParser.archive(from: Data(csv.utf8)))

        XCTAssertEqual(archive.trees.count, 1)
        XCTAssertEqual(archive.trees[0].species, "Apfel")
        XCTAssertEqual(archive.trees[0].latitude, 48.137)
        XCTAssertEqual(archive.trees[0].longitude, 11.575)
        XCTAssertEqual(archive.trees[0].horizontalAccuracy, 3.5)
    }

    func testRowsWithUnreadableCoordinatesAreReportedAsSkipped() throws {
        let csv = """
        species,latitude,longitude
        Good,51.0,-1.0
        NoLat,,-1.0
        NoLon,51.5,
        BadLon,51.5,invalid
        Text,north,west
        Short
        """
        let archive = try XCTUnwrap(TreeImportService.decode(Data(csv.utf8)))
        XCTAssertEqual(archive.trees.count, 6)

        let container = try makeContainer()
        let context = container.mainContext
        let summary = try TreeImportService(modelContext: context).importArchive(archive, photoHandling: .none)

        XCTAssertEqual(summary.importedCount, 1)
        XCTAssertEqual(summary.skippedCount, 5)
        let imported = try context.fetch(FetchDescriptor<Tree>())
        XCTAssertEqual(imported.map(\.species), ["Good"])
        XCTAssertFalse(imported.contains { $0.longitude == 0 }, "an unreadable longitude must never become 0")
    }

    /// A position on the equator or prime meridian is legitimate when the
    /// file actually says so.
    func testExplicitZeroCoordinatesAreAccepted() throws {
        let csv = "species,latitude,longitude\nGreenwich,51.4779,0\nEquator,0.0,36.9\n"
        let archive = try XCTUnwrap(CSVTreeParser.archive(from: Data(csv.utf8)))
        let container = try makeContainer()
        let summary = try TreeImportService(modelContext: container.mainContext).importArchive(archive, photoHandling: .none)

        XCTAssertEqual(summary.importedCount, 2)
        XCTAssertEqual(summary.skippedCount, 0)
    }

    func testMissingOrZeroAccuracyIsUnknownNotPerfect() throws {
        let csv = "species,latitude,longitude,accuracy\nNone,51.0,-1.0,\nZero,51.0,-1.0,0\nNegative,51.0,-1.0,-1\nReal,51.0,-1.0,4.5\n"
        let archive = try XCTUnwrap(CSVTreeParser.archive(from: Data(csv.utf8)))
        XCTAssertEqual(archive.trees.map(\.horizontalAccuracy), [0, 0, 0, 4.5])

        let container = try makeContainer()
        let context = container.mainContext
        _ = try TreeImportService(modelContext: context).importArchive(archive, photoHandling: .none)
        let trees = try context.fetch(FetchDescriptor<Tree>())
        let unknown = try XCTUnwrap(trees.first { $0.species == "None" })
        let real = try XCTUnwrap(trees.first { $0.species == "Real" })

        XCTAssertFalse(unknown.hasKnownAccuracy)
        XCTAssertEqual(unknown.accuracyDescription, "Unknown")
        XCTAssertTrue(real.hasKnownAccuracy)
        XCTAssertEqual(real.accuracyDescription, "4.5m")

        // Unknown sorts after every known accuracy, and exports as blank
        XCTAssertEqual(TreeSortOrder.accuracy.sorted(trees).first?.species, "Real")
        let exported = CSVExporter.export(trees: [unknown])
        let reimported = try XCTUnwrap(CSVTreeParser.archive(from: Data(exported.utf8)))
        XCTAssertEqual(reimported.trees.first?.horizontalAccuracy, Tree.unknownAccuracy)
        XCTAssertFalse(exported.contains(",0.0,"))
    }

    func testFilesWithoutCoordinateColumnsAreRejected() {
        XCTAssertNil(CSVTreeParser.archive(from: Data("species,variety\nApple,Cox\n".utf8)))
        XCTAssertNil(CSVTreeParser.archive(from: Data("just some text".utf8)))
        XCTAssertNil(CSVTreeParser.archive(from: Data()))
        XCTAssertNil(TreeImportService.decode(Data("{\"not\": \"trees\"}".utf8)))
    }

    /// A header-only file is a valid, empty import rather than an error.
    func testHeaderOnlyFileHasNoTrees() throws {
        let archive = try XCTUnwrap(CSVTreeParser.archive(from: Data("latitude,longitude\n".utf8)))
        XCTAssertTrue(archive.trees.isEmpty)
    }
}
