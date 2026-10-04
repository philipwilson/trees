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

    /// Trees handed to the system that haven't reached the iPhone yet (Watch side only)
    private(set) var outstandingTransferCount = 0

    /// Callback for trees received but not stored in the inbox (iPhone side).
    /// Only used as a fallback when the inbox is missing or can't be written.
    var onTreesReceived: (([WatchTree]) -> Void)?

    #if os(iOS)
    /// Where received trees are kept until saved. Set before `activate()`.
    @ObservationIgnored var inbox: WatchTreeInbox?
    /// Called on the main queue after a tree has been stored in the inbox.
    @ObservationIgnored var onInboxChanged: (() -> Void)?
    #endif

    private var session: WCSession?
    #if os(watchOS)
    private let pendingTreesKey = "pendingWatchTrees"
    #endif

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }

        #if os(watchOS)
        // Load before activating so a capture made prior to activation
        // enqueues alongside the persisted queue instead of overwriting it.
        loadPendingTrees()
        #endif

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    #if os(watchOS)
    /// Send a captured tree to the iPhone. Must be called on the main thread.
    func sendTree(_ tree: WatchTree) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.sendTree(tree) }
            return
        }
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
            outstandingTransferCount = session.outstandingUserInfoTransfers.count
        } catch {
            enqueuePendingTree(tree)
        }
    }

    /// Retry sending any pending trees. Must be called on the main thread.
    func retrySendingPendingTrees() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.retrySendingPendingTrees() }
            return
        }
        guard let session = session, session.activationState == .activated else { return }

        let treesToSend = pendingTrees
        pendingTrees.removeAll()
        savePendingTrees()

        for tree in treesToSend {
            sendTree(tree)
        }
    }

    // Deliberately uncapped: a WatchTree is a few hundred bytes, and dropping
    // entries would silently lose captured field data.
    private func enqueuePendingTree(_ tree: WatchTree) {
        guard !pendingTrees.contains(where: { $0.id == tree.id }) else { return }
        pendingTrees.append(tree)
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
        if let error {
            print("WatchConnectivity: activation failed: \(error)")
        }

        DispatchQueue.main.async {
            self.isReachable = session.isReachable

            #if os(iOS)
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            #endif

            #if os(watchOS)
            self.outstandingTransferCount = session.outstandingUserInfoTransfers.count
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

    #if os(watchOS)
    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard let error else {
            DispatchQueue.main.async {
                self.outstandingTransferCount = session.outstandingUserInfoTransfers.count
            }
            return
        }
        print("WatchConnectivity: tree transfer failed, re-queueing: \(error)")

        // The system has given up on this transfer; put the tree back in the
        // pending queue so it is retried instead of being lost.
        let tree = (userInfoTransfer.userInfo["tree"] as? Data)
            .flatMap { try? JSONDecoder().decode(WatchTree.self, from: $0) }
        DispatchQueue.main.async {
            if let tree {
                self.enqueuePendingTree(tree)
            }
            self.outstandingTransferCount = session.outstandingUserInfoTransfers.count
        }
    }
    #endif

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        #if os(iOS)
        guard let treeData = userInfo["tree"] as? Data else { return }

        // This delivery happens exactly once. Put the payload on disk before
        // returning, so a failed save later can be retried instead of losing
        // the tree. Importing happens from the inbox on the main queue.
        if let inbox, inbox.store(treeData) {
            DispatchQueue.main.async {
                self.onInboxChanged?()
            }
            return
        }

        // No inbox, or it couldn't be written: fall back to a direct import
        let tree: WatchTree
        do {
            tree = try JSONDecoder().decode(WatchTree.self, from: treeData)
        } catch {
            // transferUserInfo delivers exactly once — a dropped payload is gone for good
            print("WatchConnectivity: failed to decode received tree, payload lost: \(error)")
            return
        }

        DispatchQueue.main.async {
            self.onTreesReceived?([tree])
        }
        #endif
    }
}
