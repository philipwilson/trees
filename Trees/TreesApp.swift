import SwiftUI
import SwiftData
import CloudKit
import CoreData

@main
struct TreesApp: App {
    let modelContainer: ModelContainer

    // Set to true once Apple Developer Program enrollment is approved
    private static let enableCloudKit = true

    init() {
        do {
            let schema = Schema([Tree.self, Collection.self, Photo.self, Note.self])
            let configuration: ModelConfiguration

            if Self.enableCloudKit {
                print("🌐 CloudKit: Enabling iCloud sync")
                // Let SwiftData manage the store location for proper CloudKit integration
                configuration = ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .private("iCloud.com.treetracker.Trees")
                )
                print("🌐 CloudKit: Configuration created for container iCloud.com.treetracker.Trees")
            } else {
                print("🌐 CloudKit: Disabled, using local storage only")
                configuration = ModelConfiguration(schema: schema)
            }

            modelContainer = try ModelContainer(for: schema, configurations: [configuration])

            // Try to initialize CloudKit schema if enabled
            if Self.enableCloudKit {
                initializeCloudKitSchema()
            }

            // Debug: Print store info
            for store in modelContainer.configurations {
                print("🌐 CloudKit: Store URL = \(store.url.absoluteString)")
                print("🌐 CloudKit: CloudKit database = \(String(describing: store.cloudKitDatabase))")
            }

            // Check CloudKit account status
            CKContainer(identifier: "iCloud.com.treetracker.Trees").accountStatus { status, error in
                if let error = error {
                    print("🌐 CloudKit: Account status error: \(error)")
                } else {
                    switch status {
                    case .available:
                        print("🌐 CloudKit: Account status = available ✅")
                    case .noAccount:
                        print("🌐 CloudKit: Account status = noAccount ❌")
                    case .restricted:
                        print("🌐 CloudKit: Account status = restricted ❌")
                    case .couldNotDetermine:
                        print("🌐 CloudKit: Account status = couldNotDetermine ⚠️")
                    case .temporarilyUnavailable:
                        print("🌐 CloudKit: Account status = temporarilyUnavailable ⚠️")
                    @unknown default:
                        print("🌐 CloudKit: Account status = unknown")
                    }
                }
            }

        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        setupWatchConnectivity()
        setupCloudKitNotifications()
    }

    private func initializeCloudKitSchema() {
        // Test direct CloudKit write to verify connectivity
        let container = CKContainer(identifier: "iCloud.com.treetracker.Trees")
        let privateDB = container.privateCloudDatabase

        // Create a simple test record directly in CloudKit
        let testRecord = CKRecord(recordType: "TestRecord")
        testRecord["testField"] = "Hello from Tree Tracker at \(Date())" as CKRecordValue

        print("🌐 CloudKit Test: Attempting to save test record...")

        privateDB.save(testRecord) { record, error in
            if let error = error {
                print("🌐 CloudKit Test: FAILED to save record: \(error.localizedDescription)")
                if let ckError = error as? CKError {
                    print("🌐 CloudKit Test: CKError code: \(ckError.code.rawValue)")
                    print("🌐 CloudKit Test: CKError userInfo: \(ckError.userInfo)")
                }
            } else if let record = record {
                print("🌐 CloudKit Test: SUCCESS! Record saved with ID: \(record.recordID.recordName)")
            }
        }
    }

    private func setupCloudKitNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.CKAccountChanged,
            object: nil,
            queue: .main
        ) { _ in
            print("🌐 CloudKit: Account changed notification received")
        }

        // Listen for Core Data remote change notifications (CloudKit sync)
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { notification in
            print("🌐 CloudKit: Remote change notification received")
            if let userInfo = notification.userInfo {
                print("🌐 CloudKit: Remote change userInfo: \(userInfo)")
            }
        }

        // Listen for NSManagedObjectContext save notifications
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { notification in
            print("🌐 CloudKit: Context did save notification")
        }

        // Try a direct CloudKit operation to verify connectivity
        let container = CKContainer(identifier: "iCloud.com.treetracker.Trees")
        let privateDB = container.privateCloudDatabase

        // Fetch user record to verify CloudKit is working
        container.fetchUserRecordID { recordID, error in
            if let error = error {
                print("🌐 CloudKit: Failed to fetch user record: \(error)")
            } else if let recordID = recordID {
                print("🌐 CloudKit: User record ID = \(recordID.recordName) ✅")
            }
        }

        // List all record zones to see if SwiftData created one
        privateDB.fetchAllRecordZones { zones, error in
            if let error = error {
                print("🌐 CloudKit: Failed to fetch zones: \(error)")
            } else if let zones = zones {
                print("🌐 CloudKit: Found \(zones.count) zone(s)")
                for zone in zones {
                    print("🌐 CloudKit: Zone: \(zone.zoneID.zoneName)")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }

    private func setupWatchConnectivity() {
        let manager = WatchConnectivityManager.shared
        manager.activate()

        manager.onTreesReceived = { [modelContainer] trees in
            let context = ModelContext(modelContainer)
            let importer = WatchTreeImporter(modelContext: context)
            importer.importTrees(trees)
        }
    }
}
