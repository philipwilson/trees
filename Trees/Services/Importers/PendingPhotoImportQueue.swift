import Foundation
import SwiftData

/// Drip-feeds imported photos into the store one tree at a time so CloudKit
/// sync keeps up with large imports.
///
/// Photos wait on disk (not in memory) alongside a manifest, so the work
/// survives the import view being dismissed and the app being killed:
/// `resume()` at launch picks up whatever is left. Targets are looked up by ID
/// when their turn comes, so a tree or note deleted in the meantime is skipped.
@MainActor
@Observable
final class PendingPhotoImportQueue {
    struct Entry: Codable, Equatable, Sendable {
        let fileName: String
        let treeID: UUID
        let noteID: UUID?
        let captureDate: Date?
    }

    /// Photos in the current run, and how many of those are finished
    /// (attached, or skipped because their target is gone).
    private(set) var totalCount = 0
    private(set) var completedCount = 0

    /// Set when a run finishes with photos that could not be saved.
    var failureMessage: String?

    var isRunning: Bool { drainTask != nil }

    // The context does not keep its container alive, so hold the container.
    private let modelContainer: ModelContainer
    private let directory: URL
    private let delayBetweenTrees: Duration

    private var entries: [Entry] = []
    /// Batches whose save failed this run; kept in the manifest and retried
    /// on the next launch rather than looping on a persistent error.
    private var retryLater: [Entry] = []
    private var drainTask: Task<Void, Never>?

    nonisolated static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "PendingPhotoImport", directoryHint: .isDirectory)
    }

    init(
        modelContainer: ModelContainer,
        directory: URL = PendingPhotoImportQueue.defaultDirectory,
        delayBetweenTrees: Duration = .seconds(2)
    ) {
        self.modelContainer = modelContainer
        self.directory = directory
        self.delayBetweenTrees = delayBetweenTrees
    }

    /// Continues an import interrupted in a previous session. Call once at launch.
    func resume() {
        guard drainTask == nil, entries.isEmpty else { return }
        entries = Self.readManifest(in: directory)
        Self.removeOrphanedFiles(in: directory, keeping: Set(entries.map(\.fileName)))
        totalCount = entries.count
        completedCount = 0
        startIfNeeded()
    }

    /// Writes the photos to disk and schedules them. Returns how many were
    /// accepted (photos with invalid data are dropped).
    @discardableResult
    func enqueue(_ photos: [TreeImportService.DeferredPhoto]) async -> Int {
        let directory = directory
        let spooled = await Task.detached(priority: .userInitiated) {
            Self.spool(photos, into: directory)
        }.value
        guard !spooled.isEmpty else { return 0 }

        entries.append(contentsOf: spooled)
        totalCount += spooled.count
        persistManifest()
        startIfNeeded()
        return spooled.count
    }

    /// Suspends until the current run finishes.
    func waitUntilIdle() async {
        await drainTask?.value
    }

    // MARK: - Draining

    private func startIfNeeded() {
        guard drainTask == nil, !entries.isEmpty else { return }
        drainTask = Task { await drain() }
    }

    private func drain() async {
        var failedCount = 0

        while let first = entries.first {
            try? await Task.sleep(for: delayBetweenTrees)

            // Entries are spooled tree by tree; one batch is one tree's photos
            let batch = Array(entries.prefix { $0.treeID == first.treeID })
            let saved = attach(batch)

            entries.removeFirst(batch.count)
            if saved {
                persistManifest()
                for entry in batch {
                    try? FileManager.default.removeItem(at: directory.appending(path: entry.fileName))
                }
            } else {
                failedCount += batch.count
                retryLater.append(contentsOf: batch)
                persistManifest()
            }
            completedCount += batch.count
        }

        if failedCount > 0 {
            failureMessage = "\(failedCount) imported photo\(failedCount == 1 ? "" : "s") could not be saved. They will be retried the next time the app starts."
        }
        totalCount = 0
        completedCount = 0
        drainTask = nil
    }

    /// Attaches one tree's photos and saves. Returns false only if the save
    /// failed; photos whose tree, note, or file is gone are skipped.
    private func attach(_ batch: [Entry]) -> Bool {
        guard let treeID = batch.first?.treeID else { return true }
        let context = modelContainer.mainContext

        let descriptor = FetchDescriptor<Tree>(predicate: #Predicate { $0.id == treeID })
        guard let tree = try? context.fetch(descriptor).first, !tree.isDeleted else { return true }

        for entry in batch {
            var note: Note?
            if let noteID = entry.noteID {
                note = tree.treeNotes.first { $0.id == noteID && !$0.isDeleted }
                if note == nil { continue }
            }
            guard let data = try? Data(contentsOf: directory.appending(path: entry.fileName)) else { continue }
            TreeImportService.attachPhoto(data: data, captureDate: entry.captureDate, to: tree, note: note)
        }

        do {
            try context.save()
            return true
        } catch {
            print("Photo import: failed to save photos for tree \(treeID): \(error)")
            context.rollback()
            return false
        }
    }

    private func persistManifest() {
        Self.writeManifest(entries + retryLater, in: directory)
    }

    // MARK: - Disk

    private nonisolated static let manifestName = "manifest.json"

    nonisolated static func spool(_ photos: [TreeImportService.DeferredPhoto], into directory: URL) -> [Entry] {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("Photo import: cannot create spool directory: \(error)")
            return []
        }

        var entries: [Entry] = []
        for photo in photos {
            guard let data = Data(base64Encoded: photo.base64) else { continue }
            let fileName = UUID().uuidString + ".photo"
            do {
                try data.write(to: directory.appending(path: fileName), options: .atomic)
            } catch {
                print("Photo import: failed to spool photo: \(error)")
                continue
            }
            entries.append(Entry(
                fileName: fileName,
                treeID: photo.treeID,
                noteID: photo.noteID,
                captureDate: photo.captureDate
            ))
        }
        return entries
    }

    nonisolated static func writeManifest(_ entries: [Entry], in directory: URL) {
        let url = directory.appending(path: manifestName)
        if entries.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try JSONEncoder().encode(entries).write(to: url, options: .atomic)
        } catch {
            print("Photo import: failed to write manifest: \(error)")
        }
    }

    nonisolated static func readManifest(in directory: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: directory.appending(path: manifestName)),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }

    /// Removes spooled photos that no manifest entry refers to (left behind if
    /// the app was killed between spooling and writing the manifest).
    private nonisolated static func removeOrphanedFiles(in directory: URL, keeping fileNames: Set<String>) {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in contents where name != manifestName && !fileNames.contains(name) {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }
}
