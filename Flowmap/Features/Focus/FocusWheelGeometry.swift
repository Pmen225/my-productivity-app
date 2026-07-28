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
    // The mock's dial is a shallow bowl cut from a much larger circle, not a
    // full ring: the active task sits centred at the bottom under a fixed
    // pointer exactly as above, and upcoming tasks fan up the right-hand side
    // as thinner wedges — the same "next enters from the right" rule, folded
    // into an arc instead of a closed circle.

    /// Clearance kept between the dial's lowest point and the pointer beneath it.
    public static let pointerInset: CGFloat = 14

    /// Fraction of the dial's total sweep the active wedge occupies; the rest
    /// fans out to whatever upcoming neighbours are shown.
    public static let dialActiveFraction: Double = 0.56

    /// Half the dial's total visible sweep, solved so the bowl reaches the
    /// full width of its container (`halfWidth`) at a chosen, shallow `depth`:
    /// `depth = halfWidth · tan(halfAngle / 2)`.
    public static func dialHalfAngle(depth: CGFloat, halfWidth: CGFloat) -> Double {
        guard halfWidth > 0 else { return 0 }
        return 2 * Double(atan(depth / halfWidth)) * 180 / .pi
    }

    /// Radius of the circle the visible bowl is cut from.
    public static func dialRadius(halfWidth: CGFloat, halfAngle: Double) -> CGFloat {
        let radians = halfAngle * .pi / 180
        guard halfAngle > 0, sin(radians) > 0 else { return halfWidth }
        return halfWidth / CGFloat(sin(radians))
    }

    /// Ring thickness for the dial, given its width.
    public static func dialThickness(for width: CGFloat) -> CGFloat {
        max(46, min(64, width * 0.16))
    }

    /// Angular span of the active wedge, centred at `bottomAngle`.
    public static func dialActiveSpan(halfAngle: Double) -> (start: Double, end: Double) {
        let half = halfAngle * dialActiveFraction
        return (bottomAngle - half, bottomAngle + half)
    }

    /// Angular span of the upcoming neighbour at `index` (`1` is the very next
    /// task), fanning further right beyond the active wedge, one slice per
    /// neighbour shown.
    public static func dialNeighbourSpan(
        index: Int,
        neighbourCount: Int,
        halfAngle: Double
    ) -> (start: Double, end: Double) {
        let active = dialActiveSpan(halfAngle: halfAngle)
        guard neighbourCount > 0 else { return (active.start, active.start) }
        let remaining = halfAngle * (1 - dialActiveFraction)
        let each = remaining / Double(neighbourCount)
        let start = active.start - each * Double(index)
        return (start, start + each)
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
}
