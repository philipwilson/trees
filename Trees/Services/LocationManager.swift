import Foundation
import CoreLocation

@Observable
class LocationManager: NSObject {
    private let manager = CLLocationManager()

    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var locationError: Error?
    var isUpdatingLocation = false

    var hasGoodAccuracy: Bool {
        guard let location = currentLocation else { return false }
        return location.horizontalAccuracy > 0 && location.horizontalAccuracy < 10
    }

    var hasAcceptableAccuracy: Bool {
        guard let location = currentLocation else { return false }
        return location.horizontalAccuracy > 0 && location.horizontalAccuracy < 20
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        locationError = nil
        isUpdatingLocation = true
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        isUpdatingLocation = false
        manager.stopUpdatingLocation()
    }

    func requestSingleLocation() {
        locationError = nil
        manager.requestLocation()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Core Location replays the last known fix when updates start; it can be
        // minutes old and from a different place, so reject stale or invalid fixes.
        guard let location = locations.last,
              location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 15 else { return }
        currentLocation = location
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // locationUnknown is transient — the manager keeps trying on its own
        if (error as? CLError)?.code == .locationUnknown { return }
        locationError = error
        isUpdatingLocation = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}
