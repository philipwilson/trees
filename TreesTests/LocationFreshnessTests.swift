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
}
