import XCTest
import SwiftData
@testable import Trees

/// The label field (schema version 2) and the wider species list.
@MainActor
final class LabelTests: XCTestCase {

    // ModelContext does not keep its container alive, so tests must hold the
    // container itself; using a context whose container deallocated traps in SwiftData.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentTreesSchema.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private let created = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeTree(
        in context: ModelContext, species: String = "Blackcurrant", variety: String? = nil,
        label: String?, offset: TimeInterval = 0
    ) -> Tree {
        let when = created.addingTimeInterval(offset)
        let tree = Tree(
            latitude: 51.5, longitude: -0.12, horizontalAccuracy: 4, species: species,
            variety: variety, label: label, createdAt: when, updatedAt: when
        )
        context.insert(tree)
        return tree
    }

    func testCurrentSchemaIsTheLastInTheMigrationPlan() {
        XCTAssertTrue(TreesMigrationPlan.schemas.last == CurrentTreesSchema.self)
        XCTAssertEqual(TreesMigrationPlan.stages.count, TreesMigrationPlan.schemas.count - 1)
    }

    func testLabelIsSearchable() throws {
        let container = try makeContainer()
        let tree = makeTree(in: container.mainContext, label: "Row 3, bush 4")

        XCTAssertTrue(tree.matches(searchText: "row 3"))
        XCTAssertTrue(tree.matches(searchText: "bush"))
        XCTAssertFalse(tree.matches(searchText: "row 9"))
    }

    func testRowDetailCombinesVarietyAndLabel() throws {
        let container = try makeContainer()
        let context = container.mainContext
        XCTAssertEqual(makeTree(in: context, variety: "Ben Sarek", label: "Row 3").varietyAndLabel, "Ben Sarek · Row 3")
        XCTAssertEqual(makeTree(in: context, variety: "Ben Sarek", label: nil).varietyAndLabel, "Ben Sarek")
        XCTAssertEqual(makeTree(in: context, variety: nil, label: "Row 3").varietyAndLabel, "Row 3")
        XCTAssertNil(makeTree(in: context, variety: nil, label: nil).varietyAndLabel)
        XCTAssertNil(makeTree(in: context, variety: "", label: "").varietyAndLabel)
    }

    /// Bushes planted close together would otherwise be flagged as duplicates
    /// of each other; giving them different labels says they are distinct.
    func testDifferentLabelsAreNotDuplicates() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = makeTree(in: context, label: "Bush 1")
        _ = makeTree(in: context, label: "Bush 2", offset: 30)
        XCTAssertTrue(DuplicateTreesView.duplicateGroups(in: try context.fetch(FetchDescriptor<Tree>())).isEmpty)

        // Unlabelled, or labelled the same, they are still candidates
        _ = makeTree(in: context, label: nil, offset: 60)
        _ = makeTree(in: context, label: "bush 1 ", offset: 90)
        let groups = DuplicateTreesView.duplicateGroups(in: try context.fetch(FetchDescriptor<Tree>()))
        XCTAssertEqual(groups.count, 1)
    }

    func testLabelRoundTripsThroughJSON() throws {
        let source = try makeContainer()
        let tree = makeTree(in: source.mainContext, label: "Row 3, bush 4")
        let plain = makeTree(in: source.mainContext, species: "Apple", label: nil)
        try source.mainContext.save()

        let json = JSONExporter.export(trees: [tree, plain])
        let archive = try XCTUnwrap(TreeImportService.decode(Data(json.utf8)))
        let dest = try makeContainer()
        _ = try TreeImportService(modelContext: dest.mainContext).importArchive(archive, photoHandling: .none)

        let imported = try dest.mainContext.fetch(FetchDescriptor<Tree>())
        XCTAssertEqual(imported.first { $0.id == tree.id }?.label, "Row 3, bush 4")
        XCTAssertNil(imported.first { $0.id == plain.id }?.label)
    }

    /// Exports made before the label existed have no such key and must still import.
    func testJSONWithoutALabelKeyStillImports() throws {
        let json = """
        {"version": 2, "collections": [], "trees": [
          {"latitude": 51.0, "longitude": -1.0, "horizontalAccuracy": 5.0, "species": "Plum", "notes": ""}
        ]}
        """
        let archive = try XCTUnwrap(TreeImportService.decode(Data(json.utf8)))
        let container = try makeContainer()
        _ = try TreeImportService(modelContext: container.mainContext).importArchive(archive, photoHandling: .none)

        let imported = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<Tree>()).first)
        XCTAssertNil(imported.label)
    }

    func testLabelRoundTripsThroughCSVAsTheLastColumn() throws {
        let source = try makeContainer()
        let tree = makeTree(in: source.mainContext, label: "Row 3, bush 4")
        try source.mainContext.save()

        let csv = CSVExporter.export(trees: [tree])
        let header = try XCTUnwrap(csv.split(separator: "\n").first)
        XCTAssertTrue(header.hasSuffix(",updated_at,label"), "label is appended so earlier columns keep their positions")
        XCTAssertTrue(csv.contains("\"Row 3, bush 4\""))

        let archive = try XCTUnwrap(CSVTreeParser.archive(from: Data(csv.utf8)))
        XCTAssertEqual(archive.trees.first?.label, "Row 3, bush 4")

        let tagged = try XCTUnwrap(CSVTreeParser.archive(from: Data("lat,lon,species,tag\n51,-1,Oak,North gate\n".utf8)))
        XCTAssertEqual(tagged.trees.first?.label, "North gate")
    }

    func testLabelAppearsInGPXDescription() throws {
        let container = try makeContainer()
        let tree = makeTree(in: container.mainContext, label: "Row 3 <east>")

        XCTAssertTrue(GPXExporter.export(trees: [tree]).contains("Label: Row 3 &lt;east&gt;"))
    }

    // MARK: - Species suggestions

    func testSpeciesListIncludesShrubsAndHasNoDuplicates() {
        for shrub in ["Blackcurrant", "Redcurrant", "Honeyberry", "Gooseberry", "Raspberry"] {
            XCTAssertTrue(commonSpecies.contains(shrub), shrub)
        }
        XCTAssertTrue(commonSpecies.contains("Apple"))

        let lowercased = commonSpecies.map { $0.lowercased() }
        XCTAssertEqual(Set(lowercased).count, lowercased.count, "duplicate entries in commonSpecies")
        XCTAssertEqual(formattedSpeciesName("honeyberry"), "Honeyberry")
    }
}
