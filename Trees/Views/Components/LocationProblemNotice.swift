import SwiftUI

/// Explains why no usable position is arriving and offers the way out:
/// permission denied, Precise Location switched off, or a location failure.
/// Shows nothing when location is working.
struct LocationProblemNotice: View {
    let locationManager: LocationManager

    private var accessDenied: Bool {
        locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted
    }

    var body: some View {
        if accessDenied {
            notice(
                "Location access is off",
                "Tree Tracker can't record a position without it.",
                systemImage: "location.slash.fill"
            ) {
                Button("Open Settings") {
                    openSettings()
                }
            }
        } else if locationManager.isPreciseLocationOff {
            notice(
                "Precise Location is off",
                "Without it your position is only known to within a few kilometres, which is never accurate enough to record a tree.",
                systemImage: "scope"
            ) {
                Button("Allow Precise Location") {
                    locationManager.requestPreciseLocation()
                }
                Button("Open Settings") {
                    openSettings()
                }
            }
        } else if locationManager.locationError != nil {
            notice(
                "Can't get your location",
                "Check that Location Services is on and you have a view of the sky, then try again.",
                systemImage: "exclamationmark.triangle.fill"
            ) {
                Button("Try Again") {
                    locationManager.startUpdatingLocation()
                }
            }
        }
    }

    private func notice<Actions: View>(
        _ title: String,
        _ message: String,
        systemImage: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                actions()
            }
            .buttonStyle(.borderless)
            .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 4)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
