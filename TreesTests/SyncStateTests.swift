import XCTest
import SwiftData
import CloudKit
@testable import Trees

@MainActor
final class SyncStateTests: XCTestCase {
    private let finished = Date(timeIntervalSince1970: 1_700_000_000)

    func testSyncOffIgnoresEverything() {
        var state = SyncState(isCloudSyncActive: false)
        state.apply(eventID: UUID(), endDate: nil, succeeded: false, failure: nil)
        state.setAccountAvailable(false)

        XCTAssertEqual(state.status, .off)
        XCTAssertEqual(state.systemImage, "icloud.slash")
        XCTAssertFalse(state.needsAttention)
    }

    func testEventStartThenSuccessfulFinish() {
        var state = SyncState(isCloudSyncActive: true)
        XCTAssertEqual(state.status, .upToDate)
        XCTAssertEqual(state.title, "iCloud Sync On")

        let event = UUID()
        state.apply(eventID: event, endDate: nil, succeeded: false, failure: nil)
        XCTAssertEqual(state.status, .syncing)

        state.apply(eventID: event, endDate: finished, succeeded: true, failure: nil)
        XCTAssertEqual(state.status, .upToDate)
        XCTAssertEqual(state.lastSyncDate, finished)
        XCTAssertEqual(state.title, "Up to Date")
    }

    func testOverlappingEventsStaySyncingUntilAllFinish() {
        var state = SyncState(isCloudSyncActive: true)
        let importEvent = UUID(), exportEvent = UUID()
        state.apply(eventID: importEvent, endDate: nil, succeeded: false, failure: nil)
        state.apply(eventID: exportEvent, endDate: nil, succeeded: false, failure: nil)
        state.apply(eventID: importEvent, endDate: finished, succeeded: true, failure: nil)
        XCTAssertEqual(state.status, .syncing)

        state.apply(eventID: exportEvent, endDate: finished, succeeded: true, failure: nil)
        XCTAssertEqual(state.status, .upToDate)
    }

    func testFailureIsShownUntilALaterSuccess() {
        var state = SyncState(isCloudSyncActive: true)
        let failing = UUID()
        state.apply(eventID: failing, endDate: nil, succeeded: false, failure: nil)
        state.apply(eventID: failing, endDate: finished, succeeded: false, failure: "Your iCloud storage is full.")

        XCTAssertEqual(state.status, .failed("Your iCloud storage is full."))
        XCTAssertTrue(state.needsAttention)
        XCTAssertNil(state.lastSyncDate)
        XCTAssertTrue(state.detail().contains("safe on this device"))

        // A retry in progress shows as syncing, then clears the failure
        let retry = UUID()
        state.apply(eventID: retry, endDate: nil, succeeded: false, failure: nil)
        XCTAssertEqual(state.status, .syncing)
        state.apply(eventID: retry, endDate: finished, succeeded: true, failure: nil)
        XCTAssertEqual(state.status, .upToDate)
        XCTAssertFalse(state.needsAttention)
    }

    func testMissingAccountTakesPriorityAndRecovers() {
        var state = SyncState(isCloudSyncActive: true)
        state.setAccountAvailable(false)
        XCTAssertEqual(state.status, .noAccount)
        XCTAssertTrue(state.needsAttention)

        state.apply(eventID: UUID(), endDate: nil, succeeded: false, failure: nil)
        XCTAssertEqual(state.status, .noAccount)

        state.setAccountAvailable(true)
        XCTAssertEqual(state.status, .syncing)
    }

    func testDetailMentionsWhenItLastSynced() {
        var state = SyncState(isCloudSyncActive: true)
        state.apply(eventID: UUID(), endDate: finished, succeeded: true, failure: nil)

        let detail = state.detail(now: finished.addingTimeInterval(120))
        XCTAssertTrue(detail.contains("Last synced"), detail)
        XCTAssertTrue(detail.contains("2 minutes"), detail)
    }

    func testErrorDescriptions() {
        XCTAssertEqual(SyncMonitor.describe(CKError(.quotaExceeded)), "Your iCloud storage is full.")
        XCTAssertEqual(SyncMonitor.describe(CKError(.networkUnavailable)), "No network connection.")
        XCTAssertEqual(SyncMonitor.describe(CKError(.notAuthenticated)), "This device isn't signed in to iCloud.")
        XCTAssertTrue(SyncMonitor.describe(NSError(domain: "x", code: 1)).hasPrefix("Sync could not complete"))
    }

    // MARK: - Notices

    func testWatchImportText() throws {
        let schema = Schema(versionedSchema: TreesSchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        func tree(_ species: String) -> Tree {
            let tree = Tree(latitude: 1, longitude: 2, horizontalAccuracy: 3, species: species)
            container.mainContext.insert(tree)
            return tree
        }

        XCTAssertNil(NoticeCenter.watchImportText(for: []))
        XCTAssertEqual(NoticeCenter.watchImportText(for: [tree("Apple")]), "Apple received from Apple Watch")
        XCTAssertEqual(NoticeCenter.watchImportText(for: [tree("")]), "Tree received from Apple Watch")
        XCTAssertEqual(NoticeCenter.watchImportText(for: [tree("Apple"), tree("Pear")]), "2 trees received from Apple Watch")
    }

    func testNoticeDisappearsAfterItsDuration() async throws {
        let center = NoticeCenter(displayDuration: .milliseconds(30))
        center.show("Hello", systemImage: "applewatch")
        XCTAssertEqual(center.current?.text, "Hello")

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(center.current)
    }

    func testNewNoticeReplacesTheCurrentOneAndDismissClears() {
        let center = NoticeCenter(displayDuration: .seconds(60))
        center.show("First", systemImage: "applewatch")
        center.show("Second", systemImage: "applewatch")
        XCTAssertEqual(center.current?.text, "Second")

        center.dismiss()
        XCTAssertNil(center.current)
    }
}
