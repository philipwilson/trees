import Foundation

/// Lightweight tree data structure for Watch-to-iPhone sync
/// Not a SwiftData @Model - just a Codable struct for transfer
struct WatchTree: Codable, Identifiable, Sendable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let altitude: Double?
    let species: String
    let notes: String
    let capturedAt: Date

    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        altitude: Double? = nil,
        species: String,
        notes: String = "",
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.altitude = altitude
        self.species = species
        self.notes = notes
        self.capturedAt = capturedAt
    }
}
