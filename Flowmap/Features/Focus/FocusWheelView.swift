import SwiftUI

/// One wedge of the bottom-arc dial — an arc-shaped slice of a ring cut from a
/// much larger circle than is ever fully visible.
struct WheelWedgeShape: Shape {
    var startAngle: Double
    var endAngle: Double
    let thickness: CGFloat
    let radius: CGFloat
    let centre: CGPoint

    /// Lets a wedge's own span animate when the task it represents changes.
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startAngle, endAngle) }
        set {
            startAngle = newValue.first
            endAngle = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let inner = max(0, radius - thickness)
        var path = Path()
        path.addArc(center: centre, radius: radius, startAngle: .degrees(startAngle), endAngle: .degrees(endAngle), clockwise: false)
        path.addArc(center: centre, radius: inner, startAngle: .degrees(endAngle), endAngle: .degrees(startAngle), clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// The pointer that marks "now" at the bottom of the dial.
private struct PointerTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The fixed pointer beneath the wheel, shared by the bowl and the overview
/// ring — kept in one place so a future tweak to its shape or offset can't
/// drift between the two the way a duplicated angle once did.
private func wheelPointer(centre: CGPoint, radius: CGFloat) -> some View {
    let tip = FocusWheelGeometry.point(
        centre: centre,
        radius: radius + FocusWheelGeometry.pointerMarkerOffset,
        angle: FocusWheelGeometry.bottomAngle
    )
    return PointerTriangle()
        .fill(FlowTheme.accent)
        .frame(width: 16, height: 11)
        .position(x: tip.x, y: tip.y - 5.5)
        .accessibilityHidden(true)
}

/// A task on the wheel, resolved for drawing.
struct WheelItem: Identifiable {
    let id: UUID
    let title: String
    let iconName: String
    let colour: ColourToken
    let minutes: Int
    let isActive: Bool
    /// Minutes since midnight this item starts — the clock-time axis the
    /// time-based bowl places every segment along (`focus-wheel-spec.md` §2).
    let startMinutes: Double
}

/// A wedge of the time-based bowl. Unlike `WheelWedgeShape`, its `radius` is
/// part of `animatableData` too, so a zoom-level change (`Rtarget` switching
/// between view modes) eases smoothly instead of snapping — the pointer sits
/// at a fixed screen position while the circle underneath it grows or shrinks,
/// so the centre is derived from the interpolated radius rather than passed
/// in as a separately-animating point that could drift out of step with it.
private struct BowlWedgeShape: Shape {
    var startAngle: Double
    var endAngle: Double
    var radius: CGFloat
    let thickness: CGFloat
    let centreX: CGFloat
    let pointerY: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get { AnimatablePair(AnimatablePair(startAngle, endAngle), Double(radius)) }
        set {
            startAngle = newValue.first.first
            endAngle = newValue.first.second
            radius = CGFloat(newValue.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: centreX, y: pointerY - radius)
        let inner = max(0, radius - thickness)
        var path = Path()
        path.addArc(center: centre, radius: radius, startAngle: .degrees(startAngle), endAngle: .degrees(endAngle), clockwise: false)
        path.addArc(center: centre, radius: inner, startAngle: .degrees(endAngle), endAngle: .degrees(startAngle), clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// The focus dial: a time-based bowl at 5M and a closed visibility ring at
/// 1, 2 and 3. The All overview remains its own duration-proportional ring.
///
/// Every segment is placed by clock time under a fixed pointer at the
/// bottom — as real time advances the whole ring of segments sweeps under
/// it, so a segment already under way renders left of the pointer and one
/// still to come renders right (`focus-wheel-spec.md` §2). Switching view
/// modes changes only the ring's radius (`FocusWheelGeometry.bowlTargetRadius`)
/// — the degrees-per-minute rate is constant across every view, so zooming
/// never changes a segment's size relative to another, only how much of the
/// day is visible through the fixed-width window.
struct FocusWheelView: View {
    @Environment(\.colorScheme) private var scheme

    let items: [WheelItem]
    /// 0...1 through the active task. Reserved for a future progress mark;
    /// the dial itself reads duration from the ruler, not a filled arc.
    let progress: Double
    /// Identity of the active task, so wedge fills can cross-fade when it changes.
    let activeID: UUID?
    /// Minutes since midnight right now — the same clock every segment is
    /// placed against. `FocusScreen` ticks this forward once a second.
    let nowMinutes: Double
    /// Which zoom level to draw. `.all` never reaches this view — `FocusScreen`
    /// renders `FocusWheelOverviewView` for it instead.
    let visibility: WheelVisibility

    var body: some View {
        GeometryReader { proxy in
            if FocusWheelGeometry.usesClosedRing(for: visibility) {
                closedRing(in: proxy.size)
            } else {
                bowl(in: proxy.size)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus wheel")
    }

    private func bowl(in size: CGSize) -> some View {
        let width = size.width
        let radius = FocusWheelGeometry.bowlTargetRadius(forWidth: width, visibility: visibility)
        let thickness = FocusWheelGeometry.bowlThickness(forWidth: width)
        let centreX = width / 2
        let pointerY = size.height - FocusWheelGeometry.pointerInset
        let centre = CGPoint(x: centreX, y: pointerY - radius)
        let window = FocusWheelGeometry.bowlVisibleWindow(radius: radius, width: width)
        let halfAngle = FocusWheelGeometry.bowlHalfVisibleDegrees(radius: radius, width: width)

        return ZStack {
            wedges(centreX: centreX, pointerY: pointerY, centre: centre, radius: radius, thickness: thickness, window: window)
            gaps(centre: centre, radius: radius, thickness: thickness, window: window)
            ruler(centre: centre, radius: radius, thickness: thickness, halfAngle: halfAngle)
            pointer(centre: centre, radius: radius)
        }
        .animation(.easeOut(duration: 0.35), value: radius)
        .frame(width: size.width, height: size.height)
    }

    private func closedRing(in size: CGSize) -> some View {
        let radius = FocusWheelGeometry.closedRingOuterRadius(width: size.width, height: size.height)
        let thickness = FocusWheelGeometry.closedRingThickness(width: size.width, height: size.height)
        let centre = FocusWheelGeometry.closedRingCentre(width: size.width, height: size.height)
        let visibleCount = FocusWheelGeometry.closedRingVisibleCount(for: visibility, queueCount: items.count)
        let visibleItems = Array(items.prefix(visibleCount))
        let halfAngle = FocusWheelGeometry.closedRingRulerHalfAngle(visibleCount: visibleCount)

        return ZStack {
            WheelWedgeShape(
                startAngle: 0,
                endAngle: 360,
                thickness: thickness,
                radius: radius,
                centre: centre
            )
            .fill(FlowTheme.surface(scheme))
            .overlay(
                WheelWedgeShape(
                    startAngle: 0,
                    endAngle: 360,
                    thickness: thickness,
                    radius: radius,
                    centre: centre
                )
                .stroke(FlowTheme.separator(scheme), lineWidth: 1)
            )

            closedRingWedges(
                visibleItems: visibleItems,
                visibleCount: visibleCount,
                centre: centre,
                radius: radius,
                thickness: thickness
            )

            Text("FREE")
                .font(FlowFont.eyebrow)
                .tracking(1.5)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
                .position(
                    FocusWheelGeometry.point(
                        centre: centre,
                        radius: radius - thickness / 2,
                        angle: FocusWheelGeometry.closedRingFreeLabelAngle(visibleCount: visibleCount)
                    )
                )
                .accessibilityHidden(true)

            ruler(centre: centre, radius: radius, thickness: thickness, halfAngle: halfAngle)
            pointer(centre: centre, radius: radius)
        }
        .animation(.easeOut(duration: 0.35), value: visibleCount)
        .frame(width: size.width, height: size.height)
    }

    private func closedRingWedges(
        visibleItems: [WheelItem],
        visibleCount: Int,
        centre: CGPoint,
        radius: CGFloat,
        thickness: CGFloat
    ) -> some View {
        let gap = FocusWheelGeometry.wedgeGap(itemCount: visibleItems.count)

        return ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
            let span = FocusWheelGeometry.closedRingSpan(index: index, visibleCount: visibleCount)

            ZStack {
                WheelWedgeShape(
                    startAngle: span.start + gap,
                    endAngle: span.end - gap,
                    thickness: thickness,
                    radius: radius,
                    centre: centre
                )
                .fill(item.isActive ? item.colour.softStrong : item.colour.soft)
                .overlay(
                    WheelWedgeShape(
                        startAngle: span.start + gap,
                        endAngle: span.end - gap,
                        thickness: thickness,
                        radius: radius,
                        centre: centre
                    )
                    .stroke(FlowTheme.separatorStrong(scheme), lineWidth: 1)
                )

                if item.isActive {
                    activeTitle(item: item, span: span, centre: centre, radius: radius, thickness: thickness)
                } else {
                    neighbourLabel(item: item, span: span, centre: centre, radius: radius, thickness: thickness)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                item.isActive
                    ? "Current: \(item.title), \(DurationFormatter.spoken(minutes: item.minutes))"
                    : "Next: \(item.title), \(DurationFormatter.spoken(minutes: item.minutes))"
            )
        }
    }

    // MARK: - Wedges

    private func wedges(
        centreX: CGFloat,
        pointerY: CGFloat,
        centre: CGPoint,
        radius: CGFloat,
        thickness: CGFloat,
        window: (min: Double, max: Double)
    ) -> some View {
        // Small angular gap between wedges reads as the mock's double rim
        // between segments rather than one continuous band.
        let gap = FocusWheelGeometry.wedgeGap(itemCount: items.count)

        return ForEach(items) { item in
            let span = FocusWheelGeometry.bowlSegmentSpan(start: item.startMinutes, duration: Double(item.minutes), nowMinutes: nowMinutes)

            if FocusWheelGeometry.bowlSegmentIsVisible(span: span, window: window) {
                // Every wedge shares one ring thickness (`focus-wheel-spec.md`
                // §2: "the ring is always 136px thick... regardless of view").
                // An earlier task inflated the active wedge by 1.3x with no
                // basis in the design; that's what read as an oversized slab
                // instead of the design's shallow, uniform band — removed.
                ZStack {
                    BowlWedgeShape(
                        startAngle: span.start + gap,
                        endAngle: span.end - gap,
                        radius: radius,
                        thickness: thickness,
                        centreX: centreX,
                        pointerY: pointerY
                    )
                    .fill(item.isActive ? item.colour.softStrong : item.colour.soft)
                    .overlay(
                        BowlWedgeShape(
                            startAngle: span.start + gap,
                            endAngle: span.end - gap,
                            radius: radius,
                            thickness: thickness,
                            centreX: centreX,
                            pointerY: pointerY
                        )
                        .stroke(FlowTheme.separatorStrong(scheme), lineWidth: 1)
                    )
                    .animation(.easeInOut(duration: 0.3), value: item.id)

                    if item.isActive {
                        activeTitle(item: item, span: span, centre: centre, radius: radius, thickness: thickness)
                    } else {
                        neighbourLabel(item: item, span: span, centre: centre, radius: radius, thickness: thickness)
                    }
                }
            }
        }
    }

    /// The active wedge's title, drawn horizontally rather than arc-rotated —
    /// it sits directly under the fixed pointer, so it never needs to lean
    /// the way an off-centre neighbour label does to stay readable.
    ///
    /// Positioned at the same mid-band radius every other wedge label uses
    /// (`neighbourLabel`, the `FREE` label below) — `radius` on its own is
    /// the wedge's *outer* edge, immediately next to the fixed pointer, which
    /// is why this used to render sitting on top of the pointer instead of
    /// inside the band.
    private func activeTitle(item: WheelItem, span: (start: Double, end: Double), centre: CGPoint, radius: CGFloat, thickness: CGFloat) -> some View {
        let midAngle = (span.start + span.end) / 2
        let position = FocusWheelGeometry.point(centre: centre, radius: radius - thickness / 2, angle: midAngle)

        return Text(item.title)
            .font(FlowFont.wheelSegment)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(item.colour.onSoft)
            .position(position)
            // The centre readout already announces the active task's title;
            // this on-wedge label is purely visual.
            .accessibilityHidden(true)
    }

    /// Icon, name and compact duration stacked at a neighbour wedge's outer edge.
    private func neighbourLabel(
        item: WheelItem,
        span: (start: Double, end: Double),
        centre: CGPoint,
        radius: CGFloat,
        thickness: CGFloat
    ) -> some View {
        let midRadius = radius - thickness / 2
        let midAngle = (span.start + span.end) / 2
        let position = FocusWheelGeometry.point(centre: centre, radius: midRadius, angle: midAngle)
        let rotation = FocusWheelGeometry.readableRotation(atAngle: midAngle)
        // Two size tiers, measured from the arc the label actually has
        // (`FocusWheelGeometry` owns every angle in this view).
        let label = FocusWheelGeometry.neighbourLabel(
            spanDegrees: span.end - span.start,
            midRadius: midRadius,
            thickness: thickness
        )

        return VStack(spacing: 1) {
            Image(systemName: item.iconName)
                .font(.system(size: 11, weight: .semibold))
            Text(item.title)
                .font(label.isTight ? FlowFont.wheelSegmentCompact : FlowFont.wheelSegment)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(DurationFormatter.compact(minutes: item.minutes))
                .font(FlowFont.durationChip)
                .opacity(0.85)
        }
        .foregroundStyle(item.colour.onSoft)
        .frame(maxWidth: label.width)
        .rotationEffect(.degrees(rotation))
        .position(x: position.x, y: position.y)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next: \(item.title), \(DurationFormatter.spoken(minutes: item.minutes))")
    }

    // MARK: - Gaps

    /// Unscheduled stretches of the day (`FocusWheelGeometry.bowlGaps`, scanned
    /// 08:00–21:00). No fill is drawn for a gap — the ring's own background
    /// shows through — only a `FREE` label, and only once its visible span
    /// clears 9°, so a sliver of gap at the window's edge never gets a
    /// crowded label.
    private func gaps(centre: CGPoint, radius: CGFloat, thickness: CGFloat, window: (min: Double, max: Double)) -> some View {
        let scheduled = items.map { (start: $0.startMinutes, duration: Double($0.minutes)) }
        let dayGaps = FocusWheelGeometry.bowlGaps(scheduled: scheduled)

        return ForEach(Array(dayGaps.enumerated()), id: \.offset) { _, gapItem in
            let span = FocusWheelGeometry.bowlSegmentSpan(start: gapItem.start, duration: gapItem.duration, nowMinutes: nowMinutes)

            if FocusWheelGeometry.bowlGapShowsFreeLabel(span: span, window: window) {
                let midAngle = FocusWheelGeometry.bowlGapLabelAngle(span: span, window: window)
                let position = FocusWheelGeometry.point(centre: centre, radius: radius - thickness / 2, angle: midAngle)

                // The existing eyebrow treatment (`FlowFont.eyebrow`, 1.5pt
                // tracking, `FlowTheme.tertiaryText`) rather than the design's
                // literal `#CBBFA9` — this codebase never hard-codes a colour.
                Text("FREE")
                    .font(FlowFont.eyebrow)
                    .tracking(1.5)
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
                    .position(position)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Ruler

    /// A numbered minute scale across the active task's own span: minor
    /// hairlines every minute, major ticks with a number every `majorStep`.
    private func ruler(centre: CGPoint, radius: CGFloat, thickness: CGFloat, halfAngle: Double) -> some View {
        let totalMinutes = min(180, max(1, items.first?.minutes ?? 30))
        let majorStep = totalMinutes <= 30 ? 5 : (totalMinutes <= 60 ? 10 : 15)
        // `radius` is the wedge's own OUTER edge, right where the fixed
        // pointer sits — anchoring the ruler beyond it (as this used to) put
        // every tick and number past the pointer, outside the visible wedge
        // entirely. Anchoring just inside it instead, with ticks and their
        // numbers both reaching further inward (smaller radius, away from
        // the pointer) from there, keeps the whole ruler inside the active
        // segment, matching the design (`focus-wheel-spec.md` §4).
        let outer = radius - thickness * 0.12

        return ZStack {
            ForEach(Array(stride(from: 0, through: totalMinutes, by: 1)), id: \.self) { minute in
                // Tick spacing and the major/minor rule stay keyed to minutes
                // elapsed from task start; only the printed number — and the
                // angle it maps to — reads as minutes remaining.
                let remaining = totalMinutes - minute
                let angle = FocusWheelGeometry.dialTickAngle(minutesRemaining: remaining, totalMinutes: totalMinutes, halfAngle: halfAngle)
                let isMajor = minute % majorStep == 0
                tick(angle: angle, centre: centre, outer: outer, isMajor: isMajor)

                if isMajor {
                    // Further in than the tick itself (smaller radius), so
                    // the number reads above its tick toward mid-band rather
                    // than past the wedge's outer edge.
                    let labelPoint = FocusWheelGeometry.point(centre: centre, radius: outer - 13, angle: angle)
                    Text("\(remaining)")
                        // Explicit 11pt: the smallest size the HIG allows,
                        // chosen deliberately rather than let the ruler shrink further.
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(FlowTheme.tertiaryText(scheme))
                        .position(labelPoint)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func tick(angle: Double, centre: CGPoint, outer: CGFloat, isMajor: Bool) -> some View {
        let length: CGFloat = isMajor ? 7 : 3
        // Drawn inward (decreasing radius, away from the pointer) from
        // `outer`, not outward past it — the tick has to stay on the wedge.
        let from = FocusWheelGeometry.point(centre: centre, radius: outer, angle: angle)
        let to = FocusWheelGeometry.point(centre: centre, radius: outer - length, angle: angle)
        return Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(FlowTheme.tertiaryText(scheme), lineWidth: isMajor ? 1.5 : 1)
    }

    // MARK: - Pointer

    /// The clay marker at the very bottom of the dial, pointing up into the
    /// active wedge — fixed, since the active task always sits at the bottom.
    private func pointer(centre: CGPoint, radius: CGFloat) -> some View {
        wheelPointer(centre: centre, radius: radius)
    }
}

/// The `All`-mode dial: a small, fully-closed 360° ring, one wedge per
/// queued task sized to its own share of total duration — the closed-circle
/// counterpart to the bowl, drawn only when every task is visible at once
/// (`focus-wheel-spec.md` §3).
struct FocusWheelOverviewView: View {
    @Environment(\.colorScheme) private var scheme

    let items: [WheelItem]
    /// Whether the active item has a running timer, rather than merely
    /// occupying the bottom slot — decides "Now" vs "Next" in the centre
    /// readout below.
    let isSessionActive: Bool
    /// Minutes to show in the centre: live remaining time if a session is
    /// running, otherwise the item's own planned duration — the same string
    /// `FocusScreen` already shows above the ring, reused rather than
    /// recomputed here.
    let centreCountdownText: String
    let centreCountdownAccessibilityLabel: String

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, proxy.size.height)
            let outerRadius = FocusWheelGeometry.overviewOuterRadius(width: width)
            let innerRadius = FocusWheelGeometry.overviewInnerRadius(width: width)
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                wedges(centre: centre, outerRadius: outerRadius, innerRadius: innerRadius)
                pointer(centre: centre, radius: outerRadius)
                centreReadout()
                    .position(centre)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus wheel overview")
    }

    // MARK: - Wedges

    private func wedges(centre: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat) -> some View {
        // Same double-rim gap the bowl uses between wedges.
        let gap = FocusWheelGeometry.wedgeGap(itemCount: items.count)
        let thickness = outerRadius - innerRadius
        let durations = items.map(\.minutes)
        let midRadius = (outerRadius + innerRadius) / 2

        return ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            let span = FocusWheelGeometry.overviewSpan(index: index, durations: durations)
            let showsLabel = FocusWheelGeometry.overviewShowsLabel(spanDegrees: span.end - span.start, labelRadius: midRadius)

            ZStack {
                WheelWedgeShape(
                    startAngle: span.start + gap,
                    endAngle: span.end - gap,
                    thickness: thickness,
                    radius: outerRadius,
                    centre: centre
                )
                .fill(item.isActive ? item.colour.softStrong : item.colour.soft)
                .overlay(
                    WheelWedgeShape(
                        startAngle: span.start + gap,
                        endAngle: span.end - gap,
                        thickness: thickness,
                        radius: outerRadius,
                        centre: centre
                    )
                    .stroke(FlowTheme.separatorStrong(scheme), lineWidth: 1)
                )

                if showsLabel {
                    segmentLabel(item: item, span: span, centre: centre, outerRadius: outerRadius, innerRadius: innerRadius)
                        .accessibilityHidden(true)
                }
            }
            // Carried on the wedge itself, not the label: a segment too
            // narrow to hold any label (see `overviewShowsLabel`) must still
            // be announced to VoiceOver with its title and duration.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.title), \(DurationFormatter.spoken(minutes: item.minutes))")
        }
    }

    /// Two label tiers by span width: wide segments get a title plus a
    /// duration label, narrow ones drop the title and show only the
    /// compact duration (`FocusWheelGeometry.overviewShowsTitle`) — the
    /// geometry decides the tier and the label's flip, never this view.
    /// Only called once `overviewShowsLabel` has already confirmed there's
    /// room for a label at all.
    private func segmentLabel(
        item: WheelItem,
        span: (start: Double, end: Double),
        centre: CGPoint,
        outerRadius: CGFloat,
        innerRadius: CGFloat
    ) -> some View {
        let mid = (span.start + span.end) / 2
        let midRadius = (outerRadius + innerRadius) / 2
        let rotation = FocusWheelGeometry.readableRotation(atAngle: mid)
        let position = FocusWheelGeometry.point(centre: centre, radius: midRadius, angle: mid)
        let showsTitle = FocusWheelGeometry.overviewShowsTitle(spanDegrees: span.end - span.start)

        return Group {
            if showsTitle {
                VStack(spacing: 1) {
                    Text(item.title)
                        .font(FlowFont.wheelSegment)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(DurationFormatter.compact(minutes: item.minutes))
                        .font(FlowFont.durationChip)
                        .opacity(0.85)
                }
                .frame(maxWidth: max(56, (outerRadius - innerRadius) * 1.6))
            } else {
                Text(DurationFormatter.compact(minutes: item.minutes))
                    .font(FlowFont.durationChip)
            }
        }
        .foregroundStyle(item.colour.onSoft)
        .rotationEffect(.degrees(rotation))
        .position(position)
    }

    // MARK: - Centre readout

    /// The NOW readout the design fixes inside the donut hole: an eyebrow,
    /// the active item's minutes in the same tabular style `NowStrip` and
    /// the Today NOW card use, and its title — "Now" with a live countdown
    /// while a session is actually running, else "Next" with that item's
    /// own planned duration, since the bottom slot is always occupied but
    /// isn't always timed (`focus-wheel-spec.md` §6).
    private func centreReadout() -> some View {
        Group {
            if let first = items.first {
                VStack(spacing: 2) {
                    FlowEyebrow(isSessionActive ? "Now" : "Next")
                    (
                        Text(centreCountdownText).font(FlowFont.countdownCompact)
                            + Text(" min").font(FlowFont.chromeLabel)
                    )
                    .foregroundStyle(FlowTheme.accentText(scheme))
                    Text(first.title)
                        .font(FlowFont.chromeLabel)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(isSessionActive ? "Now" : "Next"): \(first.title), \(centreCountdownAccessibilityLabel)")
            }
        }
    }

    // MARK: - Pointer

    private func pointer(centre: CGPoint, radius: CGFloat) -> some View {
        wheelPointer(centre: centre, radius: radius)
    }
}
