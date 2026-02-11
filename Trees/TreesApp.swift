import SwiftUI
import SwiftData

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
                configuration = ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .private("iCloud.com.treetracker.Trees")
                )
            } else {
                configuration = ModelConfiguration(schema: schema)
            }

            modelContainer = try ModelContainer(for: schema, configurations: [configuration])

        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
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
