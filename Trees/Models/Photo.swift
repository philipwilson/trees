import Foundation
import SwiftData

@Model
class Photo {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data = Data()
    var captureDate: Date?
    var createdAt: Date = Date()

    // A photo belongs to either a Tree directly OR a Note (not both)
    var tree: Tree?
    var note: Note?

    init(
        id: UUID = UUID(),
        imageData: Data,
        captureDate: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.imageData = imageData
        self.captureDate = captureDate
        self.createdAt = createdAt
    }
}

extension Photo {
    /// SwiftData to-many relationships have no stable order, so photo lists are
    /// sorted by when they were added (id breaks ties) wherever they are read.
    static func isOrderedBefore(_ lhs: Photo, _ rhs: Photo) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
