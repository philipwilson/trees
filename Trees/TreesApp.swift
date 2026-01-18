import SwiftUI
import SwiftData

@main
struct TreesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Tree.self, Collection.self])
    }
}
