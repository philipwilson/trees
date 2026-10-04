import Foundation

struct CSVExporter {
    static func export(trees: [Tree]) -> String {
        var csv = "id,latitude,longitude,accuracy_meters,altitude,species,variety,rootstock,notes,created_at,updated_at\n"

        let dateFormatter = ISO8601DateFormatter()

        for tree in trees {
            let altitudeStr = tree.altitude.map { String($0) } ?? ""
            let speciesEscaped = escapeCSV(tree.species)
            let varietyEscaped = escapeCSV(tree.variety ?? "")
            let rootstockEscaped = escapeCSV(tree.rootstock ?? "")
            // Combine all notes into a single string for CSV export
            let allNotesText = tree.treeNotes.map { $0.text }.joined(separator: " | ")
            let notesEscaped = escapeCSV(allNotesText)

            let row = [
                tree.id.uuidString,
                String(tree.latitude),
                String(tree.longitude),
                // Blank rather than 0 when unknown, so it re-imports as unknown
                tree.hasKnownAccuracy ? String(tree.horizontalAccuracy) : "",
                altitudeStr,
                speciesEscaped,
                varietyEscaped,
                rootstockEscaped,
                notesEscaped,
                dateFormatter.string(from: tree.createdAt),
                dateFormatter.string(from: tree.updatedAt)
            ].joined(separator: ",")

            csv += row + "\n"
        }

        return csv
    }

    private static func escapeCSV(_ text: String) -> String {
        var value = text
        // Spreadsheets run a cell starting with one of these as a formula; a
        // leading apostrophe makes them treat it as text. Only free-text
        // fields come through here, so negative numbers are unaffected.
        if let first = value.first, "=+-@\t\r".contains(first) {
            value = "'" + value
        }
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    static func exportToFile(trees: [Tree], filePrefix: String = "trees") -> URL? {
        let content = export(trees: trees)
        let filename = "\(filePrefix)_\(formattedDate()).csv"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func formattedDate() -> String {
        let formatter = DateFormatter()
        // Fixed locale: with the device set to 12-hour time, the user's locale
        // rewrites HH and the name comes out as e.g. "44444_008 PM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss_SSS"
        return formatter.string(from: Date())
    }
}
