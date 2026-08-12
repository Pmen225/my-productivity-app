import SwiftUI

/// One block on the Today timeline: icon, task title, compact duration, an
/// optional time range, a lock indicator when the segment is locked, and a
/// carryover badge when the block continues earlier work.
///
/// Renders both Flowmap tasks and muted external calendar events — the block
/// itself decides colour and emphasis from `TimelineBlock`. At the mock's
/// density (roughly a minute a point) most blocks are short, so detail
/// degrades by the height actually available — full detail, then title-only,
/// then icon-only — rather than clipping.
struct TimelineBlockView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.flow) private var flow
    let block: TimelineBlock
    /// The block's rendered height, driving both the degrade tier and the
    /// corner radius — a block shorter than the radius must never look clipped.
    let height: CGFloat
    /// Supplied by the timeline so the active block's countdown re-renders on
    /// the same tick as the now-line, without owning a second timer.
    let now: Date

    private enum DetailTier {
        case full, titleOnly, iconOnly
    }

    private var tier: DetailTier {
        if height < 20 { return .iconOnly }
        if height < 34 { return .titleOnly }
        return .full
    }

    /// "Active" has no `SegmentState` case of its own — it is whichever
    /// segment the focus engine is actually running right now.
    private var isActive: Bool {
        guard let segment = block.segment else { return false }
        return flow?.focusEngine.activeSession?.segment?.id == segment.id
    }

    private var isDone: Bool {
        block.segment?.state == .completed
    }

    private var tint: Color {
        guard let token = block.colourToken else { return FlowTheme.externalEvent(scheme) }
        return isActive ? token.softStrong : token.soft
    }

    private var foreground: Color {
        block.colourToken?.onSoft ?? FlowTheme.secondaryText(scheme)
    }

    private var cornerRadius: CGFloat { min(FlowRadius.small, height / 2) }

    /// Screen readers get the full picture regardless of visual tier — a
    /// block that degrades to an icon must not degrade its accessibility too.
    private var accessibilityFullLabel: String {
        var parts = [block.title]
        if block.isLocked { parts.append("locked") }
        if let badge = block.badgeText { parts.append(badge) }
        parts.append(DurationFormatter.timeRange(from: block.start, to: block.end))
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Group {
            if tier == .iconOnly {
                // The mock keeps text in even the thinnest block: one compact
                // "Break · 15M" line, never an icon standing in for a title.
                Text("\(block.title) · \(DurationFormatter.compact(minutes: block.minutes))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                detailContent
            }
        }
        .padding(.horizontal, FlowSpacing.s)
        .padding(.vertical, tier == .iconOnly ? 2 : FlowSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(tint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(blockBorder, lineWidth: 1)
        )
        .opacity(block.isExternal ? 0.85 : (isDone ? 0.55 : 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityFullLabel)
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: FlowSpacing.xs) {
                Image(systemName: block.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(foreground)
                    .accessibilityHidden(true)

                Text(block.title)
                    .font(FlowFont.caption.weight(.semibold))
                    .foregroundStyle(foreground)
                    .lineLimit(1)

                if block.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(foreground.opacity(0.72))
                }

                if isActive {
                    countdownChip
                }

                Spacer(minLength: FlowSpacing.xs)
                trailingMeta
            }

            if tier == .full, let badge = block.badgeText {
                Text(badge)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(foreground.opacity(0.72))
                    .lineLimit(1)
            }
        }
    }

    /// The mock's right edge: external events carry a small "CAL" tag, Flowmap
    /// blocks read "9:35 · 30M" in muted text — no chip pill on the timeline.
    @ViewBuilder
    private var trailingMeta: some View {
        if block.isExternal {
            Text("CAL")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .kerning(0.8)
                .foregroundStyle(foreground.opacity(0.68))
        } else {
            Text(
                "\(DurationFormatter.time(block.start)) · \(DurationFormatter.compact(minutes: block.minutes))"
            )
            .font(.system(size: 11, design: .rounded).monospacedDigit())
            .foregroundStyle(foreground.opacity(0.72))
            .lineLimit(1)
        }
    }

    /// The running block's live countdown — the mock's white capsule with
    /// deep-clay digits, ticking on the timeline's own `now`.
    private var countdownChip: some View {
        Text(DurationFormatter.countdown(seconds: max(0, block.end.timeIntervalSince(now))))
            .font(.system(size: 10, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(FlowTheme.accentDeep)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(FlowTheme.raisedHighlight(scheme)))
    }

    private var blockBorder: Color {
        if block.isExternal { return FlowTheme.separator(scheme) }
        guard let token = block.colourToken else { return .clear }
        return token.base.opacity(isActive ? 0.34 : 0.18)
    }
}
