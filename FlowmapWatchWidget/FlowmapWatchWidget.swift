import SwiftUI
import WidgetKit

/// Reads the snapshot the phone last wrote for the complication.
///
/// This duplicates `WatchSharedStore` from `FlowmapWatch/WatchStore.swift`
/// rather than depending on it: that file lives in the watch app target, not
/// this extension's target, and the two share nothing but the app group and
/// the key, so a second one-file reader here beats pulling in the whole app.
private enum ComplicationSharedStore {
    static let appGroup = "group.com.flowmap.app"
    private static let snapshotKey = "flowmap.watch.snapshot"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func read() -> WatchSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }
}

struct FlowmapComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot?
}

struct FlowmapComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> FlowmapComplicationEntry {
        FlowmapComplicationEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (FlowmapComplicationEntry) -> Void) {
        completion(FlowmapComplicationEntry(date: Date(), snapshot: ComplicationSharedStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlowmapComplicationEntry>) -> Void) {
        let snapshot = ComplicationSharedStore.read()
        let now = Date()
        var entries: [FlowmapComplicationEntry] = []

        // A minute apart until the block ends, so the glance stays fresh
        // between phone pushes without the widget ever polling for itself.
        if let snapshot, !snapshot.isPaused, let endsAt = snapshot.activeEndsAt, endsAt > now {
            var cursor = now
            while cursor < endsAt {
                entries.append(FlowmapComplicationEntry(date: cursor, snapshot: snapshot))
                cursor = cursor.addingTimeInterval(60)
            }
            entries.append(FlowmapComplicationEntry(date: endsAt, snapshot: snapshot))
        } else {
            entries.append(FlowmapComplicationEntry(date: now, snapshot: snapshot))
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct FlowmapComplicationEntryView: View {
    var entry: FlowmapComplicationProvider.Entry
    @Environment(\.widgetFamily) private var family

    private var hasActiveSession: Bool { entry.snapshot?.hasActiveSession ?? false }

    private var remainingText: String {
        guard let snapshot = entry.snapshot, hasActiveSession else { return "—" }
        return DurationFormatter.countdown(seconds: snapshot.remainingSeconds(at: entry.date))
    }

    private var title: String {
        entry.snapshot?.activeTitle ?? "No block running"
    }

    private var progress: Double {
        entry.snapshot?.progress(at: entry.date) ?? 0
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: progress) {
                Text("Flowmap")
            } currentValueLabel: {
                Text(remainingText)
                    .privacySensitive(hasActiveSession)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel(accessibilityLabel)

        case .accessoryCorner:
            Text(remainingText)
                .privacySensitive(hasActiveSession)
                .widgetLabel {
                    Gauge(value: progress) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                }
                .accessibilityLabel(accessibilityLabel)

        case .accessoryInline:
            Label {
                Text(hasActiveSession ? "\(title) · \(remainingText)" : title)
                    .privacySensitive(hasActiveSession)
            } icon: {
                Image(systemName: "timer")
            }
            .accessibilityLabel(accessibilityLabel)

        default:
            VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                Text(title)
                    .font(FlowFont.caption.weight(.semibold))
                    .privacySensitive(hasActiveSession)
                    .lineLimit(2)

                if hasActiveSession {
                    Text(remainingText)
                        .font(FlowFont.caption)
                }
            }
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private var accessibilityLabel: String {
        guard let snapshot = entry.snapshot, hasActiveSession else { return "No block running" }
        return "\(title), " + DurationFormatter.spokenCountdown(seconds: snapshot.remainingSeconds(at: entry.date))
    }
}

@main
struct FlowmapWatchWidget: Widget {
    let kind = "FlowmapWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FlowmapComplicationProvider()) { entry in
            FlowmapComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Flowmap")
        .description("Shows the block you're focused on right now.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}
