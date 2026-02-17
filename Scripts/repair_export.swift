#!/usr/bin/env swift
import Foundation

enum ToolError: Error, CustomStringConvertible {
    case usage(String)
    case invalidJSONRoot
    case missingTreesArray
    case mappingParse(String)
    case duplicateTreeIDs([String])

    var description: String {
        switch self {
        case .usage(let message):
            return message
        case .invalidJSONRoot:
            return "Input JSON must be an object with top-level keys."
        case .missingTreesArray:
            return "Input JSON must contain a top-level \"trees\" array."
        case .mappingParse(let message):
            return "Mapping parse error: \(message)"
        case .duplicateTreeIDs(let ids):
            let preview = ids.prefix(10).joined(separator: ", ")
            return "Input contains duplicate tree IDs; mapping is ambiguous. Examples: \(preview)"
        }
    }
}

struct Options {
    let inputPath: String
    let outputPath: String
    let mappingPath: String?
    let templateOutputPath: String?
    let dryRun: Bool
}

enum MappingAssignment: Equatable {
    case set(String)
    case clear
}

struct MappingParseResult {
    let assignments: [UUID: MappingAssignment]
    let readRows: Int
    let appliedRows: Int
    let skippedRows: Int
    let overriddenRows: Int
}

struct RepairStats {
    var speciesTrimmed = 0
    var varietyTrimmed = 0
    var rootstockTrimmed = 0
    var varietyCleared = 0
    var rootstockCleared = 0
    var collectionNamesTrimmed = 0
    var collectionIDsRegenerated = 0
    var collectionUpdatedTouched = 0

    var mappingRowsRead = 0
    var mappingRowsApplied = 0
    var mappingRowsSkipped = 0
    var mappingRowsOverridden = 0
    var mappingUnknownTreeIDs = 0
    var mappingSetAssignments = 0
    var mappingClearAssignments = 0
    var mappingCreatedCollections = 0
    var mappingAssignedTrees = 0
    var mappingReassignedTrees = 0
    var mappingUnchangedTrees = 0
}

func printUsage() {
    let usage = """
    Usage:
      swift Scripts/repair_export.swift --input <export.json> [--mapping <tree-to-collection.csv>] [--output <repaired.json>] [--template-output <mapping-template.csv>] [--dry-run]

    What it does:
      1) Trims leading/trailing whitespace on tree fields:
         - species
         - variety (removes key if empty after trim)
         - rootstock (removes key if empty after trim)
      2) Trims collection names.
      3) Optionally applies collection assignments from a mapping file:
         tree_id,collection_name

    Mapping format:
      - CSV or TSV
      - Header row optional
      - Lines starting with # are ignored
      - Empty collection_name clears that tree's collectionId

    Examples:
      swift Scripts/repair_export.swift --input db-export-photos.json --dry-run
      swift Scripts/repair_export.swift --input db-export-photos.json --mapping tree-collection-map.csv --output db-export-photos-repaired.json
      swift Scripts/repair_export.swift --input db-export-photos.json --template-output tree-collection-map.csv --dry-run
    """
    print(usage)
}

func parseOptions(args: [String]) throws -> Options {
    var inputPath: String?
    var outputPath: String?
    var mappingPath: String?
    var templateOutputPath: String?
    var dryRun = false

    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--input":
            index += 1
            guard index < args.count else { throw ToolError.usage("Missing value for --input") }
            inputPath = args[index]
        case "--output":
            index += 1
            guard index < args.count else { throw ToolError.usage("Missing value for --output") }
            outputPath = args[index]
        case "--mapping":
            index += 1
            guard index < args.count else { throw ToolError.usage("Missing value for --mapping") }
            mappingPath = args[index]
        case "--template-output":
            index += 1
            guard index < args.count else { throw ToolError.usage("Missing value for --template-output") }
            templateOutputPath = args[index]
        case "--dry-run":
            dryRun = true
        case "--help", "-h":
            throw ToolError.usage("")
        default:
            throw ToolError.usage("Unknown argument: \(arg)")
        }
        index += 1
    }

    guard let inputPath else {
        throw ToolError.usage("Missing required --input <path>")
    }

    let resolvedOutput: String
    if let outputPath {
        resolvedOutput = outputPath
    } else {
        let inputURL = URL(fileURLWithPath: inputPath)
        let base = inputURL.deletingPathExtension().path
        resolvedOutput = "\(base)-repaired.json"
    }

    return Options(
        inputPath: inputPath,
        outputPath: resolvedOutput,
        mappingPath: mappingPath,
        templateOutputPath: templateOutputPath,
        dryRun: dryRun
    )
}

