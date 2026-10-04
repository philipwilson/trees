import Foundation

/// A short message shown briefly over the app for things that happen without
/// the user asking, such as a tree arriving from the watch.
@MainActor
@Observable
final class NoticeCenter {
    struct Notice: Equatable, Identifiable {
        let id = UUID()
        let text: String
        let systemImage: String
    }

    private(set) var current: Notice?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    private let displayDuration: Duration

    init(displayDuration: Duration = .seconds(4)) {
        self.displayDuration = displayDuration
    }

    func show(_ text: String, systemImage: String) {
        let notice = Notice(text: text, systemImage: systemImage)
        current = notice
        dismissTask?.cancel()
        dismissTask = Task { [displayDuration] in
            try? await Task.sleep(for: displayDuration)
            if !Task.isCancelled, current == notice {
                current = nil
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }

    /// The message for trees that just arrived from the watch.
    static func watchImportText(for trees: [Tree]) -> String? {
        guard let first = trees.first else { return nil }
        if trees.count == 1 {
            return first.species.isEmpty
                ? "Tree received from Apple Watch"
                : "\(first.species) received from Apple Watch"
        }
        return "\(trees.count) trees received from Apple Watch"
    }
}
