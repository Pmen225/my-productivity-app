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
}
