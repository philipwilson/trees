import Foundation
import SwiftData

@Model
class Tree {
    var id: UUID
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var altitude: Double?
    var species: String
    var variety: String?
    var rootstock: String?
    var notes: String
    @Attribute(.externalStorage) var photos: [Data]
    /// Capture dates for each photo (parallel array to photos)
    /// Optional for backward compatibility with existing trees
    var photoDates: [Date]?
    var collection: Collection?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        altitude: Double? = nil,
        species: String = "",
        variety: String? = nil,
        rootstock: String? = nil,
        notes: String = "",
        photos: [Data] = [],
        photoDates: [Date]? = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
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
        self.photos = photos
        self.photoDates = photoDates
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Tree {
    var accuracyDescription: String {
        String(format: "%.1fm", horizontalAccuracy)
    }

    var coordinateString: String {
        String(format: "%.6f, %.6f", latitude, longitude)
    }

    var formattedDate: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    /// Gets the capture date for a photo at the given index
    /// Returns nil if no date is available (legacy photos)
    func photoDate(at index: Int) -> Date? {
        guard let dates = photoDates, index < dates.count else { return nil }
        return dates[index]
    }

    /// Formatted date string for a photo at the given index
    func formattedPhotoDate(at index: Int) -> String? {
        guard let date = photoDate(at: index) else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Adds a photo with its capture date
    func addPhoto(_ data: Data, capturedAt: Date = Date()) {
        photos.append(data)
        if photoDates == nil {
            photoDates = []
        }
        photoDates?.append(capturedAt)
    }

    /// Removes a photo and its date at the given index
    func removePhoto(at index: Int) {
        guard index < photos.count else { return }
        photos.remove(at: index)
        if let dates = photoDates, index < dates.count {
            photoDates?.remove(at: index)
        }
    }
}
