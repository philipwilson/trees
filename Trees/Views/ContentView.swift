import SwiftUI

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadContentView()
        } else {
            iPhoneContentView()
        }
    }
}

struct iPhoneContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TreeListView()
                .tabItem {
                    Label("Trees", systemImage: "tree.fill")
                }
                .tag(0)

            CollectionListView()
                .tabItem {
                    Label("Collections", systemImage: "folder.fill")
                }
                .tag(1)

            TreeMapView()
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(2)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Tree.self, Collection.self], inMemory: true)
}
