import Foundation
import SwiftData

/// Drip-feeds imported photos into the store one tree at a time so CloudKit
/// sync keeps up with large imports.
///
/// Photos wait on disk (not in memory), so the work survives the import view
/// being dismissed and the app being killed: `resume()` at launch picks up
/// whatever is left. Each file's name records where the photo belongs, so
/// there is no separate index that could be lost or corrupted — a photo on
/// disk is always recoverable. Targets are looked up by ID when their turn
/// comes, so a tree or note deleted in the meantime is skipped.
///
/// A photo's file is only removed once it has been saved, or once its target
/// is known to be gone. Any failure leaves it in place for the next launch.
@MainActor
@Observable
final class PendingPhotoImportQueue {
    /// A spooled photo, described entirely by its file name:
    /// `<order>~<tree UUID>~<note UUID or "tree">~<capture ms or "nodate">.photo`
    struct Entry: Equatable, Sendable {
        let fileName: String
        let treeID: UUID
        let noteID: UUID?
        let captureDate: Date?

        static let fileExtension = "photo"

        init(order: String, treeID: UUID, noteID: UUID?, captureDate: Date?) {
            let note = noteID?.uuidString ?? "tree"
            let date = captureDate.map { String(Int64(($0.timeIntervalSince1970 * 1000).rounded())) } ?? "nodate"
            fileName = "\(order)~\(treeID.uuidString)~\(note)~\(date).\(Self.fileExtension)"
            self.treeID = treeID
            self.noteID = noteID
            self.captureDate = captureDate
        }

        /// Nil for anything that isn't one of our spooled photos.
        init?(fileName: String) {
            let url = URL(fileURLWithPath: fileName)
            guard url.pathExtension == Self.fileExtension else { return nil }
            let parts = url.deletingPathExtension().lastPathComponent.split(separator: "~", omittingEmptySubsequences: false)
            guard parts.count == 4, let treeID = UUID(uuidString: String(parts[1])) else { return nil }

            if parts[2] == "tree" {
                noteID = nil
            } else if let note = UUID(uuidString: String(parts[2])) {
                noteID = note
            } else {
                return nil
            }

            if parts[3] == "nodate" {
                captureDate = nil
            } else if let milliseconds = Int64(parts[3]) {
                captureDate = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
            } else {
                return nil
            }

            self.fileName = fileName
            self.treeID = treeID
        }
    }

    /// What became of the photos handed to `enqueue`.
    struct EnqueueResult: Equatable, Sendable {
        /// Written to disk and scheduled
        var queued = 0
        /// Not valid image data in the import file; nothing to recover
        var unreadable = 0
        /// Could not be written to disk (e.g. storage full); not imported
        var failed = 0
    }

    /// Photos in the current run, and how many of those are finished
    /// (attached, or skipped because their target is gone).
    private(set) var totalCount = 0
    private(set) var completedCount = 0

    /// Set when a run finishes with photos that could not be saved, or when
    /// photos from an earlier session could not be recovered.
    var failureMessage: String?

    var isRunning: Bool { drainTask != nil }

    // The context does not keep its container alive, so hold the container.
    private let modelContainer: ModelContainer
    private let directory: URL
    private let delayBetweenTrees: Duration

    private var entries: [Entry] = []
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

        switch Self.migrateLegacyManifest(in: directory) {
        case .nothingToMigrate, .migrated:
            break
        case .unreadable(let photoCount):
            // The old index is damaged, so these photos can't be matched to
            // trees. Leave them where they are rather than deleting them.
            if photoCount > 0 {
                failureMessage = "\(photoCount) photo\(photoCount == 1 ? "" : "s") from an interrupted import could not be matched to trees. Import the backup file again to restore them."
            }
        }

