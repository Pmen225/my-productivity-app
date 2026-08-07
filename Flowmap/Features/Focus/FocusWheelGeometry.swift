import CoreGraphics
import Foundation

/// Where each task sits on the focus wheel.
///
/// Angles are in degrees in screen space: `0°` is east, and because the screen's
/// y axis points down, **increasing angle moves clockwise**. The bottom of the
/// wheel is therefore `90°`.
///
/// Two rules drive the whole layout, and they resolve each other:
///
/// * The active task must occupy the bottom segment in every visibility mode.
/// * The wheel turns clockwise and the next task enters from the right.
///
/// So the active segment is centred on `90°` and each upcoming task is placed a
/// further `sweep` degrees *anticlockwise* from it — that is, up the right-hand
/// side. When a task ends, the wheel turns clockwise by exactly one `sweep`,
/// carrying the next task down the right side and into the bottom position.
/// Elapsing time inside a task is shown by the progress arc and the countdown
/// rather than by drifting the active task off the bottom.
public enum FocusWheelGeometry {
    /// The fixed pointer, and the centre of the active segment.
    public static let bottomAngle: Double = 90

    /// Degrees each visible task occupies.
    public static func sweep(visibleCount: Int) -> Double {
        360 / Double(max(1, visibleCount))
    }

    /// Centre angle of the task at `index`, where `0` is the active task.
    public static func centreAngle(index: Int, visibleCount: Int) -> Double {
        bottomAngle - Double(index) * sweep(visibleCount: visibleCount)
    }

    /// Angular span of the task at `index`.
    public static func span(index: Int, visibleCount: Int) -> (start: Double, end: Double) {
        let half = sweep(visibleCount: visibleCount) / 2
        let centre = centreAngle(index: index, visibleCount: visibleCount)
        return (centre - half, centre + half)
    }

    /// Point on a circle of `radius` about `centre` at `angle` degrees.
    public static func point(centre: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(
            x: centre.x + radius * CGFloat(cos(radians)),
            y: centre.y + radius * CGFloat(sin(radians))
        )
    }

    /// How much to rotate a segment's label so it reads along the arc.
    ///
    /// The active task, sitting at the bottom, comes out perfectly horizontal.
    /// Labels that would end up past a quarter turn are flipped by 180° so they
    /// read left-to-right instead of upside down on the far side of the ring.
    public static func labelRotation(index: Int, visibleCount: Int) -> Double {
        readableRotation(atAngle: centreAngle(index: index, visibleCount: visibleCount))
    }

    /// Rotation for a label sitting at `angle`, kept within a quarter turn of
    /// upright so it always reads left-to-right.
    public static func readableRotation(atAngle angle: Double) -> Double {
        var normalised = (angle - bottomAngle).truncatingRemainder(dividingBy: 360)
        if normalised > 180 { normalised -= 360 }
        if normalised < -180 { normalised += 360 }
        if normalised > 90 { return normalised - 180 }
        if normalised < -90 { return normalised + 180 }
        return normalised
    }

    /// Ring thickness for a given wheel diameter — thick enough to hold a label,
    /// thin enough that the ring reads as a track rather than a solid disc.
    public static func ringThickness(for diameter: CGFloat) -> CGFloat {
        max(52, min(72, diameter * 0.17))
    }

    /// How many tasks to draw for a visibility mode, capped by what actually exists.
    public static func visibleCount(for visibility: WheelVisibility, queueCount: Int) -> Int {
        let available = max(1, queueCount)
        guard let requested = visibility.visibleCount else { return available }
        return min(requested, available)
    }

    // MARK: - Circular carousel

    /// The close views are still the same dial at every zoom level: a true
    /// annulus, with the fixed pointer at the bottom and the next block
    /// entering from the right. Zoom changes how many blocks are allocated a
    /// slice; it never changes the fact that the track closes into a circle.
    public static func carouselSweep(for visibility: WheelVisibility, queueCount: Int) -> Double {
        let count = visibleCount(for: visibility, queueCount: queueCount)
        // A single visible block keeps a quiet free-space window so its ruler
        // has distinct left and right ends instead of collapsing into a full
        // 360° loop.
        if count == 1 && visibility != .all { return 300 }
        return 360 / Double(max(1, count))
    }

