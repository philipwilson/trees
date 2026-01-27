import Foundation
import SwiftData

@Model
class Tree {
    var id: UUID = UUID()
    var latitude: Double = 0
    var longitude: Double = 0
    var horizontalAccuracy: Double = 0
    var altitude: Double?
    var species: String = ""
    var variety: String?
    var rootstock: String?
    var collection: Collection?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Photos directly attached to this tree
    @Relationship(deleteRule: .cascade, inverse: \Photo.tree)
    var photos: [Photo]?

    // Notes/observations about this tree
    @Relationship(deleteRule: .cascade, inverse: \Note.tree)
    var notes: [Note]?

    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        altitude: Double? = nil,
        species: String = "",
        variety: String? = nil,
        rootstock: String? = nil,
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

    /// Safe accessor for photos array
    var treePhotos: [Photo] {
        photos ?? []
    }

    /// Safe accessor for notes array
    var treeNotes: [Note] {
        notes ?? []
    }

    /// All photos including those attached to notes
    var allPhotos: [Photo] {
        var result = treePhotos
        for note in treeNotes {
            result.append(contentsOf: note.notePhotos)
        }
        return result
    }

    /// Adds a photo directly to this tree
    func addPhoto(_ data: Data, capturedAt: Date? = Date()) {
        let photo = Photo(imageData: data, captureDate: capturedAt)
        photo.tree = self
        if photos == nil {
            photos = []
        }
        photos?.append(photo)
        updatedAt = Date()
    }

    /// Removes a photo from this tree
    func removePhoto(_ photo: Photo) {
        photos?.removeAll { $0.id == photo.id }
        updatedAt = Date()
    }

    /// Adds a new note to this tree
    func addNote(text: String, photos: [Data] = []) -> Note {
        let note = Note(text: text)
        note.tree = self
        for photoData in photos {
            note.addPhoto(photoData)
        }
        if self.notes == nil {
            self.notes = []
        }
        self.notes?.append(note)
        updatedAt = Date()
        return note
    }

    /// Removes a note from this tree
    func removeNote(_ note: Note) {
        notes?.removeAll { $0.id == note.id }
        updatedAt = Date()
    }
}
