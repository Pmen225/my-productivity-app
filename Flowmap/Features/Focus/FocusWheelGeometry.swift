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
/// So the active segment's *leading* edge is pinned to `90°` and each upcoming
/// task is placed a further `sweep` degrees *anticlockwise* from it — that is,
/// up the right-hand side.
///
/// Elapsing time is shown by CONSUMING the active wedge at the pointer: its
/// drawn width is `(1 − elapsed) × settledWidth`, and because the whole
/// contiguous layout starts from that shrinking wedge, every block on the ring
/// creeps clockwise as the task runs. Paired with the entering block's ramp
/// (see `carouselWidths`) the ring stays exactly full at the capped modes, and
/// at `elapsed == 1` the next task has arrived at the pointer with no snap
/// frame to advance through.
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

    /// The ruler as a tape measure: the numerals are fixed to the TASK, not to
    /// the screen, and the whole tape translates clockwise into the pointer as
    /// the task is consumed.
    ///
    /// `activeSpan` is the block's *remaining* wedge and `settledWidth` its full
    /// width, so the tape starts at the wedge's far (anticlockwise) edge — where
    /// `0` lives, arriving at the pointer exactly at completion — and runs a
    /// full width clockwise, carrying `totalMinutes` past the pointer into the
    /// consumed arc. The consequence is the one the founder asked for: whatever
    /// numeral is crossing the pointer IS the minutes remaining, with no
    /// separate readout to reconcile.
    public static func carouselRulerTapeSpan(
        activeSpan: (start: Double, end: Double),
        settledWidth: Double
    ) -> (start: Double, end: Double) {
        (start: activeSpan.start, end: activeSpan.start + settledWidth)
    }

    /// The highest remaining-minutes mark still on the live side of the pointer.
    /// Anything above it has already been consumed and must not be drawn, or the
    /// tape would print marks over the queue behind the pointer.
    public static func carouselRulerTopTick(totalMinutes: Int, elapsed: Double) -> Int {
        guard totalMinutes > 0 else { return 0 }
        return Int((Double(totalMinutes) * (1 - clampedElapsed(elapsed))).rounded(.down))
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

    /// Arc a numeral needs to itself, plus the clearance that stops two
    /// adjacent numerals reading as one number. Three character advances: the
    /// scale never prints more than two digits, so this is the number's own
    /// width and one blank beside it.
    public static func rulerMinLabelArc(fontSize: CGFloat) -> CGFloat {
        curvedRulerCharacterSpacing(fontSize: fontSize) * 3
    }

    /// How often the ruler prints a number, decided by the ARC the numerals
    /// actually have to sit on rather than by the wedge's angle alone.
    ///
    /// Degrees are not legibility: the same 60° wedge is roomy on a full-screen
    /// dial and cramped on a small one, and Dynamic Type moves the goalposts
    /// again. Measuring the real arc is what makes the zoom progressive — the
    /// deeper the zoom the longer the active wedge's arc, so numerals appear at
    /// a finer cadence on the way in and thin out on the way to `All`, without
    /// a magic degree threshold deciding it.
    ///
    /// The floor is `carouselRulerMajorStep`, so a fully-magnified block is
    /// numbered every five minutes (ten past the hour) and never denser than
    /// its own major ticks — UNLESS `visibleWindowDegrees` says the close-up
    /// has narrowed past what that floor can guarantee (see below). Endpoints
    /// are added by the renderer regardless.
    ///
    /// `visibleWindowDegrees` is the angular width of whatever the close-up
    /// currently shows around the pointer (`magnifyVisibleWindow`'s span).
    /// At rest it is effectively infinite — the whole ring is visible — so it
    /// never overrides the legibility search below. Deep in a close-up
    /// (Task 53) it can fall well under the floor cadence's own spacing: a
    /// single full-circle task numbered every five minutes places its labels
    /// 60° apart, but an 8× close-up on a typical phone shows barely 15° of
    /// ring, so most of the time NO labelled tick is inside it — the ruler
    /// numeral vanishes entirely while the task is running, even though the
    /// unlabelled minute ticks are still drawn. Tightening the cadence until
    /// consecutive labels are no further apart than the window is wide
    /// guarantees at least one is always on screen.
    public static func carouselRulerLabelStep(
        totalMinutes: Int,
        spanDegrees: Double,
        numeralRadius: CGFloat,
        fontSize: CGFloat,
        visibleWindowDegrees: Double = .infinity
    ) -> Int {
        let floorStep = carouselRulerMajorStep(totalMinutes: totalMinutes)
        guard totalMinutes > 0, numeralRadius > 0 else { return floorStep }
        let arc = Double(numeralRadius) * abs(spanDegrees) * .pi / 180
        let needed = Double(rulerMinLabelArc(fontSize: fontSize))
        let degreesPerMinute = abs(spanDegrees) / Double(totalMinutes)

        func isLegible(_ step: Int) -> Bool {
            let intervals = max(1, Double(totalMinutes) / Double(step))
            return arc / intervals >= needed
        }
        func fitsWindow(_ step: Int) -> Bool {
            guard visibleWindowDegrees.isFinite, degreesPerMinute > 0 else { return true }
            return Double(step) * degreesPerMinute <= visibleWindowDegrees
        }

        guard fitsWindow(floorStep) else {
            // The window has narrowed past the floor's own spacing: shrink
            // the cadence until a label is guaranteed to land inside it,
            // never below one minute.
            var step = floorStep - 1
            while step > 1 && !fitsWindow(step) { step -= 1 }
            return max(1, step)
        }
        for step in [floorStep, 10, 15, 30, 60] where step >= floorStep {
            if isLegible(step) && fitsWindow(step) { return step }
        }
        // Nothing fits: keep only the two endpoints the countdown exists to show.
        return max(floorStep, totalMinutes)
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

        /// The same set of tracks on the close-up circle. Ticks painted
        /// between a magnified base and tip keep their clock-face proportion
        /// with the grown band while their strokes stay native-width — left
        /// inside the scaled group, a 0.8pt minute line ballooned into a
        /// ~5pt slab and the scale read as decoration.
        public func magnified(factor: Double) -> RulerRadii {
            RulerRadii(
                numeral: FocusWheelGeometry.magnifiedRadius(numeral, factor: factor),
                tickBase: FocusWheelGeometry.magnifiedRadius(tickBase, factor: factor),
                minorTip: FocusWheelGeometry.magnifiedRadius(minorTip, factor: factor),
                mediumTip: FocusWheelGeometry.magnifiedRadius(mediumTip, factor: factor),
                majorTip: FocusWheelGeometry.magnifiedRadius(majorTip, factor: factor)
            )
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

    /// Whether a ruler tick at `angle` sits inside the close-up's visible
    /// window — the ruler's counterpart to `clippedSpanMidAngle` for wedge
    /// labels.
    ///
    /// At rest the window spans the whole circle so every tick passes; deep
    /// in a close-up it narrows to a few degrees around the pointer, and a
    /// tick outside it has nothing on screen to sit on. Skipping it here
    /// keeps the loop honest about what it is actually drawing, the same way
    /// the wedge path already clips before it places a label.
    public static func carouselRulerTickIsVisible(angle: Double, window: (start: Double, end: Double)) -> Bool {
        guard window.end > window.start else { return true }
        let windowCentre = (window.start + window.end) / 2
        let turns = ((windowCentre - angle) / 360).rounded()
        let shifted = angle + turns * 360
        return shifted >= window.start && shifted <= window.end
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
    /// constant perceptual rate rather than by raw screen distance.
    ///
    /// The sign is what makes this true magnification: spreading the fingers
    /// (`magnification > 1`) *reduces* the zoom coordinate, moving toward `1`
    /// — one task filling the ring in full detail — exactly as spreading
    /// enlarges a map or a photo. Pinching inward pulls back toward `All`.
    /// The earlier mapping added the logarithm instead, so spreading zoomed
    /// out; that inverted every user's expectation of the gesture.
    public static func carouselZoom(base: Double, magnification: Double) -> Double {
        let top = Double(WheelVisibility.carouselModes.count - 1)
        guard magnification > 0 else { return min(top, max(0, base)) }
        return min(top, max(0, base - log2(magnification)))
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
    /// `elapsed` is the active task's elapsed fraction, `0...1`. At `0` the
    /// result is the settled layout exactly; as the task runs, the first block
    /// beyond the visible cap grows from nothing to a full slice, so the queue
    /// is seen to advance instead of the ring simply spinning with nothing
    /// arriving. `All` already draws every block, so it is unaffected.
    ///
    /// These are the SETTLED widths — the active block's entry is its full
    /// slice, not the consumed remainder. Consumption is applied once, in
    /// `carouselSpans`, so the ruler can keep measuring against the task's
    /// whole width while the drawn wedge shrinks.
    public static func carouselWidths(
        for visibility: WheelVisibility,
        durations: [Int],
        elapsed: Double = 0
    ) -> [Double] {
        guard !durations.isEmpty else { return [] }
        if visibility == .all {
            let total = max(1, durations.reduce(0, +))
            return durations.map { 360 * Double($0) / Double(total) }
        }
        let shown = visibleCount(for: visibility, queueCount: durations.count)
        let sweep = carouselSweep(for: visibility, queueCount: durations.count)
        let entering = clampedElapsed(elapsed) * sweep
        return durations.indices.map { index in
            if index < shown { return sweep }
            // Only the FIRST hidden block enters; the ones behind it wait
            // their turn, or the whole tail of the queue would inflate at once.
            return index == shown ? entering : 0
        }
    }

    /// The two settled modes a zoom sits between, and how far along it is.
    private static func carouselBracket(zoom: Double) -> (lower: WheelVisibility, upper: WheelVisibility, fraction: Double) {
        let modes = WheelVisibility.carouselModes
        let clamped = min(Double(modes.count - 1), max(0, zoom))
        let lower = Int(clamped)
        return (modes[lower], modes[min(modes.count - 1, lower + 1)], clamped - Double(lower))
    }

    /// Block widths at a fractional zoom. Both bracketing layouts are taken at
    /// the SAME `elapsed`, so a pinch part-way through a task interpolates two
    /// states that already agree about the entering block — interpolating an
    /// elapsed-adjusted layout against a settled one would snap it away mid-turn.
    public static func carouselWidths(zoom: Double, durations: [Int], elapsed: Double = 0) -> [Double] {
        let bracket = carouselBracket(zoom: zoom)
        let lower = carouselWidths(for: bracket.lower, durations: durations, elapsed: elapsed)
        guard bracket.fraction > 0 else { return lower }
        let upper = carouselWidths(for: bracket.upper, durations: durations, elapsed: elapsed)
        return zip(lower, upper).map { $0 + ($1 - $0) * bracket.fraction }
    }

    /// Every block's slice at a fractional zoom, with the active block CONSUMED
    /// at the pointer: its drawn width is `(1 − elapsed) × settledWidth` and its
    /// leading (clockwise) edge is pinned to `bottomAngle`, so the wedge shrinks
    /// *into* the pointer. Everything else is laid contiguously anticlockwise
    /// from its far edge, which means the whole ring creeps clockwise as the
    /// task runs — the movement is the point, and it is what the founder's
    /// ruling asked for.
    ///
    /// Paired with the entering block's ramp (`carouselWidths`) the capped modes
    /// stay exactly full: at mode `Two`, `(1−e)·180 + 180 + e·180 = 360` for
    /// every `e`. At `e == 1` the layout equals the settled layout of the queue
    /// with the head dropped, so the advance has no snap frame.
    public static func carouselSpans(
        zoom: Double,
        durations: [Int],
        rotation: Double,
        elapsed: Double = 0
    ) -> [(start: Double, end: Double)] {
        let widths = carouselWidths(zoom: zoom, durations: durations, elapsed: elapsed)
        guard let settled = widths.first else { return [] }
        let active = settled * (1 - clampedElapsed(elapsed))
        var edge = bottomAngle - active
        var spans = [(start: edge + rotation, end: bottomAngle + rotation)]
        for width in widths.dropFirst() {
            spans.append((start: edge - width + rotation, end: edge + rotation))
            edge -= width
        }
        return spans
    }

    /// The quiet arc left behind the pointer once the ring no longer fills the
    /// turn — `nil` when it is closed. At the capped modes the entering block's
    /// ramp keeps this at zero; at `All` there is no hidden block to ramp, so
    /// consumed time simply leaves a growing gap on the clockwise side of the
    /// pointer, which is honest at day scale: that time is gone.
    public static func carouselFreeSpan(
        zoom: Double,
        durations: [Int],
        rotation: Double,
        elapsed: Double = 0
    ) -> (start: Double, end: Double)? {
        let free = 360 - carouselTotalWidth(zoom: zoom, durations: durations, elapsed: elapsed)
        guard free > 0.5 else { return nil }
        return (start: bottomAngle + rotation, end: bottomAngle + free + rotation)
    }

    /// How much of the turn the drawn blocks cover, consumption included. The
    /// clamp on time-travel and the free arc both measure against this, so they
    /// cannot disagree about where the queue ends.
    public static func carouselTotalWidth(zoom: Double, durations: [Int], elapsed: Double = 0) -> Double {
        let widths = carouselWidths(zoom: zoom, durations: durations, elapsed: elapsed)
        guard let settled = widths.first else { return 0 }
        let consumed = settled * clampedElapsed(elapsed)
        return max(0, widths.reduce(0, +) - consumed)
    }

    /// Elapsed fractions arrive from a live clock, so clamp once here rather
    /// than trusting every call site to have done it.
    private static func clampedElapsed(_ elapsed: Double) -> Double {
        min(1, max(0, elapsed))
    }

    /// Minutes actually left on the active task — the state the founder's
    /// cognitive profile requires the hub to keep restating.
    ///
    /// `totalMinutes` is the block's static allocation, which is also what
    /// sizes its wedge; that value must not move as the clock runs or the
    /// ring would resize under the reader. The countdown the hub shows is a
    /// different number derived from the same two inputs the wedge already
    /// carries, not a second source of truth.
    public static func carouselActiveRemainingMinutes(totalMinutes: Int, elapsed: Double) -> Int {
        max(0, Int((Double(totalMinutes) * (1 - clampedElapsed(elapsed))).rounded()))
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
    public static func carouselGap(zoom: Double, durations: [Int], elapsed: Double = 0) -> Double {
        let bracket = carouselBracket(zoom: zoom)
        func gap(_ visibility: WheelVisibility) -> Double {
            wedgeGap(
                itemCount: carouselWidths(
                    for: visibility,
                    durations: durations,
                    elapsed: elapsed
                ).count { $0 > 0 }
            )
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

    // MARK: - Time travel

    /// The dial's drawn diameter for a given container. The drag maps finger
    /// travel to degrees against the ring's radius, so the gesture and the
    /// artwork must read the same number from one place — a second copy of this
    /// formula is exactly how a wheel bug survived its first fix here before.
    public static func carouselDiameter(in size: CGSize) -> CGFloat {
        min(size.width - FlowSpacing.l, max(200, size.height - 44))
    }

    /// Finger travel along the ring, in degrees of preview rotation.
    ///
    /// Dragging LEFT at the bottom of the dial pushes the band clockwise, which
    /// is the direction the queue already travels as time passes — so pulling
    /// left peeks at what is coming, matching the movement the founder watches
    /// all session rather than inventing a second convention.
    public static func dragPreviewOffset(translationWidth: CGFloat, radius: CGFloat) -> Double {
        guard radius > 0 else { return 0 }
        return -Double(translationWidth / radius) * 180 / .pi
    }

    /// Hold the preview inside the queue that actually exists. Forward travel
    /// stops once the last block's far edge reaches the pointer — past that
    /// there is nothing to look at — and backward travel is pinned at zero,
    /// because the carousel carries no history to scroll into.
    public static func clampDragPreview(
        _ offset: Double,
        zoom: Double,
        durations: [Int],
        elapsed: Double = 0
    ) -> Double {
        let limit = carouselTotalWidth(zoom: zoom, durations: durations, elapsed: elapsed)
        return min(max(0, limit), max(0, offset))
    }

    /// Which queued block the pointer is reading at a given preview offset, or
    /// `nil` when the pointer is over the free arc. The drag's detent haptic
    /// fires on changes to this, so the feedback is driven by the same spans
    /// that are drawn rather than by a distance the view guesses at.
    public static func carouselIndexAtPointer(
        zoom: Double,
        durations: [Int],
        elapsed: Double = 0,
        offset: Double = 0
    ) -> Int? {
        let spans = carouselSpans(zoom: zoom, durations: durations, rotation: offset, elapsed: elapsed)
        return spans.firstIndex { $0.start <= bottomAngle && bottomAngle <= $0.end }
    }

    /// Converts the finger's angular velocity into SwiftUI spring units for a
    /// return to zero. A negative result means the wheel was still travelling
    /// away from home when released; keeping a restrained amount of that
    /// momentum is what makes the settle one continuous physical path instead
    /// of a second, disconnected reset animation.
    public static func wheelSettleInitialVelocity(
        currentOffset: Double,
        angularVelocity: Double
    ) -> Double {
        let distanceToHome = -currentOffset
        guard abs(distanceToHome) > 0.001 else { return 0 }
        return min(3, max(-1.5, angularVelocity / distanceToHome))
    }

    /// Keeps a native-size neighbour label wholly inside the visible wheel
    /// viewport. The wedge can continue beyond the crop, but its title must
    /// never lose the leading icon or the first letters at either screen edge.
    public static func edgeSafeLabelPosition(
        _ position: CGPoint,
        labelWidth: CGFloat,
        viewportWidth: CGFloat,
        edgeInset: CGFloat
    ) -> CGPoint {
        guard viewportWidth > 0 else { return position }
        let safeInset = min(max(0, edgeInset), viewportWidth / 2)
        let halfWidth = min(max(0, labelWidth / 2), viewportWidth / 2 - safeInset)
        let minimumX = safeInset + halfWidth
        let maximumX = viewportWidth - safeInset - halfWidth
        return CGPoint(x: min(maximumX, max(minimumX, position.x)), y: position.y)
    }

    // MARK: - Re-forming swell

    /// How far the re-forming style lets the dial swell under the fingers.
    public static let reformScaleRange: ClosedRange<Double> = 0.88...1.18

    /// The live swell for the re-forming style, damped so one doubling of the
    /// fingers' spread — the same doubling that is one mode step — grows the
    /// dial by about a seventh. Enough that the ring is felt to answer the
    /// hand; not so much that it collides with the title above it.
    ///
    /// This is a rendering scale and nothing else reads it: the widths still
    /// come from the zoom axis, so what is drawn and what is measured cannot
    /// drift apart.
    public static func reformScale(magnification: Double) -> Double {
        guard magnification > 0 else { return 1 }
        let swelled = 1 + 0.14 * log2(magnification)
        return min(reformScaleRange.upperBound, max(reformScaleRange.lowerBound, swelled))
    }

    // MARK: - Close-up magnification
    //
    // The close-up style stops the pinch from re-forming the ring and simply
    // magnifies the drawing about the pointer, so leaning in shows the same
    // ring in more detail instead of a different layout. Everything the view
    // needs to do that — how far it is magnified, where the anchor sits, and
    // how much of the ring is still on screen — is computed here, because the
    // view is not allowed to work out an angle for itself.

    /// How far the close-up may be magnified. One is the whole circle; eight is
    /// about one task filling the screen, past which nothing readable is left.
    public static let magnifyRange: ClosedRange<Double> = 1...8

    /// The live magnification for a pinch that began at `base`. Spreading the
    /// fingers magnifies directly, unlike the re-forming style's logarithm,
    /// because here the gesture and the drawing are the same quantity — the
    /// ring should track the fingers one-for-one.
    public static func magnifyFactor(base: Double, magnification: Double) -> Double {
        guard magnification > 0 else { return clampMagnify(base) }
        return clampMagnify(base * magnification)
    }

    public static func clampMagnify(_ factor: Double) -> Double {
        min(magnifyRange.upperBound, max(magnifyRange.lowerBound, factor))
    }

    /// The doubling stops VoiceOver moves through: 1, 2, 4, 8. Stepping by
    /// doublings rather than by a linear increment keeps the announced values
    /// the same landmarks the haptic marks for everyone else.
    public static func steppedMagnifyFactor(from factor: Double, delta: Int) -> Double {
        let stops = magnifyStops
        let nearest = stops.enumerated().min { lhs, rhs in
            abs(lhs.element - factor) < abs(rhs.element - factor)
        }
        let index = nearest?.offset ?? 0
        return stops[min(stops.count - 1, max(0, index + delta))]
    }

    public static let magnifyStops: [Double] = [1, 2, 4, 8]

    /// Which doubling the magnification is currently inside. The zoom-settle
    /// haptic fires on changes to this, so crossing 2×, 4× and 8× is felt
    /// without any new feedback machinery.
    public static func magnifyHapticBucket(factor: Double) -> Int {
        let clamped = clampMagnify(factor)
        return Int(floor(log2(clamped)))
    }

    /// The radius the drawing effectively has once magnified. The ruler's
    /// arc-length cadence must be given this rather than the laid-out radius,
    /// or the numerals stay as sparse as they were at 1× while the arc they sit
    /// on has grown eightfold.
    public static func magnifiedRadius(_ radius: CGFloat, factor: Double) -> CGFloat {
        radius * CGFloat(clampMagnify(factor))
    }

    /// The dial's drawn centre inside its container. Nudged up so the ring sits
    /// above the centre control rather than behind it.
    public static func carouselCentre(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2 - 16)
    }

    /// Where the active task's title sits: fixed above the centre control,
    /// at a constant screen position regardless of the close-up factor.
    ///
    /// Like the pointer, the title marks state the founder must always be
    /// able to read — which task is running — rather than a point on the
    /// ring, so it is drawn as a sibling of the magnified group and anchored
    /// here instead of scaling and sliding off screen with it.
    public static func carouselActiveTitleCentre(dialCentre: CGPoint) -> CGPoint {
        CGPoint(x: dialCentre.x, y: dialCentre.y - (FlowControlSize.hero / 2 + FlowSpacing.l))
    }

    /// The magnify anchor in unit space: the pointer, at the bottom of the
    /// ring. Scaling about it is what pushes the far side of the circle off
    /// screen while the band being read stays exactly where it was.
    public static func magnifyAnchorUnit(in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        let centre = carouselCentre(in: size)
        let radius = carouselDiameter(in: size) / 2
        let pointer = point(centre: centre, radius: radius, angle: bottomAngle)
        return CGPoint(x: pointer.x / size.width, y: pointer.y / size.height)
    }

    /// Where the dial's centre lands on screen once the close-up is applied.
    ///
    /// The scaled drawing is still a circle — centre here, radius
    /// `magnifiedRadius` — so text drawn OUTSIDE the scaled group can sit on
    /// the magnified wheel at its own native size instead of being rasterised
    /// and ballooned by the group's `scaleEffect`. The pointer is the
    /// transform's fixed point: scaling about it moves the centre, never the
    /// band being read.
    public static func magnifiedDialCentre(in size: CGSize, factor: Double) -> CGPoint {
        let m = clampMagnify(factor)
        let centre = carouselCentre(in: size)
        let radius = carouselDiameter(in: size) / 2
        let anchor = point(centre: centre, radius: radius, angle: bottomAngle)
        return CGPoint(
            x: anchor.x + (centre.x - anchor.x) * m,
            y: anchor.y + (centre.y - anchor.y) * m
        )
    }

    /// How far either side of the pointer the ring is still inside the
    /// container, in degrees, once magnified about the pointer.
    ///
    /// Both container edges bind: the sides cut the band off first at deep
    /// magnification, the top does at shallow. `180` means the whole ring is
    /// still on screen, which is the 1× rest state.
    public static func magnifyVisibleHalfAngle(
        radius: CGFloat,
        factor: Double,
        viewport: CGSize
    ) -> Double {
        let magnified = Double(magnifiedRadius(radius, factor: factor))
        guard magnified > 0, viewport.width > 0, viewport.height > 0 else { return 180 }
        let centre = carouselCentre(in: viewport)
        // Sideways: the point is |m·R·sin φ| from the pointer horizontally.
        let sideways = Double(viewport.width) / 2 / magnified
        let sidewaysLimit = sideways >= 1 ? 180 : asin(sideways) * 180 / .pi
        // Upward: it climbs m·R·(1 − cos φ) from the pointer toward the top.
        let headroom = (Double(centre.y) + Double(radius)) / magnified
        let upwardLimit = headroom >= 2 ? 180 : acos(1 - headroom) * 180 / .pi
        return max(0, min(180, min(sidewaysLimit, upwardLimit)))
    }

    /// The arc of the ring still on screen, as an angular span around the
    /// pointer.
    public static func magnifyVisibleWindow(
        radius: CGFloat,
        factor: Double,
        viewport: CGSize
    ) -> (start: Double, end: Double) {
        let half = magnifyVisibleHalfAngle(radius: radius, factor: factor, viewport: viewport)
        return (bottomAngle - half, bottomAngle + half)
    }

    /// The angle a label for `start...end` should sit at, clipped to the part
    /// of the span that is actually on screen — or `nil` when none of it is.
    ///
    /// Taking the raw midpoint is the bug this exists to stop: a wedge with a
    /// sliver on screen has its midpoint most of a turn away, so the label is
    /// drawn far outside the window while every visibility check, which does
    /// clip, still says the wedge is showing. Clip first, then take the middle.
    public static func clippedSpanMidAngle(
        start: Double,
        end: Double,
        window: (start: Double, end: Double)
    ) -> Double? {
        guard let visible = clippedSpan(start: start, end: end, window: window) else { return nil }
        return (visible.low + visible.high) / 2
    }

    /// How many degrees of `start...end` are actually on screen — the same
    /// clipped arc `clippedSpanMidAngle` centres a label on, so a label's
    /// room and its position can never disagree about what is visible.
    public static func clippedSpanVisibleWidth(
        start: Double,
        end: Double,
        window: (start: Double, end: Double)
    ) -> Double? {
        guard let visible = clippedSpan(start: start, end: end, window: window) else { return nil }
        return visible.high - visible.low
    }

    private static func clippedSpan(
        start: Double,
        end: Double,
        window: (start: Double, end: Double)
    ) -> (low: Double, high: Double)? {
        guard end > start, window.end > window.start else { return nil }
        // Spans are laid anticlockwise from the pointer and can run a whole
        // turn away from it, so bring the span onto the window's turn before
        // comparing — otherwise the block nearest the pointer looks furthest.
        let windowCentre = (window.start + window.end) / 2
        let spanCentre = (start + end) / 2
        let turns = ((windowCentre - spanCentre) / 360).rounded()
        let shiftedStart = start + turns * 360
        let shiftedEnd = end + turns * 360
        let low = max(shiftedStart, window.start)
        let high = min(shiftedEnd, window.end)
        guard high > low else { return nil }
        return (low, high)
    }

    /// The narrowest span the FREE caption is drawn on, in the wheel's own
    /// degrees. Under the close-up a base degree covers `factor` times the
    /// screen arc it does at rest, so the caption fits on proportionally
    /// narrower spans the deeper the founder leans in.
    public static func minimumFreeLabelSpanDegrees(factor: Double) -> Double {
        18 / clampMagnify(factor)
    }

    // MARK: - Pointer and separators

    /// The pointer tip extends this far beyond the ring's outer edge. Keeping
    /// the value in geometry keeps the marker and its hit-safe reserve aligned
    /// across every zoom level.
    public static let pointerMarkerOffset: CGFloat = 15

    /// The visual separator between adjacent task wedges. It belongs with the
    /// spans so every dial variant uses one angular gap policy.
    public static func wedgeGap(itemCount: Int) -> Double {
        itemCount > 1 ? 1.6 : 0
    }

    // MARK: - All-mode overview ring
    //
    // The mock's `All` view is a small, fully-closed 360° ring: every queued
    // task gets one wedge, sized to its own share of total duration, rather
    // than the equal per-slot sweep the closer views use. Fixed at
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
    /// the active wedge — the same "next enters from the right" rule the
    /// closer views follow, with every task given a slice at once.
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

    // MARK: - Neighbour labels

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