    /// The angular slice for a block after the carousel has turned clockwise
    /// by `rotation`. `index == 0` is the active block at the pointer when the
    /// task begins; positive rotation advances it past the pointer while the
    /// next block arrives from the right.
    public static func carouselSpan(
        index: Int,
        visibility: WheelVisibility,
        durations: [Int],
        rotation: Double
    ) -> (start: Double, end: Double) {
        guard durations.indices.contains(index) else { return (bottomAngle, bottomAngle) }

        if visibility == .all {
            let base = overviewSpan(index: index, durations: durations)
            return (base.start + rotation, base.end + rotation)
        }

        let sweep = carouselSweep(for: visibility, queueCount: durations.count)
        let centre = bottomAngle - Double(index) * sweep + rotation
        return (centre - sweep / 2, centre + sweep / 2)
    }

    /// Keep the detailed countdown on the fixed lower inner track. The ring
    /// may rotate, but the pointer and its ruler stay put so the scale always
    /// reads like the original dial: full duration on the left, zero on the
    /// right. A single full-ring task gets a little more breathing room; a
    /// multi-task overview stays inside the active task's proportional wedge.
    public static func carouselRulerSpan(activeSpan: (start: Double, end: Double)) -> (start: Double, end: Double) {
        let width = activeSpan.end - activeSpan.start
        // A full single-task ring still needs a quiet gap so its endpoints are
        // visible. Every narrower task keeps its own wedge: widening it would
        // draw the countdown through neighbouring tasks in All mode.
        guard width > 320 else { return activeSpan }
        let halfSpan = 150.0
        return (bottomAngle - halfSpan, bottomAngle + halfSpan)
    }

    /// Maps minutes remaining onto the active block's ruler. Full duration is
    /// always the left-hand end (the larger screen-space angle); zero is the
    /// right-hand end, so the numbers read as a countdown.
    public static func carouselRulerAngle(
        minutesRemaining: Int,
        totalMinutes: Int,
        span: (start: Double, end: Double)
    ) -> Double {
        guard totalMinutes > 0 else { return span.start }
        let fraction = min(1, max(0, Double(minutesRemaining) / Double(totalMinutes)))
        return span.start + (span.end - span.start) * fraction
    }

    /// Keep the minute scale dense at every zoom level. The ruler is a real
    /// measuring track, so even a long block keeps one tick per minute; only
    /// the numbered cadence relaxes for durations over an hour.
    public static func carouselRulerTickStep(totalMinutes: Int) -> Int {
        1
    }

    /// Number every five minutes on short blocks and every ten on long ones.
    /// Endpoints are always added by the renderer, even when they are not on
    /// this cadence.
    public static func carouselRulerMajorStep(totalMinutes: Int) -> Int {
        totalMinutes > 60 ? 10 : 5
    }

    /// Labels need a little more breathing room than their tick marks when a
    /// task occupies a narrow overview wedge. The ruler stays minute-detailed;
    /// only the printed numerals step back from 5M to 10M.
    public static func carouselRulerLabelStep(totalMinutes: Int, spanDegrees: Double) -> Int {
        max(carouselRulerMajorStep(totalMinutes: totalMinutes), spanDegrees < 80 ? 10 : 1)
    }

    /// The three tick weights of the ruler. A measuring instrument is read by
    /// tick length as much as by its numbers, so the tier is decided here
    /// rather than by a pair of booleans in the renderer.
    public enum RulerTickTier: Sendable {
        case minor
        case medium
        case major
    }

    /// Which weight the tick for `minutesRemaining` gets. Both ends of the
    /// scale are always major: they carry the two values the countdown exists
    /// to show. On a block longer than an hour the five-minute marks drop to
    /// the middle weight so the ten-minute numerals still stand out.
    public static func carouselRulerTickTier(minutesRemaining: Int, totalMinutes: Int) -> RulerTickTier {
        if minutesRemaining <= 0 || minutesRemaining >= totalMinutes { return .major }
        if minutesRemaining % carouselRulerMajorStep(totalMinutes: totalMinutes) == 0 { return .major }
        if minutesRemaining % 5 == 0 { return .medium }
        return .minor
    }

    /// Every radius the countdown ruler draws on, as one set derived from the
    /// band it lives in. `radius` on its own is the band's OUTER edge, which
    /// on this dial sits under the pointer — anchoring any part of the ruler
    /// to it has already put the whole scale off the band once.
    public struct RulerRadii: Sendable {
        /// Numerals sit inboard of their ticks, as on a tape measure.
        public let numeral: CGFloat
        public let tickBase: CGFloat
        public let minorTip: CGFloat
        public let mediumTip: CGFloat
        public let majorTip: CGFloat

        public func tip(for tier: RulerTickTier) -> CGFloat {
            switch tier {
            case .minor: minorTip
            case .medium: mediumTip
            case .major: majorTip
            }
        }
    }

