import SwiftUI

/// A cloud icon reflecting iCloud sync; tapping it explains the current state.
/// Shows nothing if no monitor is in the environment (e.g. previews).
struct SyncStatusButton: View {
    /// Adds the status title beside the icon, for the iPad sidebar
    var showsTitle = false
    @Environment(SyncMonitor.self) private var monitor: SyncMonitor?
    @State private var showingDetail = false

    var body: some View {
        if let monitor {
            let state = monitor.state
            Button {
                showingDetail = true
            } label: {
                if showsTitle {
                    Label(state.title, systemImage: state.systemImage)
                        .font(.footnote)
                } else {
                    Image(systemName: state.systemImage)
                }
            }
            .foregroundStyle(state.needsAttention ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            .symbolEffect(.pulse, isActive: state.status == .syncing)
            .accessibilityLabel(state.title)
            .accessibilityHint("Shows iCloud sync details")
            .alert(state.title, isPresented: $showingDetail) {
                Button("OK") {}
            } message: {
                Text(state.detail())
            }
        }
    }
}
