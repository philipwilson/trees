import Foundation
import CoreLocation

/// Location manager for the watch capture screen. Mirrors the iPhone's
/// LocationManager: a live fix is only offered while it is fresh.
@Observable
final class WatchLocationManager: NSObject {
    private let manager = CLLocationManager()

    /// A live fix older than this is no longer offered for capture.
    let maximumFixAge: TimeInterval
    @ObservationIgnored private var expiryTimer: Timer?

    /// The latest live fix. Cleared when it goes stale or location fails.
    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// The user has turned Precise Location off for this app. Fixes are then
    /// only accurate to kilometres and will never be good enough to capture.
    var isPreciseLocationOff = false
    var locationError: Error?
    var isRequestingLocation = false

    var hasAcceptableAccuracy: Bool {
        capturableLocation() != nil
    }

    /// The live fix, if it is recent and accurate enough to save as a tree's
    /// position right now.
    func capturableLocation(at now: Date = Date()) -> CLLocation? {
        guard let location = currentLocation,
              now.timeIntervalSince(location.timestamp) < maximumFixAge,
              location.horizontalAccuracy > 0, location.horizontalAccuracy < 25 else { return nil }
        return location
    }

    var accuracyDescription: String {
        guard let location = currentLocation else { return "—" }
        return String(format: "%.0fm", location.horizontalAccuracy)
    }

    init(maximumFixAge: TimeInterval = 15) {
        self.maximumFixAge = maximumFixAge
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus
        isPreciseLocationOff = manager.accuracyAuthorization == .reducedAccuracy
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

    /// Drops the fix once it reaches `maximumFixAge` unless a newer one has
    /// replaced it, so the UI stops offering it when the signal is lost.
    private func scheduleExpiry(of location: CLLocation) {
        expiryTimer?.invalidate()
        let remaining = max(maximumFixAge - Date().timeIntervalSince(location.timestamp), 0)
        expiryTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            guard let self, self.currentLocation === location else { return }
            self.currentLocation = nil
        }
    }
}

extension WatchLocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Core Location replays the last known fix when updates start; it can be
        // minutes old and from a different place, so reject stale or invalid fixes.
        guard let location = locations.last,
              location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < maximumFixAge else { return }
        currentLocation = location
        locationError = nil
        scheduleExpiry(of: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // locationUnknown is transient — the manager keeps trying on its own
        if (error as? CLError)?.code == .locationUnknown { return }
        locationError = error
        isRequestingLocation = false
        // Whatever fix we had is no longer being kept up to date
        expiryTimer?.invalidate()
        currentLocation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        isPreciseLocationOff = manager.accuracyAuthorization == .reducedAccuracy
    }
}