    /// The ruler's own track inside the annulus `innerRadius ..< innerRadius +
    /// thickness`. Everything is a fraction of the band so the scale keeps its
    /// proportions at any dial size, and the outermost tick still clears the
    /// rim by enough that it never reads as touching the wedge's edge.
    public static func carouselRulerRadii(innerRadius: CGFloat, thickness: CGFloat) -> RulerRadii {
        RulerRadii(
            numeral: innerRadius + thickness * 0.22,
            tickBase: innerRadius + thickness * 0.40,
            minorTip: innerRadius + thickness * 0.52,
            mediumTip: innerRadius + thickness * 0.60,
            majorTip: innerRadius + thickness * 0.72
        )
    }

    /// The label's tangent, before it is made readable — 90° from the radial
    /// angle, normalised to `(-180, 180]`.
    private static func rulerTangent(atAngle angle: Double) -> Double {
        var tangent = (angle + 90).truncatingRemainder(dividingBy: 360)
        if tangent > 180 { tangent -= 360 }
        if tangent < -180 { tangent += 360 }
        return tangent
    }

    /// Rotates a numeral onto the tangent of the circular ruler while keeping
    /// it upright. At the top and bottom the text is horizontal; at the sides
    /// it turns with the ring rather than remaining a straight screen label.
    public static func carouselRulerLabelRotation(angle: Double) -> Double {
        curvedRulerCharacterRotation(characterAngle: angle, labelCentreAngle: angle)
    }

    /// Whether the readable tangent was flipped by 180°. Reversing the
    /// character order at the same time keeps multi-digit labels reading
    /// left-to-right on the lower half of the ring.
    public static func carouselRulerLabelReversesCharacters(angle: Double) -> Bool {
        let tangent = rulerTangent(atAngle: angle)
        return tangent > 90 || tangent < -90
    }

    /// Rotation for ONE character of a curved numeral: its own tangent, turned
    /// by whatever the label as a whole was turned by.
    ///
    /// Giving every character the label's single centre tangent leaves a
    /// two-digit number sitting flat across the arc, which is the thing the
    /// design explicitly rejects; deciding the flip per character instead
    /// would stand one digit on its head the moment a label straddles a
    /// cardinal point. The flip is therefore the label's, the tangent is the
    /// character's.
    public static func curvedRulerCharacterRotation(characterAngle: Double, labelCentreAngle: Double) -> Double {
        let tangent = rulerTangent(atAngle: characterAngle)
        guard carouselRulerLabelReversesCharacters(angle: labelCentreAngle) else { return tangent }
        return tangent > 0 ? tangent - 180 : tangent + 180
    }

    /// Arc distance between the centres of two adjacent ruler digits. The
    /// numerals are drawn in a rounded system font, whose digits are tabular
    /// and so share one advance — measuring each glyph would buy nothing and
    /// would drag a UI framework into this type.
    public static func curvedRulerCharacterSpacing(fontSize: CGFloat) -> CGFloat {
        fontSize * 0.62
    }

    /// Places each character of a ruler numeral on a tiny arc, rather than
    /// leaving the whole word on one straight baseline.
    public static func curvedRulerCharacterAngles(
        textLength: Int,
        centreAngle: Double,
        radius: CGFloat,
        characterSpacing: CGFloat = 8
    ) -> [Double] {
        guard textLength > 0, radius > 0 else { return [] }
        let degreesPerCharacter = Double(characterSpacing / radius) * 180 / .pi
        let midpoint = Double(textLength - 1) / 2
        return (0..<textLength).map { index in
            centreAngle + (Double(index) - midpoint) * degreesPerCharacter
        }
    }

    /// Half the angular width a numeral occupies once it is bent onto `radius`.
    public static func curvedRulerLabelHalfWidth(
        characterCount: Int,
        fontSize: CGFloat,
        radius: CGFloat
    ) -> Double {
        guard characterCount > 0, radius > 0 else { return 0 }
        let arc = curvedRulerCharacterSpacing(fontSize: fontSize) * CGFloat(characterCount)
        return Double(arc / radius) * 180 / .pi / 2
    }

    /// Where a numeral is actually centred, given the tick it belongs to.
    ///
    /// A number printed dead on the scale's own end spills half of itself into
    /// the neighbouring task. Nudging just the end numerals inward keeps the
    /// two values the countdown exists to show — full duration and zero —
    /// printed inside the active block, which a narrow overview wedge would
    /// otherwise lose entirely.
    public static func carouselRulerLabelCentreAngle(
        tickAngle: Double,
        span: (start: Double, end: Double),
        characterCount: Int,
        fontSize: CGFloat,
        radius: CGFloat
    ) -> Double {
        let half = curvedRulerLabelHalfWidth(
            characterCount: characterCount,
            fontSize: fontSize,
            radius: radius
        )
        let low = min(span.start, span.end) + half
        let high = max(span.start, span.end) - half
        guard low < high else { return (span.start + span.end) / 2 }
        return min(high, max(low, tickAngle))
    }

