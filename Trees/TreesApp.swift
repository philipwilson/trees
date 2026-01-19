import SwiftUI
import SwiftData

@main
struct TreesApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: Tree.self, Collection.self)
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
