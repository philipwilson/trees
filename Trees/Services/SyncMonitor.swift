import Foundation
import CoreData
import CloudKit

/// What iCloud sync is doing, reduced from the stream of CloudKit sync
/// events. Kept separate from the monitor so the rules can be tested without
/// real events.
struct SyncState: Equatable {
    enum Status: Equatable {
        /// Sync is not enabled for this install
        case off
        /// The device isn't signed in to iCloud
        case noAccount
        case syncing
        /// Idle with no known problem
        case upToDate
        case failed(String)
    }

    private(set) var status: Status
    private(set) var lastSyncDate: Date?
    private var inFlight: Set<UUID> = []
    private var lastFailure: String?
    private var accountAvailable = true

    init(isCloudSyncActive: Bool) {
        status = isCloudSyncActive ? .upToDate : .off
    }

    /// An import/export/setup event started (`endDate` nil) or finished.
    mutating func apply(eventID: UUID, endDate: Date?, succeeded: Bool, failure: String?) {
        guard status != .off else { return }
        if let endDate {
            inFlight.remove(eventID)
            if succeeded {
                lastSyncDate = endDate
                lastFailure = nil
            } else {
                lastFailure = failure ?? "Sync could not complete."
            }
        } else {
            inFlight.insert(eventID)
        }
        refresh()
    }

    mutating func setAccountAvailable(_ available: Bool) {
        guard status != .off else { return }
        accountAvailable = available
        refresh()
    }

    private mutating func refresh() {
        if !accountAvailable {
            status = .noAccount
        } else if !inFlight.isEmpty {
            status = .syncing
        } else if let lastFailure {
            status = .failed(lastFailure)
        } else {
            status = .upToDate
        }
    }

    var title: String {
        switch status {
        case .off: return "iCloud Sync Off"
        case .noAccount: return "Not Signed In to iCloud"
        case .syncing: return "Syncing with iCloud"
        case .upToDate: return lastSyncDate == nil ? "iCloud Sync On" : "Up to Date"
        case .failed: return "iCloud Sync Problem"
        }
    }

    func detail(now: Date = Date()) -> String {
        let last = lastSyncDate.map { date -> String in
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return " Last synced \(formatter.localizedString(for: date, relativeTo: now))."
        } ?? ""

        switch status {
        case .off:
            return "Your trees are stored on this device only."
        case .noAccount:
            return "Sign in to iCloud in Settings to sync your trees between devices. Until then they are stored on this device only."
        case .syncing:
            return "Changes are being sent to or fetched from iCloud." + last
        case .upToDate:
            return lastSyncDate == nil
                ? "Your trees sync through your iCloud account. Nothing has needed syncing since the app opened."
                : "Your trees are synced with iCloud." + last
        case .failed(let message):
            return message + last + " Your trees are safe on this device and sync will retry automatically."
        }
    }

    var systemImage: String {
        switch status {
        case .off: return "icloud.slash"
        case .noAccount, .failed: return "exclamationmark.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        // The tick is a claim that a sync has completed, so it waits for one;
        // until then sync is merely switched on.
        case .upToDate: return lastSyncDate == nil ? "icloud" : "checkmark.icloud"
        }
    }

    var needsAttention: Bool {
        switch status {
        case .noAccount, .failed: return true
        case .off, .syncing, .upToDate: return false
        }
    }
}

/// Watches CloudKit sync events and iCloud account changes so the UI can
/// show whether data is actually syncing, instead of failing silently.
@MainActor
@Observable
final class SyncMonitor {
    private(set) var state: SyncState

    private let containerIdentifier: String
    private let isCloudSyncActive: Bool
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(isCloudSyncActive: Bool, containerIdentifier: String) {
        self.isCloudSyncActive = isCloudSyncActive
        self.containerIdentifier = containerIdentifier
        state = SyncState(isCloudSyncActive: isCloudSyncActive)
    }

    func start() {
        guard isCloudSyncActive, observers.isEmpty else { return }
        let center = NotificationCenter.default

        // SwiftData's CloudKit sync is NSPersistentCloudKitContainer underneath
        // and posts its progress through this notification.
        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let id = event.identifier
            let endDate = event.endDate
            let succeeded = event.succeeded
            let failure = event.error.map(Self.describe)
            MainActor.assumeIsolated {
                self?.state.apply(eventID: id, endDate: endDate, succeeded: succeeded, failure: failure)
            }
        })

        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkAccount()
            }
        })

        checkAccount()
    }

    private func checkAccount() {
        let container = CKContainer(identifier: containerIdentifier)
        Task {
            // An error here (e.g. offline) says nothing about the account
            guard let status = try? await container.accountStatus() else { return }
            state.setAccountAvailable(status != .noAccount && status != .restricted)
        }
    }

    nonisolated static func describe(_ error: Error) -> String {
        guard let ckError = error as? CKError else {
            return "Sync could not complete (\(error.localizedDescription))."
        }
        switch ckError.code {
        case .quotaExceeded:
            return "Your iCloud storage is full."
        case .notAuthenticated:
            return "This device isn't signed in to iCloud."
        case .networkUnavailable, .networkFailure:
            return "No network connection."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return "iCloud is busy."
        default:
            return "Sync could not complete (\(ckError.localizedDescription))."
        }
    }
}
