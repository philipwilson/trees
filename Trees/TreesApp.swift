import SwiftUI
import SwiftData

@main
struct TreesApp: App {
    let modelContainer: ModelContainer
    let isCloudSyncActive: Bool

    // Set to true once Apple Developer Program enrollment is approved
    private static let enableCloudKit = true

    init() {
        let schema = Schema(versionedSchema: TreesSchemaV1.self)
        var cloudSyncActive = false

        if Self.enableCloudKit {
            do {
                let cloudConfig = ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .private("iCloud.com.treetracker.Trees")
                )
                modelContainer = try ModelContainer(
                    for: schema,
                    migrationPlan: TreesMigrationPlan.self,
                    configurations: [cloudConfig]
                )
                cloudSyncActive = true
            } catch {
                print("CloudKit ModelContainer failed, falling back to local-only: \(error)")
                do {
                    // .none is required: the default (.automatic) would pick the
                    // CloudKit container back up from the entitlements.
                    let localConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
                    modelContainer = try ModelContainer(
                        for: schema,
                        migrationPlan: TreesMigrationPlan.self,
                        configurations: [localConfig]
                    )
                } catch {
                    fatalError("Failed to create both CloudKit and local ModelContainer: \(error)")
                }
            }
        } else {
            do {
                let localConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
                modelContainer = try ModelContainer(
                    for: schema,
                    migrationPlan: TreesMigrationPlan.self,
                    configurations: [localConfig]
                )
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }

        isCloudSyncActive = cloudSyncActive
        setupWatchConnectivity()
    }

    private let photoViewerState = PhotoViewerState()

    var body: some Scene {
        WindowGroup {
            ContentView(isCloudSyncActive: isCloudSyncActive)
                .environment(photoViewerState)
        }
        .modelContainer(modelContainer)
    }

    private func setupWatchConnectivity() {
        let manager = WatchConnectivityManager.shared
        manager.activate()

        manager.onTreesReceived = { [modelContainer] trees in
            // Delivered on the main queue; using the main context keeps @Query views in sync
            let importer = WatchTreeImporter(modelContext: modelContainer.mainContext)
            _ = importer.importTrees(trees)
        }
    }
}