    // MARK: - Continuous zoom axis
    //
    // The four chip modes are also four points on one continuous axis, so a
    // pinch can rest between them while the fingers are still down instead of
    // snapping from one settled layout to the next. Everything below is an
    // interpolation of the discrete layouts above, and at an integer zoom each
    // function returns exactly what its discrete counterpart returns — which is
    // what keeps the four settled states unchanged.

    /// Where a settled mode sits on the continuous zoom axis: `0` is `1`, `3`
    /// is `All`.
    public static func carouselZoom(for visibility: WheelVisibility) -> Double {
        Double(WheelVisibility.carouselModes.firstIndex(of: visibility) ?? 0)
    }

    /// The live zoom for a pinch that began at `base`. One doubling of the
    /// fingers' spread is one mode step, so the dial answers the hand at a
    /// constant perceptual rate rather than by raw screen distance, and
    /// spreading still moves toward `All` as the old discrete step did.
    public static func carouselZoom(base: Double, magnification: Double) -> Double {
        let top = Double(WheelVisibility.carouselModes.count - 1)
        guard magnification > 0 else { return min(top, max(0, base)) }
        return min(top, max(0, base + log2(magnification)))
    }

    /// The mode a released pinch lands on: the nearest of the four. A dead-even
    /// half step rounds outward, toward `All`, so a tie always resolves the same
    /// way rather than depending on which side the fingers arrived from.
    public static func settledCarouselMode(forZoom zoom: Double) -> WheelVisibility {
        let modes = WheelVisibility.carouselModes
        let top = modes.count - 1
        return modes[Int(min(Double(top), max(0, zoom)).rounded())]
    }

    /// The angular width every queued block gets at a settled mode — the one
    /// description all four layouts share. `1`/`2`/`3` hand an equal slice to
    /// the blocks they show and nothing to the rest; `All` shares the full turn
    /// out by duration. Laid out contiguously from the active block (see
    /// `carouselSpans`) these reproduce `carouselSpan` exactly, which is what
    /// lets a fractional zoom interpolate one vector of widths instead of
    /// trying to interpolate four differently-shaped layouts.
    public static func carouselWidths(for visibility: WheelVisibility, durations: [Int]) -> [Double] {
        guard !durations.isEmpty else { return [] }
        if visibility == .all {
            let total = max(1, durations.reduce(0, +))
            return durations.map { 360 * Double($0) / Double(total) }
        }
        let shown = visibleCount(for: visibility, queueCount: durations.count)
        let sweep = carouselSweep(for: visibility, queueCount: durations.count)
        return durations.indices.map { $0 < shown ? sweep : 0 }
    }

    /// The two settled modes a zoom sits between, and how far along it is.
    private static func carouselBracket(zoom: Double) -> (lower: WheelVisibility, upper: WheelVisibility, fraction: Double) {
        let modes = WheelVisibility.carouselModes
        let clamped = min(Double(modes.count - 1), max(0, zoom))
        let lower = Int(clamped)
        return (modes[lower], modes[min(modes.count - 1, lower + 1)], clamped - Double(lower))
    }

    /// Block widths at a fractional zoom.
    public static func carouselWidths(zoom: Double, durations: [Int]) -> [Double] {
        let bracket = carouselBracket(zoom: zoom)
        let lower = carouselWidths(for: bracket.lower, durations: durations)
        guard bracket.fraction > 0 else { return lower }
        let upper = carouselWidths(for: bracket.upper, durations: durations)
        return zip(lower, upper).map { $0 + ($1 - $0) * bracket.fraction }
    }

    /// Every block's slice at a fractional zoom. The active block stays centred
    /// on the pointer and the rest are laid contiguously anticlockwise from it,
    /// so a block that is about to earn a slice grows out of nothing on the
    /// right — the same place a block always enters from — rather than fading
    /// in on top of its neighbour.
    public static func carouselSpans(
        zoom: Double,
        durations: [Int],
        rotation: Double
    ) -> [(start: Double, end: Double)] {
        let widths = carouselWidths(zoom: zoom, durations: durations)
        guard let active = widths.first else { return [] }
        var edge = bottomAngle - active / 2
        var spans = [(start: edge + rotation, end: edge + active + rotation)]
        for width in widths.dropFirst() {
            spans.append((start: edge - width + rotation, end: edge + rotation))
            edge -= width
        }
        return spans
    }

