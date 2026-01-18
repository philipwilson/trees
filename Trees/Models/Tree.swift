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
}
