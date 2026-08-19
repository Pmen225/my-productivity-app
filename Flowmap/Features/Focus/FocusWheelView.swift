import SwiftUI

/// One block of the carousel — an arc-shaped slice of the ring, cut between an
/// inner and an outer radius about a fixed centre.
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

/// Draws a ruler numeral as characters on the local arc. A whole Text view can
/// only rotate as a rigid rectangle; individual characters give the number the
/// same curved baseline as the dial itself.
private struct CurvedRulerLabel: View {
    let text: String
    let centre: CGPoint
    let radius: CGFloat
    let angle: Double
    let fontSize: CGFloat
    let colour: Color

    var body: some View {
        let characters = Array(text)
        let readableCharacters = FocusWheelGeometry.carouselRulerLabelReversesCharacters(angle: angle)
            ? Array(characters.reversed())
            : characters
        let angles = FocusWheelGeometry.curvedRulerCharacterAngles(
            textLength: characters.count,
            centreAngle: angle,
            radius: radius,
            characterSpacing: FocusWheelGeometry.curvedRulerCharacterSpacing(fontSize: fontSize)
        )

        ZStack {
            ForEach(Array(zip(readableCharacters, angles).enumerated()), id: \.offset) { _, pair in
                let character = pair.0
                let characterAngle = pair.1
                Text(String(character))
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(colour)
                    // Rotate BEFORE positioning. `.position` grows the view to
                    // fill its parent, so a rotation applied after it turns
                    // that whole dial-sized frame about the dial's centre and
                    // carries the character to a completely different angle —
                    // which is how every endpoint numeral ended up piled at the
                    // bottom of the ring instead of at its own tick.
                    .rotationEffect(.degrees(FocusWheelGeometry.curvedRulerCharacterRotation(
                        characterAngle: characterAngle,
                        labelCentreAngle: angle
                    )))
                    .position(FocusWheelGeometry.point(centre: centre, radius: radius, angle: characterAngle))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The fixed pointer beneath the wheel, shared by the carousel and the
/// overview ring — kept in one place so a future tweak to its shape or offset
/// can't drift between the two the way a duplicated angle once did.
@MainActor
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
    /// Minutes since midnight this item starts. Carried for the clock-time
    /// placement the deleted bowl used; the carousel lays blocks out by
    /// duration, so nothing reads it today.
    let startMinutes: Double
}

/// The focus dial: one canonical circular carousel at every zoom level.
///
/// The active block starts under the fixed pointer, the next block is on the
/// right, and the annulus turns clockwise as the active block's elapsed
/// fraction advances. Zoom changes how many blocks get slices; it never turns
/// the dial into a partial arc.
struct FocusWheelView: View {
    @Environment(\.colorScheme) private var scheme
    /// The ruler's numerals follow the reader's text size like the rest of the
    /// app, from the same footnote-scale base the design draws them at.
    @ScaledMetric(relativeTo: .caption2) private var rulerNumeralSize: CGFloat = 10

    let items: [WheelItem]
    /// 0...1 through the active task. Reserved for a future progress mark;
    /// the dial itself reads duration from the ruler, not a filled arc.
    let progress: Double
    /// Identity of the active task, so wedge fills can cross-fade when it changes.
    let activeID: UUID?
    /// Minutes since midnight right now — the same clock every segment is
    /// placed against. `FocusScreen` ticks this forward once a second.
    let nowMinutes: Double
    /// Where the dial sits on `FocusWheelGeometry`'s continuous zoom axis: an
    /// integer while settled on one of the four views, fractional while a pinch
    /// is still in progress.
    let zoom: Double
    /// Degrees of time-travel preview, already clamped to the queue by
    /// `FocusWheelGeometry.clampDragPreview`. It is added to every span and to
    /// nothing else, so peeking ahead cannot alter what the consumption and the
    /// ruler are saying about the running task.
    var previewOffset: Double = 0
    /// Under Reduce Motion the ring remains stationary and this queued index
    /// crossfades through the fixed centre readout instead.
    var reducedMotionPreviewIndex: Int?
    /// Close-up magnification about the pointer, `1...8`. At `1` the whole
    /// circle is drawn exactly as before; above it the ring is enlarged around
    /// the pointer and its far side leaves the screen, which is the founder's
    /// "when zoomed in I don't want to see the entire wheel".
    var magnification: Double = 1
    /// The re-forming style's live swell, `0.88...1.18`. Rendering only — it is
    /// applied as a `scaleEffect` and no geometry reads it, so a hit target or
    /// an angle can never disagree with what is drawn.
    var reformScale: Double = 1

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
        let diameter = FocusWheelGeometry.carouselDiameter(in: size)
        let outerRadius = diameter / 2
        let thickness = FocusWheelGeometry.ringThickness(for: diameter)
        let innerRadius = outerRadius - thickness
        // Lift the dial slightly so its lower edge remains clear of the
        // checklist card while the circular control keeps its full diameter.
        let centre = FocusWheelGeometry.carouselCentre(in: size)
        // How much of the ring the close-up leaves on screen. At 1× this is the
        // whole turn, so every label is placed exactly where it always was.
        let window = FocusWheelGeometry.magnifyVisibleWindow(
            radius: outerRadius,
            factor: magnification,
            viewport: size
        )
        let durations = items.map(\.minutes)
        // A scheduled task is not elapsed until the focus session starts.
        // Using wall-clock time here rotated an idle demo ring by a full slice
        // before the user had pressed play.
        let elapsed = min(1, max(0, progress))
        // The ring no longer spins as a whole: elapsed time is CONSUMED at the
        // pointer inside `carouselSpans`, which walks every block clockwise on
        // its own. The only rotation left is the time-travel preview, so this
        // is a drag offset and nothing else.
        let rotation = previewOffset
        // Every zoom level is one vector of slices from the geometry, settled
        // or mid-pinch. A block whose slice has not yet grown past its own
        // separator gap is not drawn at all — the gap would invert its arc and
        // paint most of the ring.
        // One elapsed fraction drives both the consumption and the entering
        // block's ramp, so the two halves of the handover cannot disagree.
        let spans = FocusWheelGeometry.carouselSpans(
            zoom: zoom,
            durations: durations,
            rotation: rotation,
            elapsed: elapsed
        )
        let gap = FocusWheelGeometry.carouselGap(zoom: zoom, durations: durations, elapsed: elapsed)
        // `All` has no hidden block to ramp in, so consumption opens a quiet
        // arc behind the pointer. Drawn as the sunken track rather than as a
        // task, because at day scale that time is simply spent.
        let freeSpan = FocusWheelGeometry.carouselFreeSpan(
            zoom: zoom,
            durations: durations,
            rotation: rotation,
            elapsed: elapsed
        )
        // An empty queue still draws a scale, so the ruler falls back to a
        // nominal block rather than vanishing the moment the day is planned out.
        let rulerDurations = durations.isEmpty ? [30] : durations
        let rulerActiveSpan = FocusWheelGeometry.carouselSpans(
            zoom: zoom,
            durations: rulerDurations,
            rotation: rotation,
            elapsed: elapsed
        ).first ?? (start: FocusWheelGeometry.bottomAngle, end: FocusWheelGeometry.bottomAngle)
        let rulerSettledWidth = FocusWheelGeometry.carouselWidths(
            zoom: zoom,
            durations: rulerDurations,
            elapsed: elapsed
        ).first ?? 0
        let rulerTotalMinutes = max(1, items.first?.minutes ?? 30)
        let plan = rulerPlan(
            innerRadius: innerRadius,
            thickness: thickness,
            activeSpan: rulerActiveSpan,
            settledWidth: rulerSettledWidth,
            elapsed: elapsed,
            totalMinutes: rulerTotalMinutes,
            window: window
        )
        // Everything textual is drawn OUTSIDE the scaled group, on the wheel
        // the close-up actually shows: same circle, this centre, radii times
        // the factor. Inside the group a label is rasterised at rest size and
        // ballooned by the scale — off its wedge, over the hub, and blurry.
        let magnifiedCentre = FocusWheelGeometry.magnifiedDialCentre(in: size, factor: magnification)
        let magnifiedMidRadius = FocusWheelGeometry.magnifiedRadius(
            outerRadius - thickness / 2,
            factor: magnification
        )
        // The neutral base is only an edge separator. A broad stroke here
        // reads as a second ring behind the coloured wedges and makes the
        // wheel look heavy, so keep it aligned with every wedge outline.
        let rimStroke: CGFloat = 0.5

        return ZStack {
            zoomed(in: size) {
                ZStack {
                    Circle()
                        .stroke(FlowTheme.surfaceSunken(scheme), lineWidth: rimStroke)
                        .frame(width: diameter, height: diameter)
                        .position(centre)
                        .overlay {
                            Circle()
                                .stroke(FlowTheme.separator(scheme), lineWidth: 0.5)
                                .frame(width: diameter, height: diameter)
                                .position(centre)
                        }

                    if let freeSpan, FocusWheelGeometry.carouselWedgeIsDrawn(width: freeSpan.end - freeSpan.start, gap: gap) {
                        let free = WheelWedgeShape(
                            startAngle: freeSpan.start + gap,
                            endAngle: freeSpan.end - gap,
                            thickness: thickness,
                            radius: outerRadius,
                            centre: centre
                        )
                        free
                            .fill(FlowTheme.surfaceSunken(scheme))
                            .overlay(free.stroke(FlowTheme.separator(scheme), lineWidth: 0.5))
                            .accessibilityHidden(true)
                    }

                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let span = index < spans.count ? spans[index] : (start: 0.0, end: 0.0)

                        if FocusWheelGeometry.carouselWedgeIsDrawn(width: span.end - span.start, gap: gap) {
                            let wedge = WheelWedgeShape(
                                startAngle: span.start + gap,
                                endAngle: span.end - gap,
                                thickness: thickness,
                                radius: outerRadius,
                                centre: centre
                            )

                            wedge
                                // The active wedge is the card surface, not a flood of the
                                // task's colour — colour stays alive only as the icon tint
                                // and on the still-soft neighbours (Task 56: "still ugly").
                                .fill(item.isActive ? FlowTheme.surface(scheme) : item.colour.soft)
                                .overlay(wedge.stroke(FlowTheme.separator(scheme), lineWidth: 0.5))
                        }
                    }
                }
            }

            // Wedge titles, the FREE caption and the whole ruler — ticks and
            // numerals — are drawn out here at their own native stroke and
            // type size, positioned on the magnified circle. The active item's
            // title is the `activeTitle` sibling below — it must stay on
            // screen at every close-up factor, the same reason the pointer
            // sits outside the scaled group too.
            ZStack {
                if let freeSpan,
                   FocusWheelGeometry.carouselWedgeIsDrawn(width: freeSpan.end - freeSpan.start, gap: gap),
                   // Clip to what's on screen before taking the midpoint —
                   // the same rule the neighbour labels follow — then skip
                   // a clipped sliver too narrow to hold the caption at all.
                   let freeLabelAngle = FocusWheelGeometry.clippedSpanMidAngle(
                       start: freeSpan.start,
                       end: freeSpan.end,
                       window: window
                   ),
                   let freeVisible = FocusWheelGeometry.clippedSpanVisibleWidth(
                       start: freeSpan.start,
                       end: freeSpan.end,
                       window: window
                   ),
                   freeVisible >= FocusWheelGeometry.minimumFreeLabelSpanDegrees(factor: magnification) {
                    freeLabel(
                        angle: freeLabelAngle,
                        centre: magnifiedCentre,
                        radius: magnifiedMidRadius
                    )
                }

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let span = index < spans.count ? spans[index] : (start: 0.0, end: 0.0)

                    // Clip the wedge to what is on screen BEFORE taking its
                    // middle: a block with only a sliver showing has its raw
                    // midpoint most of a turn away, and the label would be
                    // drawn off screen while the wedge itself is visible.
                    if FocusWheelGeometry.carouselWedgeIsDrawn(width: span.end - span.start, gap: gap),
                       !item.isActive,
                       let labelAngle = FocusWheelGeometry.clippedSpanMidAngle(
                           start: span.start,
                           end: span.end,
                           window: window
                       ),
                       let visibleDegrees = FocusWheelGeometry.clippedSpanVisibleWidth(
                           start: span.start,
                           end: span.end,
                           window: window
                       ) {
                        carouselLabel(
                            item: item,
                            visibleDegrees: visibleDegrees,
                            labelAngle: labelAngle,
                            centre: magnifiedCentre,
                            radius: magnifiedMidRadius,
                            thickness: thickness,
                            viewportWidth: size.width
                        )
                    }
                }

                carouselRulerMarks(
                    magnifiedCentre: magnifiedCentre,
                    plan: plan,
                    activeSpan: rulerActiveSpan,
                    gap: gap,
                    window: window
                )
            }
            .frame(width: size.width, height: size.height)
            .clipped()

            wheelPointer(centre: centre, radius: outerRadius)
            // Like the pointer, the active title marks state the founder must
            // always be able to read — which task is running, how long is left
            // — rather than a point on the ring, so it is a sibling of the
            // magnified group, not a child of it. Left inside `zoomed(in:)` it
            // scaled and slid off screen at any close-up past ~1.5×.
            if let centreItem = reducedMotionCentreItem {
                activeTitle(
                    item: centreItem.item,
                    centre: centre,
                    elapsed: centreItem.isPreview ? 0 : elapsed,
                    isPreview: centreItem.isPreview
                )
                .id(centreItem.item.id)
                .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(.linear(duration: 1), value: progress)
        .animation(.easeInOut(duration: 0.35), value: activeID)
        .animation(FlowMotion.fade, value: reducedMotionPreviewIndex)
    }

    /// Reduce Motion previews the same queue item without rotating the ring.
    /// Keeping the readout in one place avoids introducing a second layout.
    private var reducedMotionCentreItem: (item: WheelItem, isPreview: Bool)? {
        if let index = reducedMotionPreviewIndex, items.indices.contains(index) {
            return (items[index], index != 0)
        }
        guard let active = items.first(where: \.isActive) else { return nil }
        return (active, false)
    }

    /// Applies whichever zoom style is live. The pointer is deliberately left
    /// outside: it marks *now* at a fixed place on the screen, so it must not
    /// swell with the ring or drift with the close-up.
    @ViewBuilder
    private func zoomed<Content: View>(
        in size: CGSize,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if magnification > 1 {
            let anchor = FocusWheelGeometry.magnifyAnchorUnit(in: size)
            content()
                .scaleEffect(magnification, anchor: UnitPoint(x: anchor.x, y: anchor.y))
                // The magnified ring runs far past the dial's own box, so
                // without this it would be drawn over the title above it and
                // the checklist card below.
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            content().scaleEffect(reformScale)
        }
    }

    /// The active task's title and its live countdown, fixed above the centre
    /// control at a constant screen position — never a child of `zoomed(in:)`,
    /// for the same reason the pointer is not: this is *state*, not a point on
    /// the ring, and the founder's cognitive profile requires it stay readable
    /// at every close-up factor.
    ///
    /// The chip shows minutes REMAINING, not the block's static duration — the
    /// duration doesn't change as the task runs and so cannot be the thing the
    /// hub is restating.
    private func activeTitle(
        item: WheelItem,
        centre: CGPoint,
        elapsed: Double,
        isPreview: Bool
    ) -> some View {
        let position = FocusWheelGeometry.carouselActiveTitleCentre(dialCentre: centre)
        let remaining = FocusWheelGeometry.carouselActiveRemainingMinutes(totalMinutes: item.minutes, elapsed: elapsed)
        return HStack(spacing: FlowSpacing.xs) {
            // The icon is the one place task colour survives on the active
            // wedge — everything else on the card surface reads as ink.
            Image(systemName: item.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.colour.onSoft)
                .accessibilityHidden(true)
            Text(item.title)
                .font(FlowFont.wheelSegment)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(DurationFormatter.compact(minutes: remaining))
                .font(FlowFont.durationChip)
                // The compact chip sits beside the active title in a fixed
                // 136pt readout. At accessibility-XXXL Dynamic Type the
                // token remains large enough to wrap unless it is explicitly
                // kept to one line; wrapping turned `30M` into a two-line
                // block that collided with the centre play control.
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .opacity(0.85)
        }
        .foregroundStyle(FlowTheme.primaryText(scheme))
        // Keep the centre readout inside the hole. The ruler stays on its
        // fixed lower track, so a compact one-line title cannot collide with
        // its curved numerals.
        .frame(width: 136)
        .clipped()
        .position(position)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(isPreview ? "Preview" : "Now"): \(item.title), "
                + "\(DurationFormatter.spoken(minutes: remaining))\(isPreview ? "" : " remaining")"
        )
    }

    /// A neighbour wedge's title, drawn outside the scaled group: `centre` and
    /// `radius` describe the MAGNIFIED circle, and `visibleDegrees` is the
    /// clipped on-screen span, so the label's room grows with the close-up
    /// while the glyphs stay native-size and crisp.
    private func carouselLabel(
        item: WheelItem,
        visibleDegrees: Double,
        labelAngle: Double,
        centre: CGPoint,
        radius: CGFloat,
        thickness: CGFloat,
        viewportWidth: CGFloat
    ) -> some View {
        let midAngle = labelAngle
        let label = FocusWheelGeometry.neighbourLabel(
            spanDegrees: visibleDegrees,
            midRadius: radius,
            thickness: thickness
        )
        let position = FocusWheelGeometry.edgeSafeLabelPosition(
            FocusWheelGeometry.point(centre: centre, radius: radius, angle: midAngle),
            labelWidth: label.width,
            viewportWidth: viewportWidth,
            edgeInset: FlowSpacing.s
        )

        return HStack(spacing: FlowSpacing.xs) {
            // The task icon belongs to the task block itself. Keep it in the
            // label, while the explicit combined label remains the VoiceOver
            // source.
            Image(systemName: item.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.colour.onSoft)
                .accessibilityHidden(true)
            Text(item.title)
                .font(label.isTight ? FlowFont.wheelSegmentCompact : FlowFont.wheelSegment)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        // The title takes the wedge's own on-colour, not a fixed ink. A single
        // quiet ink worked while every wedge was a 20% pastel over cream; now
        // that each fill carries its own lightness, one ink cannot clear
        // contrast on both the yellow and the crimson.
        .foregroundStyle(item.colour.onSoft)
        .frame(width: label.width)
        .clipped()
        // Keep words screen-upright while their position follows the wheel.
        // The former 180° readability flip was the visible discontinuity the
        // founder described as the labels "going back" on release.
        .position(position)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next: \(item.title), \(DurationFormatter.spoken(minutes: item.minutes))")
    }

    /// The free span's caption. Letterspaced and quiet by design — unlike a
    /// task neighbour it carries no icon and no colour of its own, since free
    /// time is the absence of a task rather than one more block to compare.
    private func freeLabel(angle: Double, centre: CGPoint, radius: CGFloat) -> some View {
        let position = FocusWheelGeometry.point(centre: centre, radius: radius, angle: angle)
        return Text("FREE")
            .font(FlowFont.wheelSegmentCompact)
            .fontWeight(.heavy)
            .tracking(2.5)
            .foregroundStyle(FlowTheme.tertiaryText(scheme))
            .position(position)
            .accessibilityHidden(true)
    }

    /// The ruler's shared derived values, computed once so the ticks (drawn
    /// inside the scaled group) and the numerals (drawn outside it, at native
    /// size) can never disagree about cadence, pitch, or where zero sits.
    private struct RulerPlan {
        let step: Int
        let labelStep: Int
        let radii: FocusWheelGeometry.RulerRadii
        let fontSize: CGFloat
        let tape: (start: Double, end: Double)
        let topTick: Int
        let totalMinutes: Int
    }

    private func rulerPlan(
        innerRadius: CGFloat,
        thickness: CGFloat,
        activeSpan: (start: Double, end: Double),
        settledWidth: Double,
        elapsed: Double,
        totalMinutes: Int,
        window: (start: Double, end: Double)
    ) -> RulerPlan {
        let radii = FocusWheelGeometry.carouselRulerRadii(innerRadius: innerRadius, thickness: thickness)
        // The scale grows with the reader's text size, but only so far: past
        // this the numerals stop fitting the band they are measuring, and an
        // unreadable ruler drawn over its own ticks helps nobody.
        let fontSize = min(13, rulerNumeralSize)
        // Cadence is decided on the numerals' own arc, so it has to know the
        // radius they sit on and the size they are drawn at, not just the
        // wedge's angle. It is measured against the task's SETTLED width, so a
        // task does not re-space its own numbers as it is consumed.
        // Under the close-up the numerals sit on an arc that has grown with the
        // magnification, so the cadence is measured on the EFFECTIVE radius —
        // otherwise they stay as sparse at 8× as they were at 1× and the
        // detail the founder zoomed in for never arrives. The close-up's own
        // visible window is what can starve the ruler of any numeral at all
        // at deep magnification — see `carouselRulerLabelStep`.
        let labelStep = FocusWheelGeometry.carouselRulerLabelStep(
            totalMinutes: totalMinutes,
            spanDegrees: settledWidth,
            numeralRadius: FocusWheelGeometry.magnifiedRadius(radii.numeral, factor: magnification),
            fontSize: fontSize,
            visibleWindowDegrees: window.end - window.start
        )
        return RulerPlan(
            step: FocusWheelGeometry.carouselRulerTickStep(totalMinutes: totalMinutes),
            labelStep: labelStep,
            radii: radii,
            fontSize: fontSize,
            // The tape is pinned to the task, not to the screen, so marks keep
            // a constant pitch and slide into the pointer as they are used up.
            tape: FocusWheelGeometry.carouselRulerTapeSpan(
                activeSpan: activeSpan,
                settledWidth: settledWidth
            ),
            topTick: FocusWheelGeometry.carouselRulerTopTick(
                totalMinutes: totalMinutes,
                elapsed: elapsed
            ),
            totalMinutes: totalMinutes
        )
    }

    /// The whole ruler — ticks and numerals — at native stroke and type size
    /// on the magnified circle. Inside the scaled group the tick strokes grew
    /// with the factor (a 0.8pt minute line became a ~5pt slab at 6×) and the
    /// scale read as decoration; out here the marks keep their clock-face
    /// positions and lengths but stay hairline-crisp, so at a deep close-up
    /// the minutes can actually be counted. `CurvedRulerLabel`'s character
    /// spacing is decided by size over radius, and native size on the
    /// magnified radius is the same ratio the old counter-scaled glyphs
    /// aimed for — minus the raster blur.
    private func carouselRulerMarks(
        magnifiedCentre: CGPoint,
        plan: RulerPlan,
        activeSpan: (start: Double, end: Double),
        gap: Double,
        window: (start: Double, end: Double)
    ) -> some View {
        let magnifiedRadii = plan.radii.magnified(factor: magnification)
        // The wedge the ruler sits on is drawn inset by `gap` at both ends,
        // but the tape it is measured along is not — so the end marks landed
        // in the separator and on the neighbouring wedge (the 0 tick was
        // drawn across Exercise). Clip to the fill the marks belong to.
        let drawn = (start: activeSpan.start + gap, end: activeSpan.end - gap)

        return ZStack {
            ForEach(Array(stride(from: plan.topTick, through: 0, by: -plan.step)), id: \.self) { remaining in
                let angle = FocusWheelGeometry.carouselRulerAngle(
                    minutesRemaining: remaining,
                    totalMinutes: plan.totalMinutes,
                    span: plan.tape
                )
                // A mark outside the close-up's visible window has nothing on
                // screen to sit on — the same clip-before-placing rule the
                // wedge labels already follow.
                if FocusWheelGeometry.carouselRulerTickIsVisible(angle: angle, window: window) {
                    rulerTick(
                        centre: magnifiedCentre,
                        // Clamped, not dropped: only the two end marks fall
                        // outside, and each by exactly `gap`. Dropping them
                        // cost the scale its `0`; pinning them to the wedge
                        // edge keeps the count whole and off the neighbour.
                        angle: min(max(angle, drawn.start), drawn.end),
                        tier: FocusWheelGeometry.carouselRulerTickTier(
                            minutesRemaining: remaining,
                            totalMinutes: plan.totalMinutes
                        ),
                        radii: magnifiedRadii
                    )

                    let showsLabel = remaining == plan.totalMinutes || remaining == 0 || remaining % plan.labelStep == 0
                    if showsLabel {
                        let text = "\(remaining)"
                        CurvedRulerLabel(
                            text: text,
                            centre: magnifiedCentre,
                            radius: magnifiedRadii.numeral,
                            angle: FocusWheelGeometry.carouselRulerLabelCentreAngle(
                                tickAngle: angle,
                                span: activeSpan,
                                characterCount: text.count,
                                fontSize: plan.fontSize,
                                radius: magnifiedRadii.numeral
                            ),
                            fontSize: plan.fontSize,
                            // Numerals read as quiet ink, not the task's own
                            // colour — the ruler is bronze/tan on every wedge.
                            colour: FlowTheme.tertiaryText(scheme)
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    /// One graduation. Its length carries the tier as well as its weight does,
    /// so the scale stays readable without relying on colour alone.
    ///
    /// Bronze/tan, not the task's colour — the ruler reads the same on every
    /// wedge rather than flooding with whichever task is active (Task 56).
    private func rulerTick(
        centre: CGPoint,
        angle: Double,
        tier: FocusWheelGeometry.RulerTickTier,
        radii: FocusWheelGeometry.RulerRadii
    ) -> some View {
        let from = FocusWheelGeometry.point(centre: centre, radius: radii.tickBase, angle: angle)
        let to = FocusWheelGeometry.point(centre: centre, radius: radii.tip(for: tier), angle: angle)
        let width: CGFloat
        let opacity: Double
        let tint: Color
        switch tier {
        case .minor: (width, opacity, tint) = (0.8, 0.42, FlowTheme.accent)
        case .medium: (width, opacity, tint) = (1.2, 0.7, FlowTheme.accent)
        case .major: (width, opacity, tint) = (1.8, 1, FlowTheme.accent)
        }

        return Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(tint.opacity(opacity), lineWidth: width)
    }

}

/// The `All`-mode dial: a small, fully-closed 360° ring, one wedge per
/// queued task sized to its own share of total duration
/// (`focus-wheel-spec.md` §3).
///
/// Not currently rendered — `FocusWheelView` draws `All` as the widest zoom of
/// the one carousel. Kept because the overview geometry it exercises is still
/// live (`overviewSpan` backs the carousel's `All` layout).
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
        // Same double-rim gap the carousel uses between wedges.
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
    /// dial: full duration on the left, zero on the right. It stays in the
    /// active task's own inner band, so the complete carousel remains visible
    /// without letting one task's scale cross into another task's wedge.
    private func overviewRuler(centre: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat) -> some View {
        let totalMinutes = min(180, max(1, items.first?.minutes ?? 30))
        let tickCount = FocusWheelGeometry.overviewRulerTickCount(totalMinutes: totalMinutes)
        let thickness = outerRadius - innerRadius
        let radii = FocusWheelGeometry.carouselRulerRadii(innerRadius: innerRadius, thickness: thickness)
        let activeSpan = FocusWheelGeometry.carouselRulerSpan(
            activeSpan: FocusWheelGeometry.overviewSpan(
                index: 0,
                durations: items.map(\.minutes)
            )
        )
        let colour = items.first?.colour ?? .clay
        let fontSize: CGFloat = 9
        let labelStep = FocusWheelGeometry.carouselRulerLabelStep(
            totalMinutes: totalMinutes,
            spanDegrees: activeSpan.end - activeSpan.start,
            numeralRadius: radii.numeral,
            fontSize: fontSize
        )

        return ZStack {
            ForEach(0...tickCount, id: \.self) { index in
                let remaining = totalMinutes - Int((Double(index) / Double(tickCount) * Double(totalMinutes)).rounded())
                let angle = FocusWheelGeometry.carouselRulerAngle(
                    minutesRemaining: remaining,
                    totalMinutes: totalMinutes,
                    span: activeSpan
                )
                let tier = FocusWheelGeometry.carouselRulerTickTier(
                    minutesRemaining: remaining,
                    totalMinutes: totalMinutes
                )
                let from = FocusWheelGeometry.point(centre: centre, radius: radii.tickBase, angle: angle)
                let to = FocusWheelGeometry.point(centre: centre, radius: radii.tip(for: tier), angle: angle)

                Path { path in
                    path.move(to: from)
                    path.addLine(to: to)
                }
                .stroke(
                    colour.onSoft.opacity(tier == .major ? 1 : tier == .medium ? 0.7 : 0.42),
                    lineWidth: tier == .major ? 1.4 : 0.8
                )

                let showsLabel = remaining == totalMinutes || remaining == 0 || remaining % labelStep == 0
                if showsLabel {
                    let text = "\(remaining)"
                    CurvedRulerLabel(
                        text: text,
                        centre: centre,
                        radius: radii.numeral,
                        angle: FocusWheelGeometry.carouselRulerLabelCentreAngle(
                            tickAngle: angle,
                            span: activeSpan,
                            characterCount: text.count,
                            fontSize: fontSize,
                            radius: radii.numeral
                        ),
                        fontSize: fontSize,
                        colour: colour.onSoft
                    )
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