    /// The active block's sweep at a fractional zoom, which is what the ring's
    /// rotation through the running task is measured in. Interpolated from the
    /// same two modes as the widths so the turn and the slices cannot disagree
    /// halfway through a pinch.
    public static func carouselSweep(zoom: Double, queueCount: Int) -> Double {
        let bracket = carouselBracket(zoom: zoom)
        let lower = carouselSweep(for: bracket.lower, queueCount: queueCount)
        guard bracket.fraction > 0 else { return lower }
        let upper = carouselSweep(for: bracket.upper, queueCount: queueCount)
        return lower + (upper - lower) * bracket.fraction
    }

    /// The separator gap at a fractional zoom. The gap depends on how many
    /// blocks are on the ring, and that count changes the moment a pinch starts
    /// growing the next block — so it is interpolated rather than stepped, or
    /// every wedge on the dial would jump by the gap's width at the first
    /// millimetre of finger movement.
    public static func carouselGap(zoom: Double, durations: [Int]) -> Double {
        let bracket = carouselBracket(zoom: zoom)
        func gap(_ visibility: WheelVisibility) -> Double {
            wedgeGap(itemCount: carouselWidths(for: visibility, durations: durations).count { $0 > 0 })
        }
        let lower = gap(bracket.lower)
        guard bracket.fraction > 0 else { return lower }
        return lower + (gap(bracket.upper) - lower) * bracket.fraction
    }

    /// Whether a slice this wide still leaves a wedge once its separator gap is
    /// cut from both ends. Below that the arc inverts and paints nearly the
    /// whole ring — which is exactly what a block interpolating up from zero
    /// width would do for its first frames.
    public static func carouselWedgeIsDrawn(width: Double, gap: Double) -> Bool {
        width > 2 * gap
    }

    // MARK: - Bottom-arc dial
    //
    // The mock's dial is a shallow bowl cut from a much larger, mostly
    // off-screen circle: real clock time sweeps under a fixed pointer at the
    // bottom, so a segment's position comes from when it actually falls in
    // the day, not from a slot in a fixed fan (`focus-wheel-spec.md` §2).
    // A segment already finished lands left of the pointer; one still ahead
    // lands right — both sides populate whenever segments exist there,
    // unlike the one-sided fan this replaced.

    /// Clearance kept between the dial's lowest point and the pointer beneath it.
    public static let pointerInset: CGFloat = 14

    /// The pointer tip extends this far beyond the bowl's outer edge. Keeping
    /// the value in geometry keeps the marker and its hit-safe reserve aligned
    /// across every zoom level.
    public static let pointerMarkerOffset: CGFloat = 15

    /// Degrees of arc every minute of the day sweeps under the fixed
    /// pointer — one constant across every zoom level. The "5M vs 1 vs 2 vs
    /// 3" difference is entirely a change of radius, never of this rate
    /// (`focus-wheel-spec.md` §2). 780 is the minutes in the 13-hour window
    /// the design maps onto a full 360° turn.
    public static let degreesPerMinute: Double = 360.0 / 780.0

    /// How far out the bowl's true (mostly off-screen) circle sits for each
    /// zoom level, as a multiple of the container's own width. Values are the
    /// design's pixel radii against its fixed 375pt canvas
    /// (`focus-wheel-spec.md` §2) turned into ratios, so the bowl scales to
    /// whatever width `FocusScreen` actually gives it while keeping the
    /// design's proportions. `5M` is solved rather than looked up: the
    /// radius at which the container's own half-width subtends 2.5 minutes
    /// of arc — an almost-flat horizon showing roughly five minutes across
    /// the visible chord.
    public static func bowlTargetRadiusFraction(for visibility: WheelVisibility) -> Double {
        switch visibility {
        case .one: return 1150.0 / 375.0
        case .two, .all: return 680.0 / 375.0
        case .three: return 500.0 / 375.0
        case .fiveMinute:
            let halfDegrees = 2.5 * degreesPerMinute
            return 0.5 / sin(halfDegrees * .pi / 180)
        }
    }

    /// The bowl's target radius, in points, for a dial `width` wide.
    public static func bowlTargetRadius(forWidth width: CGFloat, visibility: WheelVisibility) -> CGFloat {
        width * CGFloat(bowlTargetRadiusFraction(for: visibility))
    }

    /// The visual separator between adjacent task wedges. It belongs with the
    /// spans so every dial variant uses one angular gap policy.
    public static func wedgeGap(itemCount: Int) -> Double {
        itemCount > 1 ? 1.6 : 0
    }

    /// The ring is always this fraction of the dial's width thick, regardless
    /// of zoom level (`focus-wheel-spec.md` §2's fixed 136pt against its
    /// 375pt canvas).
    public static let bowlThicknessFraction: CGFloat = 136.0 / 375.0

