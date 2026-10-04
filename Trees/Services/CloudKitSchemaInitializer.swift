#if DEBUG
import Foundation
import CoreData
import SwiftData

/// Pushes the complete data model to the CloudKit **development** schema.
///
/// CloudKit normally adds a record type or field to the development schema
/// only when a record that uses it is first saved, so anything the developer's
/// own data never filled in can be missing. Production does not add fields on
/// demand, so the development schema must be complete before it is deployed.
///
/// Run once, from a debug build on a device signed in to iCloud, before
/// deploying the schema in the CloudKit Console, and again after any model
/// change:
///
///     Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments, add
///     -initializeCloudKitSchema YES
///
/// Then check the result in the Xcode console and remove the argument.
/// It is compiled out of release builds.
enum CloudKitSchemaInitializer {
    static let launchArgument = "initializeCloudKitSchema"

    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: launchArgument)
    }

    /// The Core Data model CloudKit sync uses, built from the latest schema version.
    static func makeManagedObjectModel() -> NSManagedObjectModel? {
        guard let latest = TreesMigrationPlan.schemas.last else { return nil }
        return NSManagedObjectModel.makeManagedObjectModel(for: latest.models)
    }

    /// Uses a throwaway local store, so the app's real data is never opened
    /// or changed. Only the schema in CloudKit is affected.
    static func run(containerIdentifier: String) {
        print("CloudKit schema: initializing development schema for \(containerIdentifier)…")
        guard let model = makeManagedObjectModel() else {
            print("CloudKit schema: FAILED, could not build the model")
            return
        }

        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: "CloudKitSchemaInit-\(UUID().uuidString).store")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: containerIdentifier
        )
        description.shouldAddStoreAsynchronously = false

        let container = NSPersistentCloudKitContainer(name: "Trees", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            print("CloudKit schema: FAILED to open the temporary store: \(loadError)")
            return
        }

        do {
            try container.initializeCloudKitSchema()
            let entities = model.entities.compactMap(\.name).sorted().joined(separator: ", ")
            print("CloudKit schema: done. Record types now complete for: \(entities)")
            print("CloudKit schema: review it in the CloudKit Console before deploying to production.")
        } catch {
            print("CloudKit schema: FAILED: \(error)")
        }

        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(atPath: storeURL.path + suffix)
        }
    }
}
#endif
