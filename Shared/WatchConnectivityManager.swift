import Foundation
import WatchConnectivity

/// Manages Watch Connectivity session between iPhone and Apple Watch
@Observable
final class WatchConnectivityManager: NSObject {
    static let shared = WatchConnectivityManager()

    private(set) var isReachable = false
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false

    /// Pending trees that failed to send (Watch side only)
    private(set) var pendingTrees: [WatchTree] = []

    /// Callback for when new trees are received (iPhone side)
    var onTreesReceived: (([WatchTree]) -> Void)?

    private var session: WCSession?
    #if os(watchOS)
    private let pendingTreesKey = "pendingWatchTrees"
    #endif

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    #if os(watchOS)
    /// Send a captured tree to the iPhone. Must be called on the main thread.
    func sendTree(_ tree: WatchTree) {
        assert(Thread.isMainThread, "sendTree must be called on the main thread")
        guard let session = session, session.activationState == .activated else {
            enqueuePendingTree(tree)
            return
        }

        do {
            let data = try JSONEncoder().encode(tree)
            let context: [String: Any] = [
                "tree": data,
                "timestamp": Date().timeIntervalSince1970
            ]

            session.transferUserInfo(context)
        } catch {
            enqueuePendingTree(tree)
        }
    }

    /// Retry sending any pending trees. Must be called on the main thread.
    func retrySendingPendingTrees() {
        assert(Thread.isMainThread, "retrySendingPendingTrees must be called on the main thread")
        guard let session = session, session.activationState == .activated else { return }

        let treesToSend = pendingTrees
        pendingTrees.removeAll()
        savePendingTrees()

        for tree in treesToSend {
            sendTree(tree)
        }
    }

    private static let maxPendingTrees = 100

    private func enqueuePendingTree(_ tree: WatchTree) {
        guard !pendingTrees.contains(where: { $0.id == tree.id }) else { return }
        pendingTrees.append(tree)
        // Drop oldest entries if queue exceeds limit
        if pendingTrees.count > Self.maxPendingTrees {
            pendingTrees.removeFirst(pendingTrees.count - Self.maxPendingTrees)
        }
        savePendingTrees()
    }

    private func savePendingTrees() {
        guard let data = try? JSONEncoder().encode(pendingTrees) else { return }
        UserDefaults.standard.set(data, forKey: pendingTreesKey)
    }

    private func loadPendingTrees() {
        guard let data = UserDefaults.standard.data(forKey: pendingTreesKey),
              let trees = try? JSONDecoder().decode([WatchTree].self, from: data) else { return }
        var seenIDs = Set<UUID>()
        let dedupedTrees = trees.filter { seenIDs.insert($0.id).inserted }
        pendingTrees = dedupedTrees
        if dedupedTrees.count != trees.count {
            savePendingTrees()
        }
    }
    #endif
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable

            #if os(iOS)
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            #endif

            #if os(watchOS)
            self.loadPendingTrees()
            if activationState == .activated && !self.pendingTrees.isEmpty {
                self.retrySendingPendingTrees()
            }
            #endif
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable

            #if os(watchOS)
            if session.isReachable && !self.pendingTrees.isEmpty {
                self.retrySendingPendingTrees()
            }
            #endif
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        #if os(iOS)
        guard let treeData = userInfo["tree"] as? Data,
              let tree = try? JSONDecoder().decode(WatchTree.self, from: treeData) else { return }

        DispatchQueue.main.async {
            self.onTreesReceived?([tree])
        }
        #endif
    }
}
