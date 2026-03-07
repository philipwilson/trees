import SwiftUI

struct ContentView: View {
    var isCloudSyncActive = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingSyncWarning = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadContentView()
            } else {
                iPhoneContentView()
            }
        }
        .onAppear {
            if !isCloudSyncActive {
                showingSyncWarning = true
            }
        }
        .alert("iCloud Sync Unavailable", isPresented: $showingSyncWarning) {
            Button("OK") {}
        } message: {
            Text("iCloud sync could not be enabled. Your data will be stored locally only and won't sync across devices.")
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
