import Foundation
import SwiftData

@Model
class Collection {
    var id: UUID = UUID()
    var name: String = ""
    @Relationship(deleteRule: .nullify, inverse: \Tree.collection)
    var trees: [Tree]?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        trees: [Tree] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.trees = trees
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Collection {
    var treeCount: Int {
        trees?.count ?? 0
    }

    var formattedDate: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}
