import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = SimpleEntry(date: Date())
        // Static content, no need to refresh frequently
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct TreesWatchWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var widgetFamily

    var body: some View {
        switch widgetFamily {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "tree.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
        case .accessoryCorner:
            Image(systemName: "tree.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .widgetLabel {
                    Text("Capture")
                }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "tree.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text("Tree Tracker")
                        .font(.headline)
                    Text("Tap to capture")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .accessoryInline:
            Label("Capture Tree", systemImage: "tree.fill")
        @unknown default:
            Image(systemName: "tree.fill")
                .foregroundStyle(.green)
        }
    }
}

@main
struct TreesWatchWidget: Widget {
    let kind: String = "TreesWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TreesWatchWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tree Tracker")
        .description("Quick access to capture a tree location.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

#Preview(as: .accessoryCircular) {
    TreesWatchWidget()
} timeline: {
    SimpleEntry(date: Date())
}