func trimmed(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

func normalizedCollectionKey(_ value: String) -> String {
    trimmed(value).lowercased()
}

func isoTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

func parseDelimitedLine(_ line: String, delimiter: Character) -> [String] {
    let chars = Array(line)
    var fields: [String] = []
    var current = ""
    var inQuotes = false
    var i = 0

    while i < chars.count {
        let char = chars[i]
        if char == "\"" {
            if inQuotes && i + 1 < chars.count && chars[i + 1] == "\"" {
                current.append("\"")
                i += 1
            } else {
                inQuotes.toggle()
            }
        } else if char == delimiter && !inQuotes {
            fields.append(trimmed(current))
            current = ""
        } else {
            current.append(char)
        }
        i += 1
    }

    fields.append(trimmed(current))
    return fields
}

func detectDelimiter(lines: [String]) -> Character {
    for line in lines {
        let t = trimmed(line)
        if t.isEmpty || t.hasPrefix("#") { continue }
        if t.contains("\t") { return "\t" }
        return ","
    }
    return ","
}

func parseMappingFile(path: String) throws -> MappingParseResult {
    let text = try String(contentsOfFile: path, encoding: .utf8)
    let lines = text.components(separatedBy: .newlines)
    let delimiter = detectDelimiter(lines: lines)

    var parsedRows: [[String]] = []
    for raw in lines {
        let line = trimmed(raw)
        if line.isEmpty || line.hasPrefix("#") { continue }
        let columns = parseDelimitedLine(line, delimiter: delimiter)
        parsedRows.append(columns)
    }

    if parsedRows.isEmpty {
        return MappingParseResult(assignments: [:], readRows: 0, appliedRows: 0, skippedRows: 0, overriddenRows: 0)
    }

    let first = parsedRows[0]
    let firstCol = first.indices.contains(0) ? first[0].lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "") : ""
    let secondCol = first.indices.contains(1) ? first[1].lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "") : ""
    let hasHeader = (firstCol == "treeid" || firstCol == "id") && secondCol.contains("collection")

    var assignments: [UUID: MappingAssignment] = [:]
    var readRows = 0
    var appliedRows = 0
    var skippedRows = 0
    var overriddenRows = 0

    for (rowIndex, row) in parsedRows.enumerated() {
        if hasHeader && rowIndex == 0 { continue }
        readRows += 1
        guard row.count >= 2 else {
            skippedRows += 1
            continue
        }

        let treeIDString = trimmed(row[0])
        guard let treeID = UUID(uuidString: treeIDString) else {
            skippedRows += 1
            continue
        }

        let collectionName = trimmed(row[1])
        let assignment: MappingAssignment = collectionName.isEmpty ? .clear : .set(collectionName)
        if let existing = assignments[treeID], existing != assignment {
            overriddenRows += 1
        }
        assignments[treeID] = assignment
        appliedRows += 1
    }

    return MappingParseResult(
        assignments: assignments,
        readRows: readRows,
        appliedRows: appliedRows,
        skippedRows: skippedRows,
        overriddenRows: overriddenRows
    )
}

func loadExport(path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ToolError.invalidJSONRoot
    }
    return root
}

func validateUniqueTreeIDs(trees: [[String: Any]]) throws -> [UUID: Int] {
    var indexByID: [UUID: Int] = [:]
    var duplicates: [String] = []

    for (index, tree) in trees.enumerated() {
        guard let idString = tree["id"] as? String, let id = UUID(uuidString: idString) else { continue }
        if indexByID[id] != nil {
            duplicates.append(id.uuidString)
        } else {
            indexByID[id] = index
        }
    }

    if !duplicates.isEmpty {
        throw ToolError.duplicateTreeIDs(Array(Set(duplicates)))
    }

    return indexByID
}

