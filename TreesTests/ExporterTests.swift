import XCTest
import SwiftData
@testable import Trees

@MainActor
final class ExporterTests: XCTestCase {

    // ModelContext does not keep its container alive, so tests must hold the
    // container itself; using a context whose container deallocated traps in SwiftData.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: TreesSchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeTree(in context: ModelContext, species: String, variety: String? = nil, noteText: String? = nil) -> Tree {
        let tree = Tree(latitude: 51.5, longitude: -0.12, horizontalAccuracy: 4.0, species: species, variety: variety)
        context.insert(tree)
        if let noteText {
            _ = tree.addNote(text: noteText)
        }
        return tree
    }

    // MARK: - CSV

    func testCSVEscapesCommasQuotesAndNewlines() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tree = makeTree(
            in: context,
            species: #"Apple, "Heritage""#,
            variety: "Line1\nLine2",
            noteText: "plain note"
        )

        let csv = CSVExporter.export(trees: [tree])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)

        // Header plus one data row (the embedded newline must stay inside quotes,
        // so the variety field contributes an extra physical line, not a new record)
        XCTAssertTrue(csv.hasPrefix("id,latitude,longitude"))
        XCTAssertTrue(csv.contains(#""Apple, ""Heritage""""#))
        XCTAssertTrue(csv.contains("\"Line1\nLine2\""))
        XCTAssertEqual(lines.filter { $0.hasPrefix(tree.id.uuidString) }.count, 1)
    }

    func testCSVPlainFieldsNotQuoted() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tree = makeTree(in: context, species: "Oak")

        let csv = CSVExporter.export(trees: [tree])
        XCTAssertTrue(csv.contains(",Oak,"))
        XCTAssertFalse(csv.contains("\"Oak\""))
    }

    func testCSVQuotesCarriageReturns() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tree = makeTree(in: context, species: "Oak", noteText: "first\rsecond")

        let csv = CSVExporter.export(trees: [tree])
        XCTAssertTrue(csv.contains("\"first\rsecond\""))
    }

    /// Text a spreadsheet would run as a formula is prefixed so it stays text;
    /// numeric columns and ordinary text are left alone.
    func testCSVNeutralizesFormulaLikeText() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tree = Tree(latitude: -33.9, longitude: -70.6, horizontalAccuracy: 4.0, species: "=HYPERLINK(\"http://x\")", variety: "+1", rootstock: "@home")
        context.insert(tree)
        _ = tree.addNote(text: "-fine, really")
        let plain = makeTree(in: context, species: "Oak", variety: "Semi-dwarf", noteText: "a = b")

        let csv = CSVExporter.export(trees: [tree, plain])

        XCTAssertTrue(csv.contains(#""'=HYPERLINK(""http://x"")""#))
        XCTAssertTrue(csv.contains(",'+1,"))
        XCTAssertTrue(csv.contains(",'@home,"))
        XCTAssertTrue(csv.contains(#""'-fine, really""#))
        XCTAssertTrue(csv.contains(",-33.9,-70.6,"), "negative coordinates must stay numeric")
        XCTAssertTrue(csv.contains(",Oak,Semi-dwarf,,a = b,"))
    }

    // MARK: - JSON failures

    /// JSON cannot represent NaN. The export must report failure rather than
    /// return a file that is malformed or silently missing the tree.
    func testJSONFileExportFailsWhenATreeCannotBeEncoded() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let good = makeTree(in: context, species: "Oak")
        let bad = Tree(latitude: .nan, longitude: 0, horizontalAccuracy: 4.0, species: "Broken")
        context.insert(bad)
        let alsoGood = makeTree(in: context, species: "Ash")

        XCTAssertNil(JSONExporter.exportToFile(trees: [good, bad, alsoGood], includePhotos: true, filePrefix: "failure-test"))
        XCTAssertNil(JSONExporter.exportToFile(trees: [good, bad, alsoGood], includePhotos: false, filePrefix: "failure-test"))

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("failure-test") }
        XCTAssertEqual(leftovers, [])
    }

    // MARK: - Species names

    func testSpeciesNameFormatting() {
        XCTAssertEqual(formattedSpeciesName("apple"), "Apple")
        XCTAssertEqual(formattedSpeciesName("  red maple "), "Red Maple")
        XCTAssertEqual(formattedSpeciesName("Red Maple"), "Red Maple")
        XCTAssertEqual(formattedSpeciesName("McIntosh apple"), "McIntosh apple")
        XCTAssertEqual(formattedSpeciesName("WALNUT"), "Walnut", "a listed species takes the list's spelling")
        XCTAssertEqual(formattedSpeciesName(""), "")
    }

    // MARK: - Delete confirmation wording

    func testDeletionTitles() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let oak = makeTree(in: context, species: "Oak")
        let unnamed = makeTree(in: context, species: "")
        let orchard = Collection(name: "Orchard")
        context.insert(orchard)

        XCTAssertEqual(Tree.deletionTitle(for: [oak]), "Delete Oak?")
        XCTAssertEqual(Tree.deletionTitle(for: [unnamed]), "Delete this tree?")
        XCTAssertEqual(Tree.deletionTitle(for: [oak, unnamed]), "Delete 2 trees?")
        XCTAssertEqual(Collection.deletionTitle(for: [orchard]), "Delete \u{201C}Orchard\u{201D}?")
    }

    func testPendingDeletionOnlyPresentsForRealRequests() {
        var pending = PendingDeletion<Int>()
        pending.request([])
        XCTAssertFalse(pending.isPresented)
        pending.request([1, 2])
        XCTAssertTrue(pending.isPresented)
        XCTAssertEqual(pending.items, [1, 2])
    }

    // MARK: - GPX

    func testGPXEscapesXMLEntities() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tree = makeTree(
            in: context,
            species: #"Oak <"Quercus"> & Co's"#,
            noteText: "height > 3m & growing"
        )

        let gpx = GPXExporter.export(trees: [tree])

        XCTAssertTrue(gpx.contains("<name>Oak &lt;&quot;Quercus&quot;&gt; &amp; Co&apos;s</name>"))
        XCTAssertTrue(gpx.contains("height &gt; 3m &amp; growing"))
        XCTAssertFalse(gpx.contains(#"<name>Oak <"#))
    }

    func testGPXEmptySpeciesFallsBackToUnknown() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tree = makeTree(in: context, species: "")

        let gpx = GPXExporter.export(trees: [tree])
        XCTAssertTrue(gpx.contains("<name>Unknown Tree</name>"))
    }

    // MARK: - File prefix

    func testFilePrefixReplacesPathSeparatorsAndPunctuation() {
        XCTAssertEqual(ExportView.sanitizedFilePrefix("North/South: Field 2"), "north_south__field_2")
        XCTAssertEqual(ExportView.sanitizedFilePrefix("Victoria's Orchard"), "victoria_s_orchard")
        XCTAssertEqual(ExportView.sanitizedFilePrefix("pre-2020_plot"), "pre-2020_plot")
    }

    func testFilePrefixFallsBackWhenNothingUsableRemains() {
        XCTAssertEqual(ExportView.sanitizedFilePrefix(""), "trees")
        XCTAssertEqual(ExportView.sanitizedFilePrefix("///"), "trees")
        XCTAssertEqual(ExportView.sanitizedFilePrefix("🌳🌳"), "trees")
    }
}
