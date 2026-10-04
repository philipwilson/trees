import SwiftUI
import SwiftData

struct ContentView: View {
    var isCloudSyncActive = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(PendingPhotoImportQueue.self) private var photoImportQueue: PendingPhotoImportQueue?
    @Environment(NoticeCenter.self) private var noticeCenter: NoticeCenter?
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showingWelcome = false
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
            VStack(spacing: 6) {
                if let queue = photoImportQueue, queue.isRunning {
                    Label("Adding photos \(queue.completedCount)/\(queue.totalCount)", systemImage: "photo.on.rectangle")
                        .monospacedDigit()
                        .statusCapsule()
                }
                if let notice = noticeCenter?.current {
                    Label(notice.text, systemImage: notice.systemImage)
                        .statusCapsule()
                        .onTapGesture {
                            noticeCenter?.dismiss()
                        }
                }
            }
            .padding(.top, 4)
        }
        .animation(.default, value: photoImportQueue?.isRunning)
        .animation(.default, value: noticeCenter?.current)
        .sheet(isPresented: $showingWelcome, onDismiss: {
            // Held back so the alert doesn't fight the welcome sheet
            if !isCloudSyncActive {
                showingSyncWarning = true
            }
        }) {
            WelcomeView()
        }
        .alert("Photo Import Incomplete", isPresented: Binding(
            get: { photoImportQueue?.failureMessage != nil },
            set: { if !$0 { photoImportQueue?.failureMessage = nil } }
        )) {
            Button("OK") { photoImportQueue?.failureMessage = nil }
        } message: {
            if let message = photoImportQueue?.failureMessage { Text(message) }
        }
        .onAppear {
            if !hasSeenWelcome {
                hasSeenWelcome = true
                // Only for a genuinely new user, not someone updating the app
                let treeCount = (try? modelContext.fetchCount(FetchDescriptor<Tree>())) ?? 0
                showingWelcome = treeCount == 0
            }
            if !isCloudSyncActive && !showingWelcome {
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

private extension View {
    /// The floating pill used for background status at the top of the screen.
    func statusCapsule() -> some View {
        font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .transition(.opacity)
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