func repairExport(root: inout [String: Any], mapping: MappingParseResult?) throws -> RepairStats {
    guard var trees = root["trees"] as? [[String: Any]] else {
        throw ToolError.missingTreesArray
    }
    var collections = (root["collections"] as? [[String: Any]]) ?? []

    var stats = RepairStats()

    for treeIndex in trees.indices {
        var tree = trees[treeIndex]

        if let species = tree["species"] as? String {
            let cleaned = trimmed(species)
            if cleaned != species {
                stats.speciesTrimmed += 1
            }
            tree["species"] = cleaned
        }

        if let variety = tree["variety"] as? String {
            let cleaned = trimmed(variety)
            if cleaned != variety {
                stats.varietyTrimmed += 1
            }
            if cleaned.isEmpty {
                tree.removeValue(forKey: "variety")
                stats.varietyCleared += 1
            } else {
                tree["variety"] = cleaned
            }
        }

        if let rootstock = tree["rootstock"] as? String {
            let cleaned = trimmed(rootstock)
            if cleaned != rootstock {
                stats.rootstockTrimmed += 1
            }
            if cleaned.isEmpty {
                tree.removeValue(forKey: "rootstock")
                stats.rootstockCleared += 1
            } else {
                tree["rootstock"] = cleaned
            }
        }

        trees[treeIndex] = tree
    }

    let now = isoTimestamp(Date())

    var collectionIDByKey: [String: String] = [:]
    var collectionIndexByID: [String: Int] = [:]
    var seenCollectionIDs = Set<String>()

    for index in collections.indices {
        var collection = collections[index]

        if let name = collection["name"] as? String {
            let cleaned = trimmed(name)
            if cleaned != name {
                stats.collectionNamesTrimmed += 1
            }
            collection["name"] = cleaned
        }

        let existingID = (collection["id"] as? String).flatMap { UUID(uuidString: $0)?.uuidString }
        let resolvedID: String
        if let existingID, !seenCollectionIDs.contains(existingID) {
            resolvedID = existingID
        } else {
            resolvedID = UUID().uuidString
            stats.collectionIDsRegenerated += 1
        }
        seenCollectionIDs.insert(resolvedID)
        collection["id"] = resolvedID

        if collection["createdAt"] == nil {
            collection["createdAt"] = now
        }
        if collection["updatedAt"] == nil {
            collection["updatedAt"] = now
        }

        collections[index] = collection
        collectionIndexByID[resolvedID] = index
        if let name = collection["name"] as? String {
            let key = normalizedCollectionKey(name)
            if !key.isEmpty, collectionIDByKey[key] == nil {
                collectionIDByKey[key] = resolvedID
            }
        }
    }

    if let mapping {
        stats.mappingRowsRead = mapping.readRows
        stats.mappingRowsApplied = mapping.appliedRows
        stats.mappingRowsSkipped = mapping.skippedRows
        stats.mappingRowsOverridden = mapping.overriddenRows

        let treeIndexByID = try validateUniqueTreeIDs(trees: trees)
        var touchedCollectionIDs = Set<String>()

        for (treeID, assignment) in mapping.assignments {
            guard let treeIndex = treeIndexByID[treeID] else {
                stats.mappingUnknownTreeIDs += 1
                continue
            }

            var tree = trees[treeIndex]

            switch assignment {
            case .clear:
                stats.mappingClearAssignments += 1
                if tree["collectionId"] != nil {
                    tree.removeValue(forKey: "collectionId")
                    stats.mappingReassignedTrees += 1
                } else {
                    stats.mappingUnchangedTrees += 1
                }

            case .set(let collectionName):
                stats.mappingSetAssignments += 1
                let key = normalizedCollectionKey(collectionName)
                if key.isEmpty {
                    stats.mappingRowsSkipped += 1
                    continue
                }

                let collectionID: String
                if let existingID = collectionIDByKey[key] {
                    collectionID = existingID
                } else {
                    let newID = UUID().uuidString
                    let cleanedName = trimmed(collectionName)
                    let newCollection: [String: Any] = [
                        "id": newID,
                        "name": cleanedName,
                        "createdAt": now,
                        "updatedAt": now
                    ]
                    let newIndex = collections.count
                    collections.append(newCollection)
                    collectionIDByKey[key] = newID
                    collectionIndexByID[newID] = newIndex
                    collectionID = newID
                    stats.mappingCreatedCollections += 1
                }

                touchedCollectionIDs.insert(collectionID)

                if let existingCollectionID = tree["collectionId"] as? String {
                    if existingCollectionID == collectionID {
                        stats.mappingUnchangedTrees += 1
                    } else {
                        stats.mappingReassignedTrees += 1
                    }
                } else {
                    stats.mappingAssignedTrees += 1
                }

                tree["collectionId"] = collectionID
            }

            trees[treeIndex] = tree
        }

        for collectionID in touchedCollectionIDs {
            guard let index = collectionIndexByID[collectionID] else { continue }
            var collection = collections[index]
            collection["updatedAt"] = now
            collections[index] = collection
            stats.collectionUpdatedTouched += 1
        }
    }

    root["trees"] = trees
    root["collections"] = collections
    return stats
}

func writeExport(root: [String: Any], to outputPath: String) throws {
    var data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    if data.last != 0x0A {
        data.append(0x0A)
    }
    try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
}

func escapeCSV(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return value
}