    public static func bowlThickness(forWidth width: CGFloat) -> CGFloat {
        width * bowlThicknessFraction
    }

    /// Half the angular window actually on screen at `radius`, for a dial
    /// `width` wide: the container's own half-width subtends this many
    /// degrees at that radius. A bigger radius (more zoomed in) narrows the
    /// window — this, not `degreesPerMinute`, is the entire zoom mechanism
    /// (`focus-wheel-spec.md` §2).
    public static func bowlHalfVisibleDegrees(radius: CGFloat, width: CGFloat) -> Double {
        guard radius > 0 else { return 0 }
        let ratio = min(1, Double(width / 2 / radius))
        return asin(ratio) * 180 / .pi
    }

    /// The visible angular window, with a 3° overscan margin either side so
    /// segments don't pop in right at the container's own edge
    /// (`focus-wheel-spec.md` §2).
    public static func bowlVisibleWindow(radius: CGFloat, width: CGFloat) -> (min: Double, max: Double) {
        let half = bowlHalfVisibleDegrees(radius: radius, width: width)
        return (bottomAngle - half - 3, bottomAngle + half + 3)
    }

    /// Leading/trailing angle of a segment that starts `start` minutes from
    /// midnight and lasts `duration` minutes, at the current time
    /// `nowMinutes` (same units). Returned already sorted so it can be
    /// passed straight to `WheelWedgeShape`. A segment already finished
    /// lands past the pointer on one side; one still ahead lands past it on
    /// the other — both from this single formula, since only `nowMinutes`
    /// relative to `start`/`start + duration` decides which
    /// (`focus-wheel-spec.md` §2).
    public static func bowlSegmentSpan(start: Double, duration: Double, nowMinutes: Double) -> (start: Double, end: Double) {
        let leading = bottomAngle + (nowMinutes - start) * degreesPerMinute
        let trailing = bottomAngle + (nowMinutes - (start + duration)) * degreesPerMinute
        return (min(leading, trailing), max(leading, trailing))
    }

    /// Whether a segment with this span falls at least partly inside the
    /// visible window — the crop that replaces a fixed task-count cap: every
    /// scheduled segment is considered, only the angle decides which are
    /// drawn (`focus-wheel-spec.md` §2).
    public static func bowlSegmentIsVisible(span: (start: Double, end: Double), window: (min: Double, max: Double)) -> Bool {
        // Overlap, not containment. A segment longer than the visible window
        // is the normal case on a zoomed dial — the active task usually is —
        // so requiring it to fit entirely inside the window drops exactly the
        // segment the user is looking at.
        span.end > window.min + 1 && span.start < window.max - 1
    }

    /// Unscheduled spans of the working day (08:00–21:00 by default), given
    /// the day's scheduled `(start, duration)` pairs in minutes. Re-scanned
    /// fresh each call rather than cached, since segments can change between
    /// renders (`focus-wheel-spec.md` §2).
    public static func bowlGaps(
        scheduled: [(start: Double, duration: Double)],
        dayStart: Double = 480,
        dayEnd: Double = 1260
    ) -> [(start: Double, duration: Double)] {
        var gaps: [(start: Double, duration: Double)] = []
        var cursor = dayStart
        for segment in scheduled.sorted(by: { $0.start < $1.start }) {
            if segment.start > cursor {
                gaps.append((start: cursor, duration: segment.start - cursor))
            }
            cursor = max(cursor, segment.start + segment.duration)
        }
        if cursor < dayEnd {
            gaps.append((start: cursor, duration: dayEnd - cursor))
        }
        return gaps
    }

    /// Whether a gap's own visible span, clipped to the window with a 2°
    /// margin, is wide enough to earn a `FREE` label rather than just the
    /// bare ring showing through (`focus-wheel-spec.md` §2's 9° threshold).
    /// The gap itself is never filled — this only decides the label.
    public static func bowlGapShowsFreeLabel(span: (start: Double, end: Double), window: (min: Double, max: Double)) -> Bool {
        let clipped = bowlGapClipped(span: span, window: window)
        return clipped.end - clipped.start > 9
    }

    /// Where the `FREE` label sits: the middle of the gap's VISIBLE stretch, not
    /// of the gap itself.
    ///
    /// The two only agree for a gap straddling the pointer. The demo day's real
    /// gap is the whole morning before the plan starts, which qualifies on its
    /// last few degrees while its raw midpoint is most of a turn away — drawn,
    /// but off screen, which is why the label had never been photographed.
    public static func bowlGapLabelAngle(span: (start: Double, end: Double), window: (min: Double, max: Double)) -> Double {
        let clipped = bowlGapClipped(span: span, window: window)
        return (clipped.start + clipped.end) / 2
    }

