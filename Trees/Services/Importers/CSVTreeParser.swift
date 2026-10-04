import Foundation

/// Reads trees from a CSV file: either this app's own CSV export or a
/// spreadsheet with at least latitude and longitude columns.
///
/// Column names are matched case-insensitively against a few common
/// spellings. Comma, semicolon and tab delimiters are detected from the
/// header row; with a non-comma delimiter, decimal commas are accepted.
enum CSVTreeParser {
    private enum Column: CaseIterable {
        case id, latitude, longitude, accuracy, altitude
        case species, variety, rootstock, notes, createdAt, updatedAt

        var names: [String] {
            switch self {
            case .id: return ["id", "uuid"]
            case .latitude: return ["latitude", "lat", "y"]
            case .longitude: return ["longitude", "lon", "lng", "long", "x"]
            case .accuracy: return ["accuracy_meters", "accuracy", "horizontal_accuracy", "horizontalaccuracy"]
            case .altitude: return ["altitude", "elevation", "ele"]
            case .species: return ["species", "name", "tree"]
            case .variety: return ["variety", "cultivar"]
            case .rootstock: return ["rootstock"]
            case .notes: return ["notes", "note", "description", "desc", "comments"]
            case .createdAt: return ["created_at", "createdat", "created", "date"]
            case .updatedAt: return ["updated_at", "updatedat", "updated"]
            }
        }
    }

    /// Returns nil if the data isn't text, or has no latitude and longitude
    /// columns. Rows whose coordinates can't be read are kept with an
    /// out-of-range latitude, so the import counts them as skipped instead
    /// of dropping them silently.
    static func archive(from data: Data) -> ImportedArchive? {
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }

        let delimiter = detectDelimiter(in: text)
        var rows = parseRows(text, delimiter: delimiter)
        guard !rows.isEmpty else { return nil }

        let header = rows.removeFirst().map {
            $0.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "_")
        }
        var indexes: [Column: Int] = [:]
        for column in Column.allCases {
            indexes[column] = header.firstIndex { column.names.contains($0) }
        }
        guard indexes[.latitude] != nil, indexes[.longitude] != nil else { return nil }

        let decimalComma = delimiter != ","
        let trees: [ImportedTreeRecord] = rows.compactMap { row in
            // Skip blank lines (a single empty field)
            guard row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }

            func field(_ column: Column) -> String? {
                guard let index = indexes[column], index < row.count else { return nil }
                let value = unneutralized(row[index].trimmingCharacters(in: .whitespacesAndNewlines))
                return value.isEmpty ? nil : value
            }
            func number(_ column: Column) -> Double? {
                guard var value = field(column) else { return nil }
                if decimalComma { value = value.replacingOccurrences(of: ",", with: ".") }
                return Double(value)
            }

            return ImportedTreeRecord(
                id: field(.id),
                latitude: number(.latitude) ?? Self.invalidLatitude,
                longitude: number(.longitude) ?? 0,
                horizontalAccuracy: max(number(.accuracy) ?? 0, 0),
                altitude: number(.altitude),
                species: field(.species) ?? "",
                variety: field(.variety),
                rootstock: field(.rootstock),
                notes: field(.notes) ?? "",
                createdAt: isoDateString(field(.createdAt)),
                updatedAt: isoDateString(field(.updatedAt))
            )
        }

        return ImportedArchive(version: nil, collections: nil, trees: trees)
    }

    /// Out of range on purpose: the import service rejects it and reports the row.
    static let invalidLatitude: Double = 999

    /// Splits CSV text into rows of fields, honouring quoted fields that
    /// contain delimiters, doubled quotes, and line breaks.
    static func parseRows(_ text: String, delimiter: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var fieldWasQuoted = false

        func endField() {
            row.append(field)
            field = ""
            fieldWasQuoted = false
        }
        func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        var iterator = text.makeIterator()
        var pending: Character?
        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" && field.isEmpty && !fieldWasQuoted {
                inQuotes = true
                fieldWasQuoted = true
            } else if character == delimiter {
                endField()
            } else if character == "\n" || character == "\r\n" || character == "\r" {
                endRow()
            } else {
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty || fieldWasQuoted {
            endRow()
        }
        return rows
    }

    private static func detectDelimiter(in text: String) -> Character {
        let headerLine = text.prefix { !$0.isNewline }
        let candidates: [Character] = [",", ";", "\t"]
        return candidates.max { lhs, rhs in
            headerLine.filter { $0 == lhs }.count < headerLine.filter { $0 == rhs }.count
        } ?? ","
    }

    /// Undoes the apostrophe the CSV exporter puts before formula-like text.
    private static func unneutralized(_ value: String) -> String {
        guard value.hasPrefix("'"), let second = value.dropFirst().first, "=+-@".contains(second) else {
            return value
        }
        return String(value.dropFirst())
    }

    private static let dateFormats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"]

    /// Normalises spreadsheet-style dates to the ISO 8601 text the import
    /// models carry. Unreadable dates become nil (the import uses "now").
    private static func isoDateString(_ value: String?) -> String? {
        guard let value else { return nil }
        if ImportDateParser.date(from: value) != nil {
            return value
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return ISO8601DateFormatter().string(from: date)
            }
        }
        return nil
    }
}
