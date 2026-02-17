import SwiftData

enum TreesSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Tree.self, Collection.self, Photo.self, Note.self]
    }
}

enum TreesMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TreesSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
