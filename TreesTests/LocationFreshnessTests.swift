import XCTest
import CoreLocation
@testable import Trees

@MainActor
final class LocationFreshnessTests: XCTestCase {

    private func location(accuracy: Double, age: TimeInterval) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12),
            altitude: 30,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5,
            timestamp: Date(timeIntervalSinceNow: -age)
        )
    }

    func testFreshFixIsAccepted() {
        let manager = LocationManager()
        manager.locationManager(CLLocationManager(), didUpdateLocations: [location(accuracy: 5, age: 1)])
        XCTAssertNotNil(manager.currentLocation)
    }

    func testStaleCachedFixIsRejected() {
        // Core Location replays the last known fix when updates start; it can be
        // minutes old and from a different place. It must not become currentLocation.
        let manager = LocationManager()
        manager.locationManager(CLLocationManager(), didUpdateLocations: [location(accuracy: 5, age: 300)])
        XCTAssertNil(manager.currentLocation)
    }

    func testInvalidAccuracyIsRejected() {
        let manager = LocationManager()
        manager.locationManager(CLLocationManager(), didUpdateLocations: [location(accuracy: -1, age: 1)])
        XCTAssertNil(manager.currentLocation)
    }

    func testStaleFixDoesNotReplaceFreshOne() {
        let manager = LocationManager()
        manager.locationManager(CLLocationManager(), didUpdateLocations: [location(accuracy: 5, age: 1)])
        let fresh = manager.currentLocation
        manager.locationManager(CLLocationManager(), didUpdateLocations: [location(accuracy: 3, age: 120)])
        XCTAssertEqual(manager.currentLocation, fresh)
    }

    func testTransientLocationUnknownErrorIsIgnored() {
        let manager = LocationManager()
        manager.startUpdatingLocation()
        manager.locationManager(CLLocationManager(), didFailWithError: CLError(.locationUnknown))
        XCTAssertNil(manager.locationError)
        XCTAssertTrue(manager.isUpdatingLocation)
        manager.stopUpdatingLocation()
    }

    func testRealErrorIsRecorded() {
        let manager = LocationManager()
        manager.startUpdatingLocation()
        manager.locationManager(CLLocationManager(), didFailWithError: CLError(.denied))
        XCTAssertNotNil(manager.locationError)
        XCTAssertFalse(manager.isUpdatingLocation)
    }

    // MARK: - Freshness at the moment of capture

    func testFreshAccurateFixIsCapturable() {
        let manager = LocationManager()
        manager.locationManager(CLLocationManager(), didUpdateLocations: [location(accuracy: 5, age: 1)])

        XCTAssertTrue(manager.hasAcceptableAccuracy)
        XCTAssertNotNil(manager.capturableLocation())
    }

    func testInaccurateFixIsNotCapturable() {
        let manager = LocationManager()
        manager.locationManager(CLLocationManager(), didUpdateLocations: [location(accuracy: 40, age: 1)])

        XCTAssertNotNil(manager.currentLocation, "still shown as the live reading")
        XCTAssertFalse(manager.hasAcceptableAccuracy)
    }

    /// A fix that was fine when it arrived must not be capturable minutes
    /// later, even if nothing has replaced or cleared it yet.
    func testFixStopsBeingCapturableAsItAges() {
        let manager = LocationManager()
        manager.locationManager(CLLocationManager(), didUpdateLocations: [location(accuracy: 5, age: 1)])

        XCTAssertNotNil(manager.capturableLocation(at: Date().addingTimeInterval(10)))
        XCTAssertNil(manager.capturableLocation(at: Date().addingTimeInterval(20)))
        XCTAssertNil(manager.capturableLocation(at: Date().addingTimeInterval(300)))
    }

    /// With no newer fix (signal lost), the live fix is dropped so the UI
    /// goes back to "acquiring" instead of offering an old position.
    func testFixIsClearedWhenNoNewerOneArrives() async throws {
        let manager = LocationManager(maximumFixAge: 0.3)
        manager.locationManager(CLLocationManager(), didUpdateLocations: [location(accuracy: 5, age: 0)])
        XCTAssertTrue(manager.hasAcceptableAccuracy)

        try await Task.sleep(for: .milliseconds(700))

        XCTAssertNil(manager.currentLocation)
        XCTAssertFalse(manager.hasAcceptableAccuracy)
    }

    func testNewerFixKeepsTheLiveReadingAlive() async throws {
        let manager = LocationManager(maximumFixAge: 0.5)
        manager.locationManager(CLLocationManager(), didUpdateLocations: [location(accuracy: 8, age: 0)])
        try await Task.sleep(for: .milliseconds(300))
        manager.locationManager(CLLocationManager(), didUpdateLocations: [location(accuracy: 4, age: 0)])
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(manager.currentLocation?.horizontalAccuracy, 4)
        XCTAssertTrue(manager.hasAcceptableAccuracy)
    }

    func testLocationFailureClearsTheFix() {
        let manager = LocationManager()
        manager.startUpdatingLocation()
        manager.locationManager(CLLocationManager(), didUpdateLocations: [location(accuracy: 5, age: 1)])
        manager.locationManager(CLLocationManager(), didFailWithError: CLError(.network))

        XCTAssertNotNil(manager.locationError)
        XCTAssertNil(manager.currentLocation)
        XCTAssertFalse(manager.hasAcceptableAccuracy)
    }

    func testTransientErrorKeepsTheFix() {
        let manager = LocationManager()
        manager.locationManager(CLLocationManager(), didUpdateLocations: [location(accuracy: 5, age: 1)])
        manager.locationManager(CLLocationManager(), didFailWithError: CLError(.locationUnknown))

        XCTAssertTrue(manager.hasAcceptableAccuracy)
    }

    func testNewFixClearsAnEarlierError() {
        let manager = LocationManager()
        manager.locationManager(CLLocationManager(), didFailWithError: CLError(.network))
        manager.locationManager(CLLocationManager(), didUpdateLocations: [location(accuracy: 5, age: 1)])

        XCTAssertNil(manager.locationError)
        XCTAssertTrue(manager.hasAcceptableAccuracy)
    }
}
