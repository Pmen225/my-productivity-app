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

/// The focus dial: one canonical circular carousel at every zoom level.
///
/// The active block starts under the fixed pointer, the next block is on the
/// right, and the annulus turns clockwise as the active block's elapsed
/// fraction advances. Zoom changes how many blocks get slices; it never turns
/// the dial into a bowl or a partial arc.
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
            carousel(in: proxy.size)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus wheel")
        .accessibilityHint("Pinch to zoom the circular carousel")
    }

    // MARK: - Circular carousel

    private func carousel(in size: CGSize) -> some View {
        // Use the available dial height so the ring reads as the primary
        // control even while the checklist card is open. The old 180pt floor
        // made a perfectly circular wheel look like a small status badge.
        let diameter = min(size.width - FlowSpacing.l, max(200, size.height - 44))
        let outerRadius = diameter / 2
        let thickness = FocusWheelGeometry.ringThickness(for: diameter)
        let innerRadius = outerRadius - thickness
        // Lift the dial slightly so its lower edge remains clear of the
        // checklist card while the circular control keeps its full diameter.
        let centre = CGPoint(x: size.width / 2, y: size.height / 2 - 16)
        let count = FocusWheelGeometry.visibleCount(for: visibility, queueCount: items.count)
        let shown = Array(items.prefix(count))
        let durations = shown.map(\.minutes)
        let elapsed = activeElapsedFraction
        let activeSweep = FocusWheelGeometry.carouselSweep(for: visibility, queueCount: max(1, items.count))
        let rotation = elapsed * activeSweep

        return ZStack {
            Circle()
                .stroke(FlowTheme.surfaceSunken(scheme), lineWidth: thickness)
                .frame(width: diameter, height: diameter)
                .position(centre)
                .overlay {
                    Circle()
                        .stroke(FlowTheme.separator(scheme), lineWidth: 1)
                        .frame(width: diameter, height: diameter)
                        .position(centre)
                }

            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                let span = FocusWheelGeometry.carouselSpan(
                    index: index,
                    visibility: visibility,
                    durations: durations,
                    rotation: rotation
                )
                let gap = FocusWheelGeometry.wedgeGap(itemCount: shown.count)
                let wedge = WheelWedgeShape(
                    startAngle: span.start + gap,
                    endAngle: span.end - gap,
                    thickness: thickness,
                    radius: outerRadius,
                    centre: centre
                )

                wedge
                    .fill(item.isActive ? item.colour.softStrong : item.colour.soft)
                    .overlay(wedge.stroke(FlowTheme.separatorStrong(scheme), lineWidth: 1))

                carouselLabel(
                    item: item,
                    span: span,
                    centre: centre,
                    radius: outerRadius - 10,
                    thickness: thickness
                )
            }

            carouselRuler(
                centre: centre,
                innerRadius: innerRadius,
                activeSpan: FocusWheelGeometry.carouselRulerSpan(
                    activeSpan: FocusWheelGeometry.carouselSpan(
                        index: 0,
                        visibility: visibility,
                        durations: durations.isEmpty ? [30] : durations,
                        rotation: rotation
                    )
                ),
                totalMinutes: max(1, items.first?.minutes ?? 30)
            )
            wheelPointer(centre: centre, radius: outerRadius)
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeOut(duration: 0.35), value: visibility)
        .animation(.linear(duration: 1), value: nowMinutes)
    }

    private var activeElapsedFraction: Double {
        guard let item = items.first, item.minutes > 0 else { return 0 }
        return min(1, max(0, (nowMinutes - item.startMinutes) / Double(item.minutes)))
    }

    private func carouselLabel(
        item: WheelItem,
        span: (start: Double, end: Double),
        centre: CGPoint,
        radius: CGFloat,
        thickness: CGFloat
    ) -> some View {
        let midAngle = (span.start + span.end) / 2
        let position = item.isActive
            ? CGPoint(x: centre.x, y: centre.y - 30)
            : FocusWheelGeometry.point(centre: centre, radius: radius, angle: midAngle)
        let rotation = item.isActive ? 0 : FocusWheelGeometry.readableRotation(atAngle: midAngle)
        let label = FocusWheelGeometry.neighbourLabel(
            spanDegrees: span.end - span.start,
            midRadius: radius,
            thickness: thickness
        )

        return HStack(spacing: FlowSpacing.xs) {
            if !item.isActive {
                Image(systemName: item.iconName)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(item.title)
                .font(item.isActive ? FlowFont.wheelSegment : (label.isTight ? FlowFont.wheelSegmentCompact : FlowFont.wheelSegment))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if item.isActive {
                Text(DurationFormatter.compact(minutes: item.minutes))
                    .font(FlowFont.durationChip)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(item.colour.onSoft)
        // Keep the centre readout inside the hole. The ruler may pass above
        // that hole on a rotated slice, so a wide one-line title would collide
        // with its curved numerals.
        .frame(width: item.isActive ? 112 : label.width)
        .clipped()
        .rotationEffect(.degrees(rotation))
        .position(position)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.isActive ? "Now: \(item.title), \(DurationFormatter.spoken(minutes: item.minutes))" : "Next: \(item.title), \(DurationFormatter.spoken(minutes: item.minutes))")
    }

    private func carouselRuler(
        centre: CGPoint,
        innerRadius: CGFloat,
        activeSpan: (start: Double, end: Double),
        totalMinutes: Int
    ) -> some View {
        let step = FocusWheelGeometry.carouselRulerTickStep(totalMinutes: totalMinutes)
        let majorStep = FocusWheelGeometry.carouselRulerMajorStep(totalMinutes: totalMinutes)
        // Keep the ruler just inside the track. Task labels live on the outer
        // band, leaving the centre hole calm enough for the play control.
        let labelRadius = max(20, innerRadius + 8)
        return ZStack {
            ForEach(Array(stride(from: totalMinutes, through: 0, by: -step)), id: \.self) { remaining in
                let angle = FocusWheelGeometry.carouselRulerAngle(
                    minutesRemaining: remaining,
                    totalMinutes: totalMinutes,
                    span: activeSpan
                )
                let isMajor = remaining == totalMinutes || remaining == 0 || remaining % majorStep == 0
                let from = FocusWheelGeometry.point(centre: centre, radius: innerRadius + 5, angle: angle)
                let to = FocusWheelGeometry.point(centre: centre, radius: innerRadius + (isMajor ? 19 : 13), angle: angle)

                Path { path in
                    path.move(to: from)
                    path.addLine(to: to)
                }
                .stroke(
                    isMajor ? FlowTheme.accent.opacity(0.82) : FlowTheme.separatorStrong(scheme),
                    lineWidth: isMajor ? 1.5 : 0.95
                )

                if isMajor {
                    Text("\(remaining)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(FlowTheme.tertiaryText(scheme))
                        .position(FocusWheelGeometry.point(centre: centre, radius: labelRadius, angle: angle))
                        .rotationEffect(.degrees(FocusWheelGeometry.carouselRulerLabelRotation(angle: angle)))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    // MARK: - Time-window bowl
    private func bowl(in size: CGSize) -> some View {
        let width = size.width
        let radius = FocusWheelGeometry.bowlTargetRadius(forWidth: width, visibility: visibility)
        let thickness = FocusWheelGeometry.bowlThickness(forWidth: width)
        let centreX = width / 2
        let pointerY = size.height - FocusWheelGeometry.pointerInset
        let centre = CGPoint(x: centreX, y: pointerY - radius)
        let window = FocusWheelGeometry.bowlVisibleWindow(radius: radius, width: width)

        return ZStack {
            dialBand(centre: centre, radius: radius, thickness: thickness, window: window)
            wedges(centreX: centreX, pointerY: pointerY, centre: centre, radius: radius, thickness: thickness, window: window)
            boundaryMarkers(centre: centre, radius: radius, thickness: thickness, window: window)
            gaps(centre: centre, radius: radius, thickness: thickness, window: window)
            ruler(centre: centre, radius: radius, window: window)
            pointer(centre: centre, radius: radius)
        }
        .animation(.easeOut(duration: 0.35), value: radius)
        // `nowMinutes` advances once per second. Animating the same geometry
        // axis linearly makes the carousel visibly turn clockwise instead of
        // jumping between one-second snapshots.
        .animation(.linear(duration: 1), value: nowMinutes)
        .frame(width: size.width, height: size.height)
    }

    /// The dial is a ring even when a time window contains no scheduled task.
    /// Keeping this quiet clay band underneath the coloured wedges is what
    /// makes the zoomed view read as a circle rather than a floating trapezoid.
    private func dialBand(
        centre: CGPoint,
        radius: CGFloat,
        thickness: CGFloat,
        window: (min: Double, max: Double)
    ) -> some View {
        BowlWedgeShape(
            startAngle: window.min,
            endAngle: window.max,
            radius: radius,
            thickness: thickness,
            centreX: centre.x,
            pointerY: centre.y + radius
        )
        .fill(FlowTheme.surfaceSunken(scheme))
        .overlay(
            BowlWedgeShape(
                startAngle: window.min,
                endAngle: window.max,
                radius: radius,
                thickness: thickness,
                centreX: centre.x,
                pointerY: centre.y + radius
            )
            .stroke(FlowTheme.separator(scheme), lineWidth: 1)
        )
        .accessibilityHidden(true)
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
                    .fill(item.isActive ? FlowTheme.surface(scheme) : item.colour.soft)
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

        return HStack(spacing: FlowSpacing.xs) {
            Image(systemName: item.iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FlowTheme.accentText(scheme))
            Text(item.title)
                .font(FlowFont.wheelSegment)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.72)
                .foregroundStyle(FlowTheme.primaryText(scheme))
        }
        .frame(maxWidth: 180)
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

    /// Small anchor dots make the task cuts legible without adding another
    /// control. They are the visual boundary markers from the reference dial,
    /// placed on the inner rim so they stay fixed to the ring at every zoom.
    private func boundaryMarkers(
        centre: CGPoint,
        radius: CGFloat,
        thickness: CGFloat,
        window: (min: Double, max: Double)
    ) -> some View {
        let markerRadius = radius - thickness
        return ForEach(items) { item in
            ForEach([item.startMinutes, item.startMinutes + Double(item.minutes)], id: \.self) { minute in
                let angle = FocusWheelGeometry.bottomAngle
                    + (nowMinutes - minute) * FocusWheelGeometry.degreesPerMinute
                if angle > window.min + 3 && angle < window.max - 3 {
                    Circle()
                        .fill(FlowTheme.background(scheme))
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .fill(item.isActive ? FlowTheme.accent : FlowTheme.tertiaryText(scheme))
                                .frame(width: 6, height: 6)
                        )
                        .position(FocusWheelGeometry.point(centre: centre, radius: markerRadius, angle: angle))
                        .accessibilityHidden(true)
                }
            }
        }
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
    private func ruler(
        centre: CGPoint,
        radius: CGFloat,
        window: (min: Double, max: Double)
    ) -> some View {
        let totalMinutes = min(180, max(1, items.first?.minutes ?? 30))
        let fine = radius > 3_000
        let majorStep = FocusWheelGeometry.bowlRulerMajorStep(radius: radius)
        let subdivisions = FocusWheelGeometry.bowlRulerSubdivisions(radius: radius)
        // `radius` is the wedge's own OUTER edge, right where the fixed
        // pointer sits — anchoring the ruler beyond it (as this used to) put
        // every tick and number past the pointer, outside the visible wedge
        // entirely. Anchoring just inside it instead, with ticks and their
        // numbers both reaching further inward (smaller radius, away from
        // the pointer) from there, keeps the whole ruler inside the active
        // segment, matching the design (`focus-wheel-spec.md` §4).
        let outer = radius - 14
        let activeStart = items.first?.startMinutes ?? nowMinutes

        return ZStack {
            ForEach(0...(totalMinutes * subdivisions), id: \.self) { index in
                let elapsed = Double(index) / Double(subdivisions)
                let angle = FocusWheelGeometry.bowlRulerAngle(
                    elapsedMinutes: elapsed,
                    activeStartMinutes: activeStart,
                    nowMinutes: nowMinutes
                )
                let visible = angle > window.min + 2 && angle < window.max - 2
                let wholeMinute = index % subdivisions == 0
                let isMajor = wholeMinute && Int(elapsed.rounded()) % majorStep == 0

                if visible && (fine || radius >= 600 || isMajor) {
                    tick(
                        angle: angle,
                        centre: centre,
                        outer: outer,
                        isMajor: isMajor,
                        wholeMinute: wholeMinute
                    )
                    if isMajor {
                        let remaining = FocusWheelGeometry.bowlRulerRemaining(
                            elapsedMinutes: elapsed,
                            totalMinutes: totalMinutes
                        )
                        let labelPoint = FocusWheelGeometry.point(
                            centre: centre,
                            radius: outer - 32,
                            angle: angle
                        )
                        Text("\(remaining)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(FlowTheme.tertiaryText(scheme))
                            .position(labelPoint)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func tick(
        angle: Double,
        centre: CGPoint,
        outer: CGFloat,
        isMajor: Bool,
        wholeMinute: Bool
    ) -> some View {
        let length: CGFloat = isMajor ? 18 : (wholeMinute ? 12 : 8)
        // Drawn inward (decreasing radius, away from the pointer) from
        // `outer`, not outward past it — the tick has to stay on the wedge.
        let from = FocusWheelGeometry.point(centre: centre, radius: outer, angle: angle)
        let to = FocusWheelGeometry.point(centre: centre, radius: outer - length, angle: angle)
        return Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(
            isMajor ? FlowTheme.accent.opacity(0.8) : FlowTheme.separatorStrong(scheme),
            lineWidth: isMajor ? 1.5 : 1
        )
    }

    // MARK: - Pointer

    /// The clay marker at the very bottom of the dial, pointing up into the
    /// active wedge — fixed, since the active task always sits at the bottom.
    private func pointer(centre: CGPoint, radius: CGFloat) -> some View {
        wheelPointer(centre: centre, radius: radius - FocusWheelGeometry.pointerMarkerOffset)
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
                overviewRuler(centre: centre, outerRadius: outerRadius, innerRadius: innerRadius)
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

    // MARK: - Inward countdown ruler

    /// The zoomed-out ring keeps the same countdown language as the close
    /// dial: full duration on the left, zero on the right. It lives on the
    /// inner half of the annulus so the complete circular carousel remains
    /// visible without adding another control or a second task icon.
    private func overviewRuler(centre: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat) -> some View {
        let totalMinutes = min(180, max(1, items.first?.minutes ?? 30))
        let tickCount = FocusWheelGeometry.overviewRulerTickCount(totalMinutes: totalMinutes)
        let tickRadius = innerRadius + 3
        let labelRadius = innerRadius + 12

        return ZStack {
            ForEach(0...tickCount, id: \.self) { index in
                let remaining = totalMinutes - Int((Double(index) / Double(tickCount) * Double(totalMinutes)).rounded())
                let angle = FocusWheelGeometry.overviewRulerAngle(
                    minutesRemaining: remaining,
                    totalMinutes: totalMinutes
                )
                let isMajor = index == 0 || index == tickCount / 2 || index == tickCount
                let from = FocusWheelGeometry.point(centre: centre, radius: tickRadius, angle: angle)
                let to = FocusWheelGeometry.point(
                    centre: centre,
                    radius: tickRadius + (isMajor ? 9 : 5),
                    angle: angle
                )

                Path { path in
                    path.move(to: from)
                    path.addLine(to: to)
                }
                .stroke(
                    isMajor ? FlowTheme.accent.opacity(0.78) : FlowTheme.separatorStrong(scheme),
                    lineWidth: isMajor ? 1.4 : 0.8
                )

                if isMajor {
                    Text("\(remaining)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(FlowTheme.tertiaryText(scheme))
                        .position(FocusWheelGeometry.point(centre: centre, radius: labelRadius, angle: angle))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
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
