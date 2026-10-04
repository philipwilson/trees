import SwiftUI
import SwiftData

@main
struct TreesApp: App {
    let modelContainer: ModelContainer
    let isCloudSyncActive: Bool
    private let photoImportQueue: PendingPhotoImportQueue
    private let syncMonitor: SyncMonitor
    private let noticeCenter = NoticeCenter()

    private static let cloudKitContainerIdentifier = "iCloud.com.treetracker.Trees"

    // Set to true once Apple Developer Program enrollment is approved
    private static let enableCloudKit = true

    init() {
        let schema = Schema(versionedSchema: TreesSchemaV1.self)
        var cloudSyncActive = false

        if Self.enableCloudKit {
            do {
                let cloudConfig = ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .private(Self.cloudKitContainerIdentifier)
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
        photoImportQueue = PendingPhotoImportQueue(modelContainer: modelContainer)
        // Pick up photos from an import that was interrupted last session
        photoImportQueue.resume()
        syncMonitor = SyncMonitor(
            isCloudSyncActive: cloudSyncActive,
            containerIdentifier: Self.cloudKitContainerIdentifier
        )
        syncMonitor.start()
        setupWatchConnectivity()
    }

    private let photoViewerState = PhotoViewerState()

    var body: some Scene {
        WindowGroup {
            ContentView(isCloudSyncActive: isCloudSyncActive)
                .environment(photoViewerState)
                .environment(photoImportQueue)
                .environment(syncMonitor)
                .environment(noticeCenter)
        }
        .modelContainer(modelContainer)
    }

    private func setupWatchConnectivity() {
        let manager = WatchConnectivityManager.shared
        let inbox = WatchTreeInbox()

        // Both run on the main queue; using the main context keeps @Query views in sync
        let announce: ([Tree]) -> Void = { [noticeCenter] imported in
            if let text = NoticeCenter.watchImportText(for: imported) {
                noticeCenter.show(text, systemImage: "applewatch")
            }
        }
        let processInbox: () -> Void = { [modelContainer] in
            let importer = WatchTreeImporter(modelContext: modelContainer.mainContext)
            announce(inbox.processPending(importTree: importer.importOutcome))
        }

        // Set before activating: queued deliveries can arrive immediately
        manager.inbox = inbox
        manager.onInboxChanged = processInbox
        manager.onTreesReceived = { [modelContainer] trees in
            let importer = WatchTreeImporter(modelContext: modelContainer.mainContext)
            announce(importer.importTrees(trees))
        }
        manager.activate()

        // Retry anything received in an earlier session that couldn't be saved
        processInbox()
    }
}
