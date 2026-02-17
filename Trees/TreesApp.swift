import SwiftUI
import SwiftData

@main
struct TreesApp: App {
    let modelContainer: ModelContainer

    // Set to true once Apple Developer Program enrollment is approved
    private static let enableCloudKit = true

    init() {
        let schema = Schema(versionedSchema: TreesSchemaV1.self)

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
            } catch {
                print("CloudKit ModelContainer failed, falling back to local-only: \(error)")
                do {
                    let localConfig = ModelConfiguration(schema: schema)
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
                let localConfig = ModelConfiguration(schema: schema)
                modelContainer = try ModelContainer(
                    for: schema,
                    migrationPlan: TreesMigrationPlan.self,
                    configurations: [localConfig]
                )
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }

        setupWatchConnectivity()
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