        entries = Self.pendingEntries(in: directory)
        totalCount = entries.count
        completedCount = 0
        startIfNeeded()
    }

    /// Writes the photos to disk and schedules them.
    @discardableResult
    func enqueue(_ photos: [TreeImportService.DeferredPhoto]) async -> EnqueueResult {
        let directory = directory
        let (spooled, result) = await Task.detached(priority: .userInitiated) {
            Self.spool(photos, into: directory)
        }.value

        if !spooled.isEmpty {
            entries.append(contentsOf: spooled)
            totalCount += spooled.count
            startIfNeeded()
        }
        return result
    }

    /// Suspends until the current run finishes.
    func waitUntilIdle() async {
        await drainTask?.value
    }

    // MARK: - Draining

    private enum BatchOutcome {
        /// Saved, or nothing to save because the target is gone: files can go
        case finished
        /// Could not be completed now: files must stay for the next launch
        case failed
    }

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
            entries.removeFirst(batch.count)

            switch attach(batch) {
            case .finished:
                for entry in batch {
                    try? FileManager.default.removeItem(at: directory.appending(path: entry.fileName))
                }
            case .failed:
                // Left on disk; resume() picks them up at the next launch
                // rather than looping on a persistent error now.
                failedCount += batch.count
            }
            completedCount += batch.count
        }

        if failedCount > 0 {
            failureMessage = "\(failedCount) imported photo\(failedCount == 1 ? "" : "s") could not be saved. They have been kept and will be retried the next time the app starts."
        }
        totalCount = 0
        completedCount = 0
        drainTask = nil
    }

    /// Attaches one tree's photos and saves.
    private func attach(_ batch: [Entry]) -> BatchOutcome {
        guard let treeID = batch.first?.treeID else { return .finished }
        let context = modelContainer.mainContext

        let tree: Tree?
        do {
            tree = try fetchTree(treeID, context)
        } catch {
            // A failed lookup says nothing about whether the tree exists
            print("Photo import: could not look up tree \(treeID): \(error)")
            return .failed
        }
        // Deleted since the import: its photos have nowhere to go
        guard let tree, !tree.isDeleted else { return .finished }

        for entry in batch {
            var note: Note?
            if let noteID = entry.noteID {
                note = tree.treeNotes.first { $0.id == noteID && !$0.isDeleted }
                if note == nil { continue }
            }

            let url = directory.appending(path: entry.fileName)
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                if FileManager.default.fileExists(atPath: url.path) {
                    // Present but unreadable right now: keep it for a retry
                    print("Photo import: could not read \(entry.fileName): \(error)")
                    context.rollback()
                    return .failed
                }
                continue
            }
            TreeImportService.attachPhoto(data: data, captureDate: entry.captureDate, to: tree, note: note)
        }

        do {
            try context.save()
            return .finished
        } catch {
            print("Photo import: failed to save photos for tree \(treeID): \(error)")
            context.rollback()
            return .failed
        }
    }

    /// Looks up a tree by ID. Replaceable so tests can simulate a store error.
    var fetchTree: (UUID, ModelContext) throws -> Tree? = { treeID, context in
        try context.fetch(FetchDescriptor<Tree>(predicate: #Predicate { $0.id == treeID })).first
    }

    // MARK: - Disk

    nonisolated static func spool(
        _ photos: [TreeImportService.DeferredPhoto],
        into directory: URL
    ) -> (entries: [Entry], result: EnqueueResult) {
        var result = EnqueueResult()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("Photo import: cannot create spool directory: \(error)")
            result.failed = photos.count
            return ([], result)
        }

        // Names sort in the order photos were queued, across separate imports
        let batchPrefix = String(format: "%013lld", Int64(Date().timeIntervalSince1970 * 1000))

        var entries: [Entry] = []
        for (index, photo) in photos.enumerated() {
            guard let data = Data(base64Encoded: photo.base64) else {
                result.unreadable += 1
                continue
            }
            let entry = Entry(
                order: "\(batchPrefix)-\(String(format: "%06d", index))",
                treeID: photo.treeID,
                noteID: photo.noteID,
                captureDate: photo.captureDate
            )
            do {
                try data.write(to: directory.appending(path: entry.fileName), options: .atomic)
            } catch {
                print("Photo import: failed to spool photo: \(error)")
                result.failed += 1
                continue
            }
            entries.append(entry)
            result.queued += 1
        }
        return (entries, result)
    }

    /// Every spooled photo in the directory, in queue order. Files with names
    /// this queue didn't produce are ignored, never deleted.
    nonisolated static func pendingEntries(in directory: URL) -> [Entry] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.sorted().compactMap(Entry.init(fileName:))
    }

    // MARK: - Legacy manifest

    // The first version of this queue named files randomly and kept their
    // targets in manifest.json. Convert any such leftover to the current
    // self-describing names.

    private struct LegacyEntry: Codable {
        let fileName: String
        let treeID: UUID
        let noteID: UUID?
        let captureDate: Date?
    }

    enum LegacyMigration: Equatable {
        case nothingToMigrate
        case migrated(Int)
        /// The manifest exists but can't be read; the photo files are untouched
        case unreadable(photoCount: Int)
    }

    nonisolated static let legacyManifestName = "manifest.json"

    @discardableResult
    nonisolated static func migrateLegacyManifest(in directory: URL) -> LegacyMigration {
        let fileManager = FileManager.default
        let manifestURL = directory.appending(path: legacyManifestName)
        guard fileManager.fileExists(atPath: manifestURL.path) else { return .nothingToMigrate }

        guard let data = try? Data(contentsOf: manifestURL),
              let legacy = try? JSONDecoder().decode([LegacyEntry].self, from: data) else {
            let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
            let orphaned = names.filter { $0.hasSuffix(".\(Entry.fileExtension)") && Entry(fileName: $0) == nil }
            // Move the damaged index aside so this isn't reported every launch
            try? fileManager.moveItem(at: manifestURL, to: directory.appending(path: "manifest.unreadable.json"))
            return .unreadable(photoCount: orphaned.count)
        }

        var migrated = 0
        for (index, old) in legacy.enumerated() {
            let entry = Entry(
                order: "0000000000000-\(String(format: "%06d", index))",
                treeID: old.treeID,
                noteID: old.noteID,
                captureDate: old.captureDate
            )
            let source = directory.appending(path: old.fileName)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            do {
                try fileManager.moveItem(at: source, to: directory.appending(path: entry.fileName))
                migrated += 1
            } catch {
                print("Photo import: could not migrate \(old.fileName): \(error)")
            }
        }
        try? fileManager.removeItem(at: manifestURL)
        return .migrated(migrated)
    }
}
