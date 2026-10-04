import Foundation

/// Holds trees received from the watch until they are safely in the store.
///
/// WatchConnectivity delivers each tree exactly once. If saving it then
/// fails, nothing would bring it back, so the raw payload is written here
/// first and only removed once the tree is saved (or found to be already
/// present). Anything left over is retried at the next launch or delivery.
final class WatchTreeInbox: Sendable {
    enum ImportOutcome {
        case imported(Tree)
        case alreadyPresent
        case failed
    }

    let directory: URL

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "WatchTreeInbox", directoryHint: .isDirectory)
    }

    init(directory: URL = WatchTreeInbox.defaultDirectory) {
        self.directory = directory
    }

    /// Writes a received payload to disk. Safe to call from any thread.
    /// Returns false if it could not be stored.
    @discardableResult
    func store(_ payload: Data) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Names sort in arrival order. The clock time orders trees across
            // launches; the uptime counter orders ones that arrive within the
            // same millisecond, where the clock alone would tie.
            let name = String(
                format: "%013lld-%020llu-%@.json",
                Int64(Date().timeIntervalSince1970 * 1000),
                DispatchTime.now().uptimeNanoseconds,
                UUID().uuidString
            )
            try payload.write(to: directory.appending(path: name), options: .atomic)
            return true
        } catch {
            print("Watch inbox: failed to store received tree: \(error)")
            return false
        }
    }

    var pendingCount: Int {
        pendingFiles().count
    }

    /// Imports everything waiting. A payload is removed once its tree is
    /// saved or already present; one that fails to save, or that this
    /// version of the app can't decode, stays for a later attempt.
    @MainActor
    func processPending(importTree: (WatchTree) -> ImportOutcome) -> [Tree] {
        var imported: [Tree] = []
        for url in pendingFiles() {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let watchTree = try? JSONDecoder().decode(WatchTree.self, from: data) else {
                // Likely sent by a newer watch app; a later update may read it
                print("Watch inbox: cannot decode \(url.lastPathComponent); keeping it")
                continue
            }

            switch importTree(watchTree) {
            case .imported(let tree):
                imported.append(tree)
                try? FileManager.default.removeItem(at: url)
            case .alreadyPresent:
                try? FileManager.default.removeItem(at: url)
            case .failed:
                print("Watch inbox: could not save tree \(watchTree.id); will retry")
            }
        }
        return imported
    }

    private func pendingFiles() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted().map { directory.appending(path: $0) }
    }
}
