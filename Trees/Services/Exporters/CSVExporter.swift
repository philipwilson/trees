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
            let notesEscaped = escapeCSV(tree.notes)

            let row = [
                tree.id.uuidString,
                String(tree.latitude),
                String(tree.longitude),
                String(tree.horizontalAccuracy),
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

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    static func exportToFile(trees: [Tree], filePrefix: String = "trees") -> URL? {
        let content = export(trees: trees)
        let filename = "\(filePrefix)_\(formattedDate()).csv"

        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(filename) else {
            return nil
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: Date())
    }
}
