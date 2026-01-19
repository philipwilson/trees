import Foundation
import CoreLocation

/// Location manager optimized for watchOS
/// Uses single-shot location requests for battery efficiency
@Observable
final class WatchLocationManager: NSObject {
    private let manager = CLLocationManager()

    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var locationError: Error?
    var isRequestingLocation = false

    var hasAcceptableAccuracy: Bool {
        guard let location = currentLocation else { return false }
        return location.horizontalAccuracy > 0 && location.horizontalAccuracy < 25
    }

    var accuracyDescription: String {
        guard let location = currentLocation else { return "—" }
        return String(format: "%.0fm", location.horizontalAccuracy)
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        locationError = nil
        isRequestingLocation = true
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        isRequestingLocation = false
        manager.stopUpdatingLocation()
    }

    func requestSingleLocation() {
        locationError = nil
        isRequestingLocation = true
        manager.requestLocation()
    }
}

extension WatchLocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationError = error
        isRequestingLocation = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}
