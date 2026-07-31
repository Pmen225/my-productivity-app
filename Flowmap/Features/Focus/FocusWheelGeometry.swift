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
    public static let dialActiveFraction: Double = 0.56

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
