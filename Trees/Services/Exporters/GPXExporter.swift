import Foundation

struct GPXExporter {
    static func export(trees: [Tree]) -> String {
        let dateFormatter = ISO8601DateFormatter()

        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="TreeTracker"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
          <metadata>
            <name>Tree Locations</name>
            <time>\(dateFormatter.string(from: Date()))</time>
          </metadata>

        """

        for tree in trees {
            let name = escapeXML(tree.species.isEmpty ? "Unknown Tree" : tree.species)
            let time = dateFormatter.string(from: tree.createdAt)

            var descParts: [String] = []
            if let variety = tree.variety {
                descParts.append("Variety: \(variety)")
            }
            if let rootstock = tree.rootstock {
                descParts.append("Rootstock: \(rootstock)")
            }
            // Combine all notes into description
            let allNotesText = tree.treeNotes.map { $0.text }.joined(separator: "\n")
            if !allNotesText.isEmpty {
                descParts.append(allNotesText)
            }
            let desc = escapeXML(descParts.joined(separator: "\n"))

            gpx += "  <wpt lat=\"\(tree.latitude)\" lon=\"\(tree.longitude)\">\n"

            if let altitude = tree.altitude {
                gpx += "    <ele>\(altitude)</ele>\n"
            }

            gpx += "    <time>\(time)</time>\n"
            gpx += "    <name>\(name)</name>\n"

            if !desc.isEmpty {
                gpx += "    <desc>\(desc)</desc>\n"
            }

            gpx += "    <sym>Tree</sym>\n"
            gpx += "  </wpt>\n"
        }

        gpx += "</gpx>\n"

        return gpx
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func exportToFile(trees: [Tree], filePrefix: String = "trees") -> URL? {
        let content = export(trees: trees)
        let filename = "\(filePrefix)_\(formattedDate()).gpx"

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
