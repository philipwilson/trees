import Foundation
import SwiftData

/// The schema version the app runs on. Model classes at the top level of the
/// module (Tree, Note, Photo, Collection) always belong to this version.
typealias CurrentTreesSchema = TreesSchemaV2

// To change the model:
// 1. Copy the current top-level model classes into a new nested, frozen set
//    inside the outgoing version's enum (as V1 has below).
// 2. Add TreesSchemaV3 listing the top-level classes, point CurrentTreesSchema
//    at it, and add a migration stage.
// 3. Add a frozen store fixture for the outgoing version to TreesTests.
// 4. Re-run the CloudKit schema initialiser (see CloudKitSchemaInitializer).
// CloudKit only allows additions: new fields must be optional or defaulted,
// and nothing may be renamed, retyped or removed.

/// Version 2: adds `Tree.label`.
enum TreesSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Tree.self, Collection.self, Photo.self, Note.self]
    }
}

/// Version 1, as first shipped. These nested classes are a frozen record of
/// that model and must never be edited: stores written by version 1 are
/// recognised by matching them.
enum TreesSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Tree.self, Collection.self, Photo.self, Note.self]
    }

    @Model
    final class Tree {
        var id: UUID = UUID()
        var latitude: Double = 0
        var longitude: Double = 0
        var horizontalAccuracy: Double = 0
        var altitude: Double?
        var species: String = ""
        var variety: String?
        var rootstock: String?
        @Relationship
        var collection: Collection?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        @Relationship(deleteRule: .cascade, inverse: \Photo.tree)
        var photos: [Photo]?

        @Relationship(deleteRule: .cascade, inverse: \Note.tree)
        var notes: [Note]?

        init() {}
    }

    @Model
    final class Note {
        var id: UUID = UUID()
        var text: String = ""
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var tree: Tree?

        @Relationship(deleteRule: .cascade, inverse: \Photo.note)
        var photos: [Photo]?

        init() {}
    }

    @Model
    final class Photo {
        var id: UUID = UUID()
        @Attribute(.externalStorage) var imageData: Data = Data()
        var captureDate: Date?
        var createdAt: Date = Date()
        var tree: Tree?
        var note: Note?

        init() {}
    }

    @Model
    final class Collection {
        var id: UUID = UUID()
        var name: String = ""
        @Relationship(deleteRule: .nullify, inverse: \Tree.collection)
        var trees: [Tree]?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init() {}
    }
}

enum TreesMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TreesSchemaV1.self, TreesSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            // Adds the optional Tree.label; no data needs transforming
            .lightweight(fromVersion: TreesSchemaV1.self, toVersion: TreesSchemaV2.self)
        ]
    }
}
