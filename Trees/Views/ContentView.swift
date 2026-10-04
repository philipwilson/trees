import SwiftUI

struct ContentView: View {
    var isCloudSyncActive = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(PendingPhotoImportQueue.self) private var photoImportQueue: PendingPhotoImportQueue?
    @State private var showingSyncWarning = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadContentView()
            } else {
                iPhoneContentView()
            }
        }
        .overlay(alignment: .top) {
            if let queue = photoImportQueue, queue.isRunning {
                Label("Adding photos \(queue.completedCount)/\(queue.totalCount)", systemImage: "photo.on.rectangle")
                    .font(.caption)
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: photoImportQueue?.isRunning)
        .alert("Photo Import Incomplete", isPresented: Binding(
            get: { photoImportQueue?.failureMessage != nil },
            set: { if !$0 { photoImportQueue?.failureMessage = nil } }
        )) {
            Button("OK") { photoImportQueue?.failureMessage = nil }
        } message: {
            if let message = photoImportQueue?.failureMessage { Text(message) }
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