func writeMappingTemplate(root: [String: Any], to outputPath: String) throws {
    let trees = (root["trees"] as? [[String: Any]]) ?? []
    let collections = (root["collections"] as? [[String: Any]]) ?? []

    var collectionNameByID: [String: String] = [:]
    for collection in collections {
        guard let id = collection["id"] as? String else { continue }
        let name = (collection["name"] as? String).map(trimmed) ?? ""
        collectionNameByID[id] = name
    }

    var lines: [String] = []
    lines.append("tree_id,collection_name,species,variety,rootstock,place_name")

    for tree in trees {
        guard let treeID = tree["id"] as? String else { continue }
        let collectionID = tree["collectionId"] as? String
        let collectionName = collectionID.flatMap { collectionNameByID[$0] } ?? ""
        let species = (tree["species"] as? String).map(trimmed) ?? ""
        let variety = (tree["variety"] as? String).map(trimmed) ?? ""
        let rootstock = (tree["rootstock"] as? String).map(trimmed) ?? ""
        let placeName = (tree["placeName"] as? String).map(trimmed) ?? ""
        let row = [
            escapeCSV(treeID),
            escapeCSV(collectionName),
            escapeCSV(species),
            escapeCSV(variety),
            escapeCSV(rootstock),
            escapeCSV(placeName)
        ].joined(separator: ",")
        lines.append(row)
    }

    let content = lines.joined(separator: "\n") + "\n"
    try content.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
}

func printSummary(
    inputPath: String,
    outputPath: String,
    templateOutputPath: String?,
    dryRun: Bool,
    root: [String: Any],
    stats: RepairStats
) {
    let treesCount = (root["trees"] as? [[String: Any]])?.count ?? 0
    let collectionsCount = (root["collections"] as? [[String: Any]])?.count ?? 0

    print("Input: \(inputPath)")
    if dryRun {
        print("Output: (dry-run, no file written)")
    } else {
        print("Output: \(outputPath)")
    }
    if let templateOutputPath {
        print("Mapping template: \(templateOutputPath)")
    }
    print("Trees: \(treesCount)")
    print("Collections: \(collectionsCount)")

    print("")
    print("Normalization changes:")
    print("  species trimmed: \(stats.speciesTrimmed)")
    print("  variety trimmed: \(stats.varietyTrimmed)")
    print("  rootstock trimmed: \(stats.rootstockTrimmed)")
    print("  variety keys removed (empty after trim): \(stats.varietyCleared)")
    print("  rootstock keys removed (empty after trim): \(stats.rootstockCleared)")
    print("  collection names trimmed: \(stats.collectionNamesTrimmed)")
    print("  collection IDs regenerated (invalid/duplicate): \(stats.collectionIDsRegenerated)")

    if stats.mappingRowsRead > 0 {
        print("")
        print("Mapping changes:")
        print("  rows read: \(stats.mappingRowsRead)")
        print("  rows applied: \(stats.mappingRowsApplied)")
        print("  rows skipped: \(stats.mappingRowsSkipped)")
        print("  rows overridden by later duplicate tree_id: \(stats.mappingRowsOverridden)")
        print("  unknown tree IDs in mapping: \(stats.mappingUnknownTreeIDs)")
        print("  set assignments: \(stats.mappingSetAssignments)")
        print("  clear assignments: \(stats.mappingClearAssignments)")
        print("  trees newly assigned to collection: \(stats.mappingAssignedTrees)")
        print("  trees reassigned/cleared: \(stats.mappingReassignedTrees)")
        print("  trees unchanged: \(stats.mappingUnchangedTrees)")
        print("  collections created from mapping: \(stats.mappingCreatedCollections)")
        print("  collections touched (updatedAt set): \(stats.collectionUpdatedTouched)")
    }
}

do {
    let options = try parseOptions(args: Array(CommandLine.arguments.dropFirst()))
    var root = try loadExport(path: options.inputPath)
    let mapping: MappingParseResult?
    if let mappingPath = options.mappingPath {
        mapping = try parseMappingFile(path: mappingPath)
    } else {
        mapping = nil
    }

    let stats = try repairExport(root: &root, mapping: mapping)
    if !options.dryRun {
        try writeExport(root: root, to: options.outputPath)
    }
    if let templateOutputPath = options.templateOutputPath {
        try writeMappingTemplate(root: root, to: templateOutputPath)
    }
    printSummary(
        inputPath: options.inputPath,
        outputPath: options.outputPath,
        templateOutputPath: options.templateOutputPath,
        dryRun: options.dryRun,
        root: root,
        stats: stats
    )
} catch let error as ToolError {
    if case .usage(let message) = error {
        if !message.isEmpty {
            fputs("Error: \(message)\n\n", stderr)
        }
        printUsage()
    } else {
        fputs("Error: \(error.description)\n", stderr)
    }
    exit(2)
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
