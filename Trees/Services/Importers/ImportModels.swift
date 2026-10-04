import Foundation

/// Result of an import operation, shown to the user.
struct ImportResult {
    let success: Bool
    let message: String
}

/// Parses ISO8601 date strings with or without fractional seconds.
/// Files produced by other tools often include fractional seconds, which the
/// default ISO8601DateFormatter rejects.
enum ImportDateParser {
    private static let standard = ISO8601DateFormatter()

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return standard.date(from: string) ?? fractional.date(from: string)
    }
}

/// A photo in the v2 export format.
struct ImportedPhotoRecord: Codable {
    let data: String          // base64-encoded image data
    let captureDate: String?  // ISO8601

    var parsedCaptureDate: Date? { ImportDateParser.date(from: captureDate) }
}

/// A structured note in the v2 export format.
struct ImportedNoteRecord: Codable {
    let text: String
    let createdAt: String?
    let updatedAt: String?
    let photos: [ImportedPhotoRecord]?

    var parsedCreatedAt: Date? { ImportDateParser.date(from: createdAt) }
    var parsedUpdatedAt: Date? { ImportDateParser.date(from: updatedAt) }
}

struct ImportedCollectionRecord: Codable {
    let id: String
    let name: String
    let createdAt: String?
    let updatedAt: String?

    var parsedId: UUID? { UUID(uuidString: id) }
    var parsedCreatedAt: Date? { ImportDateParser.date(from: createdAt) }
    var parsedUpdatedAt: Date? { ImportDateParser.date(from: updatedAt) }
}

/// A tree record from any export format version.
/// v1 fields: `notes` (combined " | "-joined string), flat `photos`/`photoDates` arrays.
/// v2 fields: `noteEntries` (structured notes with their own photos), `treePhotos`
/// (photos owned by the tree itself). Import prefers v2 fields when present.
struct ImportedTreeRecord: Codable {
    let id: String?
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let altitude: Double?
    let species: String
    let variety: String?
    let rootstock: String?
    let notes: String
    let photos: [String]?           // legacy: base64 strings, tree + note photos flattened
    let photoDates: [Date]?         // legacy: capture dates as Date
    let photoDateStrings: [String]? // legacy: capture dates as ISO8601 strings
    let noteEntries: [ImportedNoteRecord]?
    let treePhotos: [ImportedPhotoRecord]?
    let collectionId: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, horizontalAccuracy, altitude
        case species, variety, rootstock, notes, photos, photoDates
        case noteEntries, treePhotos, collectionId, createdAt, updatedAt
    }

    /// For sources other than JSON (e.g. CSV), which carry no photos or
    /// structured notes.
    init(
        id: String?,
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        altitude: Double?,
        species: String,
        variety: String?,
        rootstock: String?,
        notes: String,
        createdAt: String?,
        updatedAt: String?
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.altitude = altitude
        self.species = species
        self.variety = variety
        self.rootstock = rootstock
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        photos = nil
        photoDates = nil
        photoDateStrings = nil
        noteEntries = nil
        treePhotos = nil
        collectionId = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        horizontalAccuracy = try container.decode(Double.self, forKey: .horizontalAccuracy)
        altitude = try container.decodeIfPresent(Double.self, forKey: .altitude)
        species = try container.decode(String.self, forKey: .species)
        variety = try container.decodeIfPresent(String.self, forKey: .variety)
        rootstock = try container.decodeIfPresent(String.self, forKey: .rootstock)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        photos = try container.decodeIfPresent([String].self, forKey: .photos)
        noteEntries = try container.decodeIfPresent([ImportedNoteRecord].self, forKey: .noteEntries)
        treePhotos = try container.decodeIfPresent([ImportedPhotoRecord].self, forKey: .treePhotos)
        collectionId = try container.decodeIfPresent(String.self, forKey: .collectionId)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)

        // photoDates was written as Dates by some versions and ISO8601 strings by others
        if let dates = try? container.decodeIfPresent([Date].self, forKey: .photoDates) {
            photoDates = dates
            photoDateStrings = nil
        } else if let dateStrings = try? container.decodeIfPresent([String].self, forKey: .photoDates) {
            photoDateStrings = dateStrings
            photoDates = nil
        } else {
            photoDates = nil
            photoDateStrings = nil
        }
    }

    func legacyCaptureDate(at index: Int) -> Date? {
        if let dates = photoDates, dates.indices.contains(index) {
            return dates[index]
        }
        if let dateStrings = photoDateStrings, dateStrings.indices.contains(index) {
            return ImportDateParser.date(from: dateStrings[index])
        }
        return nil
    }

    var parsedCreatedAt: Date? { ImportDateParser.date(from: createdAt) }
    var parsedUpdatedAt: Date? { ImportDateParser.date(from: updatedAt) }
    var parsedId: UUID? { id.flatMap { UUID(uuidString: $0) } }
}

/// Top-level shape of a Trees JSON export.
/// v2 sets `version: 2`; v1 has no version field; the oldest format is a bare
/// tree array (see `TreeImportService.decode`).
struct ImportedArchive: Codable {
    let version: Int?
    let collections: [ImportedCollectionRecord]?
    let trees: [ImportedTreeRecord]
}
