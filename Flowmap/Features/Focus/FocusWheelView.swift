import SwiftUI

/// One arc of the ring.
struct WheelSegmentShape: Shape {
    var startAngle: Double
    var endAngle: Double
    var thickness: CGFloat

    /// Lets the whole ring animate as one rigid body during a task change.
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startAngle, endAngle) }
        set {
            startAngle = newValue.first
            endAngle = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = max(0, outer - thickness)

        var path = Path()
        path.addArc(
            center: centre,
            radius: outer,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(endAngle),
            clockwise: false
        )
        path.addArc(
            center: centre,
            radius: inner,
            startAngle: .degrees(endAngle),
            endAngle: .degrees(startAngle),
            clockwise: true
        )
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

/// The focus ring.
///
/// The active task sits at the bottom under a fixed pointer. Progress inside the
/// active task is drawn as an arc along its own segment; the ring itself turns
/// clockwise by exactly one segment when the task changes, which is what carries
/// the next task down the right-hand side into the bottom slot.
struct FocusWheelView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let items: [WheelItem]
    /// 0...1 through the active task.
    let progress: Double
    /// Identity of the active task, so a change can drive the rotation.
    let activeID: UUID?

    @State private var rotationOffset: Double = 0

    private var visibleCount: Int { max(1, items.count) }
    private var sweep: Double { FocusWheelGeometry.sweep(visibleCount: visibleCount) }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let thickness = FocusWheelGeometry.ringThickness(for: size)
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let outerRadius = size / 2
            let labelRadius = outerRadius - thickness / 2

            ZStack {
                track(thickness: thickness, size: size)

                // Nodes and their labels live in one rotated space, so a label can
                // never drift away from the arc it belongs to.
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let span = FocusWheelGeometry.span(index: index, visibleCount: visibleCount)

                    WheelSegmentShape(
                        startAngle: span.start + rotationOffset,
                        endAngle: span.end + rotationOffset,
                        thickness: thickness
                    )
                    .fill(item.isActive ? item.colour.softStrong : item.colour.soft)
                    .overlay(
                        WheelSegmentShape(
                            startAngle: span.start + rotationOffset,
                            endAngle: span.end + rotationOffset,
                            thickness: thickness
                        )
                        .stroke(FlowTheme.background(scheme), lineWidth: 2)
                    )

                    if item.isActive {
                        progressArc(span: span, thickness: thickness, colour: item.colour)
                    }

                    segmentLabel(
                        item: item,
                        index: index,
                        centre: centre,
                        radius: labelRadius,
                        thickness: thickness
                    )
                }

                pointer(centre: centre, outerRadius: outerRadius, thickness: thickness)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus wheel")
        .onChange(of: activeID) { _, _ in
            advanceWheel()
        }
    }

    // MARK: - Pieces

    private func track(thickness: CGFloat, size: CGFloat) -> some View {
        Circle()
            .strokeBorder(FlowTheme.surfaceSunken(scheme), lineWidth: thickness)
            .frame(width: size, height: size)
    }

    /// A thin arc that fills clockwise through the active segment as time passes.
    private func progressArc(span: (start: Double, end: Double), thickness: CGFloat, colour: ColourToken) -> some View {
        let travelled = (span.end - span.start) * min(1, max(0, progress))
        return WheelSegmentShape(
            startAngle: span.start + rotationOffset,
            endAngle: span.start + rotationOffset + travelled,
            thickness: thickness * 0.18
        )
        .fill(colour.base.opacity(0.85))
        .allowsHitTesting(false)
    }

    /// Icon, title and compact duration written *inside* the ring segment.
    private func segmentLabel(
        item: WheelItem,
        index: Int,
        centre: CGPoint,
        radius: CGFloat,
        thickness: CGFloat
    ) -> some View {
        let angle = FocusWheelGeometry.centreAngle(index: index, visibleCount: visibleCount) + rotationOffset
        let position = FocusWheelGeometry.point(centre: centre, radius: radius, angle: angle)
        let rotation = angle - FocusWheelGeometry.bottomAngle

        return VStack(spacing: 1) {
            HStack(spacing: 3) {
                if !item.iconName.isEmpty {
                    Image(systemName: item.iconName)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(item.title)
                    .font(FlowFont.wheelSegment)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text(DurationFormatter.compact(minutes: item.minutes))
                .font(FlowFont.durationChip)
                .opacity(0.85)
        }
        .foregroundStyle(item.colour.onSoft)
        // Keep the label comfortably inside the ring band so it can never clip.
        .frame(maxWidth: max(60, thickness * 2.4))
        .rotationEffect(.degrees(rotation))
        .position(x: position.x, y: position.y)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.isActive ? "Now: " : "")\(item.title), \(DurationFormatter.spoken(minutes: item.minutes))"
        )
    }

    /// Fixed marker at the bottom. It never moves — the ring moves beneath it.
    private func pointer(centre: CGPoint, outerRadius: CGFloat, thickness: CGFloat) -> some View {
        let tip = FocusWheelGeometry.point(
            centre: centre,
            radius: outerRadius + 2,
            angle: FocusWheelGeometry.bottomAngle
        )
        return Capsule()
            .fill(FlowTheme.primaryText(scheme))
            .frame(width: 3, height: thickness + 12)
            .position(x: tip.x, y: tip.y - (thickness + 12) / 2 + 6)
            .accessibilityHidden(true)
    }

    // MARK: - Transition

    /// Turns the ring one segment clockwise as the next task arrives.
    ///
    /// Reduced Motion gets the same information as a discrete update instead of
    /// a continuous sweep.
    private func advanceWheel() {
        guard !reduceMotion else {
            rotationOffset = 0
            return
        }
        // Start one segment back, then animate forward: increasing angle is clockwise.
        rotationOffset = -sweep
        withAnimation(.easeInOut(duration: 1.1)) {
            rotationOffset = 0
        }
    }
}