    /// The gap's span cropped to the window, held 2° inside each edge so a label
    /// is never crowded against it.
    private static func bowlGapClipped(span: (start: Double, end: Double), window: (min: Double, max: Double)) -> (start: Double, end: Double) {
        (start: max(span.start, window.min + 2), end: min(span.end, window.max - 2))
    }

    /// Fraction of the visible window the active wedge's ruler overlay
    /// spans. Unrelated to the active segment's own true (and possibly
    /// asymmetric) elapsed/remaining split — the ruler stays the
    /// artificially-centred overlay it has always been since task 57 fixed
    /// its numbering, decoupled from where the real wedge now sits.
    /// Keep the ruler nearly as wide as the visible task block. The original
    /// design deliberately lets the full-duration and zero marks breathe at
    /// the two ends; a narrow overlay made captures begin at `26` and finish
    /// at `1`, which broke the dial's most important arithmetic cue.
    public static let dialActiveFraction: Double = 0.88

    /// Angular span of the active wedge's ruler overlay, centred at
    /// `bottomAngle` — unchanged since task 57; the bowl's per-segment
    /// placement above does not feed into this.
    public static func dialActiveSpan(halfAngle: Double) -> (start: Double, end: Double) {
        let half = halfAngle * dialActiveFraction
        return (bottomAngle - half, bottomAngle + half)
    }

    /// Angle of the ruler tick showing `minutesRemaining` of `totalMinutes`,
    /// mapped across the active wedge's own span. The scale counts down like
    /// the header's countdown: the full duration sits at the LEFT end and
    /// `0` sits at the RIGHT end (`focus-wheel-spec.md` §4 — the design
    /// numbers minutes remaining, not minutes elapsed).
    public static func dialTickAngle(minutesRemaining: Int, totalMinutes: Int, halfAngle: Double) -> Double {
        let span = dialActiveSpan(halfAngle: halfAngle)
        guard totalMinutes > 0 else { return span.start }
        let fraction = Double(minutesRemaining) / Double(totalMinutes)
        return span.start + (span.end - span.start) * fraction
    }

    /// Position of a live ruler tick on the same clock-time axis as its task.
    /// Elapsed minutes move clockwise away from the task's start; remaining
    /// minutes therefore read from the left/past side toward zero on the right.
    public static func bowlRulerAngle(
        elapsedMinutes: Double,
        activeStartMinutes: Double,
        nowMinutes: Double
    ) -> Double {
        bottomAngle + (nowMinutes - (activeStartMinutes + elapsedMinutes)) * degreesPerMinute
    }

    /// The value printed beside a ruler major tick.
    public static func bowlRulerRemaining(elapsedMinutes: Double, totalMinutes: Int) -> Int {
        max(0, totalMinutes - Int(elapsedMinutes.rounded()))
    }

    /// Source-spec ruler cadence: zoom controls how much arithmetic is shown,
    /// not the meaning of the clock. The close modes deliberately get fewer
    /// labels as the ring opens out, while 5M exposes ten-second detail.
    public static func bowlRulerMajorStep(radius: CGFloat) -> Int {
        radius > 3_000 ? 1 : radius >= 900 ? 5 : radius >= 550 ? 10 : 15
    }

    public static func bowlRulerSubdivisions(radius: CGFloat) -> Int {
        radius > 3_000 ? 6 : 1
    }

    // MARK: - All-mode overview ring
    //
    // The mock's `All` view swaps the bowl for a small, fully-closed 360°
    // ring: every queued task gets one wedge, sized to its own share of
    // total duration, rather than the bowl's fixed per-slot sweep. Fixed at
    // `R0=96, R1=146` about a 320pt canvas (`focus-wheel-spec.md` §3);
    // expressed as fractions of canvas width so the ring scales with
    // whatever container it's given while keeping that same 96:146 ratio.

    private static let overviewCanvasWidth: CGFloat = 320
    public static let overviewOuterRadiusFraction: CGFloat = 146 / overviewCanvasWidth
    public static let overviewInnerRadiusFraction: CGFloat = 96 / overviewCanvasWidth

    /// Beyond this angular span a segment earns both a title and a duration
    /// label; at or below it, only the compact duration is drawn — a label
    /// tier demotion, not truncation (`focus-wheel-spec.md` §3, design line 565).
    public static let overviewLabelThresholdDegrees: Double = 26

    public static func overviewOuterRadius(width: CGFloat) -> CGFloat {
        width * overviewOuterRadiusFraction
    }

