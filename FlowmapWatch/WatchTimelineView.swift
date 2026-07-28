import SwiftUI

/// The rest of the day, list form.
///
/// The phone's Today timeline is a drag-and-drop canvas; none of that applies
/// here, so this is read-only — a coloured bar per block, its time range, and
/// the day's overall progress in the header.
struct WatchTimelineView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    private var snapshot: WatchSnapshot? { store.snapshot }

    var body: some View {
        List {
            if let snapshot {
                header(for: snapshot)
                    .listRowBackground(Color.clear)

                ForEach(snapshot.items) { item in
                    row(for: item)
                        .listRowBackground(Color.clear)
                }
            } else {
                Text("No plan yet")
                    .font(FlowFont.secondary)
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
            }
        }
    }

    private func header(for snapshot: WatchSnapshot) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
            Text(
                "\(DurationFormatter.compact(minutes: snapshot.remainingMinutes)) left of "
                    + DurationFormatter.compact(minutes: snapshot.plannedMinutes)
            )
            .font(FlowFont.caption.weight(.semibold))
            .foregroundStyle(FlowTheme.secondaryText(scheme))

            Text("\(snapshot.completedCount) of \(snapshot.totalCount) done")
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
        }
        .accessibilityElement(children: .combine)
    }

    private func row(for item: WatchSnapshot.Item) -> some View {
        let token = ColourToken.token(item.colourToken)

        return HStack(spacing: FlowSpacing.s) {
            Capsule()
                .fill(item.isActive ? token.softStrong : token.soft)
                .frame(width: FlowSpacing.xs)

            VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                Text(item.title)
                    .font(FlowFont.body)
                    .foregroundStyle(rowTextColour(for: item))
                    .strikethrough(item.isDone, color: FlowTheme.tertiaryText(scheme))
                    .lineLimit(2)

                Text(DurationFormatter.timeRange(from: item.start, to: item.end))
                    .font(FlowFont.caption.monospacedDigit())
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func rowTextColour(for item: WatchSnapshot.Item) -> Color {
        if item.isDone { return FlowTheme.tertiaryText(scheme) }
        if item.isExternal { return FlowTheme.externalEvent(scheme) }
        return FlowTheme.primaryText(scheme)
    }
}
