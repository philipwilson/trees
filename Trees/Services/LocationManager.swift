import Foundation
import CoreLocation

@Observable
class LocationManager: NSObject {
    private let manager = CLLocationManager()

    /// A live fix older than this is no longer offered for capture.
    let maximumFixAge: TimeInterval
    @ObservationIgnored private var expiryTimer: Timer?

    /// The latest live fix. Cleared when it goes stale or location fails, so
    /// it never lingers as something that looks capturable.
    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// The user has turned Precise Location off for this app. Fixes are then
    /// only accurate to kilometres and will never be good enough to capture.
    var isPreciseLocationOff = false
    var locationError: Error?
    var isUpdatingLocation = false

    static let preciseLocationPurposeKey = "TreeCapture"

    var hasGoodAccuracy: Bool {
        guard let location = capturableLocation() else { return false }
        return location.horizontalAccuracy < 10
    }

    var hasAcceptableAccuracy: Bool {
        capturableLocation() != nil
    }

    /// The live fix, if it is recent and accurate enough to save as a tree's
    /// position right now. Capture actions must take their location from
    /// here rather than from `currentLocation`.
    func capturableLocation(at now: Date = Date()) -> CLLocation? {
        guard let location = currentLocation,
              now.timeIntervalSince(location.timestamp) < maximumFixAge,
              location.horizontalAccuracy > 0, location.horizontalAccuracy < 20 else { return nil }
        return location
    }

    init(maximumFixAge: TimeInterval = 15) {
        self.maximumFixAge = maximumFixAge
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        authorizationStatus = manager.authorizationStatus
        isPreciseLocationOff = manager.accuracyAuthorization == .reducedAccuracy
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Asks for precise location for this session when the user has it
    /// switched off. The system shows its own prompt.
    func requestPreciseLocation() {
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.preciseLocationPurposeKey)
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

extension LocationManager: CLLocationManagerDelegate {
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
        isUpdatingLocation = false
        // Whatever fix we had is no longer being kept up to date
        expiryTimer?.invalidate()
        currentLocation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        isPreciseLocationOff = manager.accuracyAuthorization == .reducedAccuracy
    }
}