    public static func overviewInnerRadius(width: CGFloat) -> CGFloat {
        width * overviewInnerRadiusFraction
    }

    /// Angular span of the item at `index` (`0` is the active task), sized
    /// to its own share of `durations`' total and laid out clockwise from
    /// the active wedge — the same "next enters from the right" rule as the
    /// bowl, just closed into a full circle instead of a shallow arc.
    public static func overviewSpan(index: Int, durations: [Int]) -> (start: Double, end: Double) {
        guard durations.indices.contains(index) else { return (bottomAngle, bottomAngle) }
        let total = max(1, durations.reduce(0, +))
        func width(_ i: Int) -> Double { 360 * Double(durations[i]) / Double(total) }

        let activeWidth = width(0)
        let activeStart = bottomAngle - activeWidth / 2
        guard index > 0 else { return (activeStart, activeStart + activeWidth) }

        var end = activeStart
        for i in 1..<index { end -= width(i) }
        return (end - width(index), end)
    }

    /// Whether a segment this wide earns a title label alongside its
    /// duration, or drops to duration-only (`overviewLabelThresholdDegrees`).
    public static func overviewShowsTitle(spanDegrees: Double) -> Bool {
        spanDegrees > overviewLabelThresholdDegrees
    }

    /// Minimum arc length, in points, a wedge needs at the label radius
    /// before any label is drawn at all — below this even the duration-only
    /// tier would spill into its neighbour, since a `Text` is laid out at
    /// its natural width regardless of how much arc it sits on (unlike the
    /// design's `textPath`, which clips text to the arc's own length).
    ///
    /// Measured, not guessed: "88M" — the widest realistic two-digit
    /// compact-duration string (`DurationFormatter.compact`) — rendered at
    /// `FlowFont.durationChip`'s underlying system font (`.caption2` bold
    /// rounded, 11pt at the default Dynamic Type size) comes out to ~25pt
    /// wide; `Tests/FocusTests.swift`'s `overviewHidesLabelWhenArcTooShort`
    /// re-measures this on every run so the constant can't quietly go
    /// stale. The extra few points cover kerning/anti-aliasing variance.
    public static let overviewMinLabelArcLength: CGFloat = 28

    /// Whether a wedge this wide, at this label radius, has room to draw
    /// any label without overlapping its neighbour — a third tier below
    /// `overviewShowsTitle`, demoting duration-only labels to no label.
    public static func overviewShowsLabel(spanDegrees: Double, labelRadius: CGFloat) -> Bool {
        let arcLength = labelRadius * CGFloat(spanDegrees * .pi / 180)
        return arcLength >= overviewMinLabelArcLength
    }

    /// Angle for the overview ring's inward countdown ruler. The full
    /// duration is fixed at the left-hand end of the inner half-ring and zero
    /// at the right, matching the close dial while keeping the complete ring
    /// legible when zoomed all the way out.
    public static func overviewRulerAngle(minutesRemaining: Int, totalMinutes: Int) -> Double {
        guard totalMinutes > 0 else { return 360 }
        let fraction = min(1, max(0, Double(minutesRemaining) / Double(totalMinutes)))
        return 360 - fraction * 180
    }

    /// Number of overview ruler ticks. Short tasks get one tick per minute;
    /// long tasks cap at one tick for every few minutes so the inner track stays
    /// detailed without turning into an indistinguishable solid line.
    public static func overviewRulerTickCount(totalMinutes: Int) -> Int {
        min(60, max(6, totalMinutes))
    }

    // MARK: - Bowl neighbour labels

    /// The widest a neighbour wedge's label is ever drawn: the band it sits
    /// in, floored so a thin ring still gets a readable label.
    public static func neighbourLabelBandWidth(thickness: CGFloat) -> CGFloat {
        max(56, thickness * 1.6)
    }

    /// How much room a neighbour wedge's label really has, and whether that
    /// is tight enough to step the title's type down a size.
    ///
    /// The label runs along the arc, so a short wedge is a narrow label —
    /// the design answers this by shrinking the type rather than truncating
    /// a five-minute task down to one word. The floor stops an extremely
    /// thin sliver from collapsing the label to nothing.
    public static func neighbourLabel(
        spanDegrees: Double,
        midRadius: CGFloat,
        thickness: CGFloat
    ) -> (width: CGFloat, isTight: Bool) {
        let band = neighbourLabelBandWidth(thickness: thickness)
        let arcLength = midRadius * CGFloat(abs(spanDegrees) * .pi / 180)
        let width = min(band, max(30, arcLength - 4))
        return (width, width < band)
    }
}
