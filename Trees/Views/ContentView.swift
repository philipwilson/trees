import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TreeListView()
                .tabItem {
                    Label("Trees", systemImage: "tree.fill")
                }
                .tag(0)

            TreeMapView()
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(1)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Tree.self, inMemory: true)
}
