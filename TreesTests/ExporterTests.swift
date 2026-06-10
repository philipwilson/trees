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
}
