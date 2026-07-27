import SwiftUI

/// One block on the Today timeline: icon, task title, compact duration, an
/// optional time range, a lock indicator when the segment is locked, and a
/// carryover badge when the block continues earlier work.
///
/// Renders both Flowmap tasks and muted external calendar events — the block
/// itself decides colour and emphasis from `TimelineBlock`.
struct TimelineBlockView: View {
    @Environment(\.colorScheme) private var scheme
    let block: TimelineBlock
    /// Hidden on very short blocks where there is no room for it.
    let showsTimeRange: Bool

    private var tint: Color {
        block.colourToken?.soft ?? FlowTheme.externalEvent(scheme)
    }

    private var foreground: Color {
        block.colourToken?.onSoft ?? FlowTheme.secondaryText(scheme)
    }

    var body: some View {
        HStack(alignment: .top, spacing: FlowSpacing.s) {
            Image(systemName: block.iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: FlowSpacing.xs) {
                    Text(block.title)
                        .font(FlowFont.caption.weight(.semibold))
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                        .lineLimit(1)

                    if block.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                            .accessibilityLabel("Locked")
                    }
                }

                if let badge = block.badgeText {
                    Text(badge)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                        .lineLimit(1)
                }

                if showsTimeRange {
                    Text(DurationFormatter.timeRange(from: block.start, to: block.end))
                        .font(.system(size: 10, design: .rounded).monospacedDigit())
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                }
            }

            Spacer(minLength: FlowSpacing.xs)
            DurationChip(minutes: block.minutes, tint: block.colourToken)
        }
        .padding(.horizontal, FlowSpacing.s)
        .padding(.vertical, FlowSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                .fill(tint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                .strokeBorder(block.isExternal ? FlowTheme.separator(scheme) : .clear, lineWidth: 1)
        )
        .opacity(block.isExternal ? 0.85 : 1)
        .accessibilityElement(children: .combine)
    }
}
