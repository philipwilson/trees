import Foundation
import SwiftData

@Model
class Note {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // The tree this note belongs to
    var tree: Tree?

    // Photos attached to this note
    @Relationship(deleteRule: .cascade, inverse: \Photo.note)
    var photos: [Photo]?

    init(
        id: UUID = UUID(),
        text: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Note {
    var formattedDate: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var notePhotos: [Photo] {
        photos ?? []
    }

    func addPhoto(_ data: Data, capturedAt: Date? = Date()) {
        let photo = Photo(imageData: data, captureDate: capturedAt)
        photo.note = self
        if photos == nil {
            photos = []
        }
        photos?.append(photo)
        updatedAt = Date()
    }
}
