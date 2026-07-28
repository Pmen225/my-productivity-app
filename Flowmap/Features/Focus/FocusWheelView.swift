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

/// A task on the wheel, resolved for drawing.
struct WheelItem: Identifiable {
    let id: UUID
    let title: String
    let iconName: String
    let colour: ColourToken
    let minutes: Int
    let isActive: Bool
}

/// The focus dial: a shallow bowl, not a full ring.
///
/// The active task fills the dominant wedge at the bottom, under a fixed clay
/// pointer. Upcoming tasks fan up the right side as thinner wedges — the same
/// "next enters from the right" rule the wheel has always used, just folded
/// into an arc instead of a closed circle. A numbered ruler along the active
/// wedge's own span reads its duration in minutes.
struct FocusWheelView: View {
    @Environment(\.colorScheme) private var scheme

    let items: [WheelItem]
    /// 0...1 through the active task. Reserved for a future progress mark;
    /// the dial itself reads duration from the ruler, not a filled arc.
    let progress: Double
    /// Identity of the active task, so wedge fills can cross-fade when it changes.
    let activeID: UUID?

    private var neighbourCount: Int { max(0, items.count - 1) }

    var body: some View {
        GeometryReader { proxy in
            let halfWidth = proxy.size.width / 2
            let depth = max(1, proxy.size.height - FocusWheelGeometry.pointerInset)
            let halfAngle = FocusWheelGeometry.dialHalfAngle(depth: depth, halfWidth: halfWidth)
            let radius = FocusWheelGeometry.dialRadius(halfWidth: halfWidth, halfAngle: halfAngle)
            let centre = CGPoint(
                x: proxy.size.width / 2,
                y: proxy.size.height - FocusWheelGeometry.pointerInset - radius
            )
            let thickness = FocusWheelGeometry.dialThickness(for: proxy.size.width)

            ZStack {
                wedges(centre: centre, radius: radius, thickness: thickness, halfAngle: halfAngle)
                ruler(centre: centre, radius: radius, thickness: thickness, halfAngle: halfAngle)
                pointer(centre: centre, radius: radius)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus wheel")
    }

    // MARK: - Wedges

    private func wedges(centre: CGPoint, radius: CGFloat, thickness: CGFloat, halfAngle: Double) -> some View {
        // Small angular gap between wedges reads as the mock's double rim
        // between segments rather than one continuous band.
        let gap = items.count > 1 ? 1.6 : 0.0

        return ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            let span = index == 0
                ? FocusWheelGeometry.dialActiveSpan(halfAngle: halfAngle)
                : FocusWheelGeometry.dialNeighbourSpan(index: index, neighbourCount: neighbourCount, halfAngle: halfAngle)
            let wedgeThickness = index == 0 ? thickness * 1.3 : thickness

            ZStack {
                WheelWedgeShape(
                    startAngle: span.start + gap,
                    endAngle: span.end - gap,
                    thickness: wedgeThickness,
                    radius: radius,
                    centre: centre
                )
                .fill(item.isActive ? item.colour.softStrong : item.colour.soft)
                .overlay(
                    WheelWedgeShape(
                        startAngle: span.start + gap,
                        endAngle: span.end - gap,
                        thickness: wedgeThickness,
                        radius: radius,
                        centre: centre
                    )
                    .stroke(FlowTheme.separatorStrong(scheme), lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.3), value: item.id)

                if index > 0 {
                    neighbourLabel(item: item, span: span, centre: centre, radius: radius, thickness: wedgeThickness)
                }
            }
        }
    }

    /// Icon, name and compact duration stacked at a neighbour wedge's outer edge.
    private func neighbourLabel(
        item: WheelItem,
        span: (start: Double, end: Double),
        centre: CGPoint,
        radius: CGFloat,
        thickness: CGFloat
    ) -> some View {
        let midAngle = (span.start + span.end) / 2
        let position = FocusWheelGeometry.point(centre: centre, radius: radius - thickness / 2, angle: midAngle)
        let rotation = FocusWheelGeometry.readableRotation(atAngle: midAngle)

        return VStack(spacing: 1) {
            Image(systemName: item.iconName)
                .font(.system(size: 11, weight: .semibold))
            Text(item.title)
                .font(FlowFont.wheelSegment)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(DurationFormatter.compact(minutes: item.minutes))
                .font(FlowFont.durationChip)
                .opacity(0.85)
        }
        .foregroundStyle(item.colour.onSoft)
        .frame(maxWidth: max(56, thickness * 1.6))
        .rotationEffect(.degrees(rotation))
        .position(x: position.x, y: position.y)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next: \(item.title), \(DurationFormatter.spoken(minutes: item.minutes))")
    }

    // MARK: - Ruler

    /// A numbered minute scale across the active task's own span: minor
    /// hairlines every minute, major ticks with a number every `majorStep`.
    private func ruler(centre: CGPoint, radius: CGFloat, thickness: CGFloat, halfAngle: Double) -> some View {
        let totalMinutes = min(180, max(1, items.first?.minutes ?? 30))
        let majorStep = totalMinutes <= 30 ? 5 : (totalMinutes <= 60 ? 10 : 15)
        let outer = radius + thickness * 1.3 / 2

        return ZStack {
            ForEach(Array(stride(from: 0, through: totalMinutes, by: 1)), id: \.self) { minute in
                let angle = FocusWheelGeometry.dialTickAngle(minute: minute, totalMinutes: totalMinutes, halfAngle: halfAngle)
                let isMajor = minute % majorStep == 0
                tick(angle: angle, centre: centre, outer: outer, isMajor: isMajor)

                if isMajor {
                    let labelPoint = FocusWheelGeometry.point(centre: centre, radius: outer + 13, angle: angle)
                    Text("\(minute)")
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
        let from = FocusWheelGeometry.point(centre: centre, radius: outer, angle: angle)
        let to = FocusWheelGeometry.point(centre: centre, radius: outer + length, angle: angle)
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
        let tip = FocusWheelGeometry.point(centre: centre, radius: radius + 15, angle: FocusWheelGeometry.bottomAngle)
        return PointerTriangle()
            .fill(FlowTheme.accent)
            .frame(width: 16, height: 11)
            .position(x: tip.x, y: tip.y - 5.5)
            .accessibilityHidden(true)
    }
}
