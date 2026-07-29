import SwiftUI

/// The mock's `cWheelRow` duration picker: a sunken well holding one value at a
/// time, flanked by step chevrons, scroll-snapping between the eight offered
/// lengths.
///
/// Shared on purpose — the create sheet and the Plan page both pick a duration
/// this way, and decision 7 settles that it is a wheel rather than the chips
/// this replaced.
public struct FlowDurationWheel: View {
    /// The mock's eight options, in order.
    public static let defaultOptions = [15, 20, 25, 30, 45, 60, 90, 120]

    @Environment(\.colorScheme) private var scheme

    @Binding private var minutes: Int
    private let options: [Int]
    @State private var scrolled: Int?

    public init(minutes: Binding<Int>, options: [Int] = FlowDurationWheel.defaultOptions) {
        self._minutes = minutes
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 0) {
            chevron("chevron.left", by: -1)
            wheel
            chevron("chevron.right", by: 1)
        }
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.field, style: .continuous)
                .fill(FlowTheme.surfaceSunken(scheme))
        )
        // One adjustable control to VoiceOver rather than a scroll view and two
        // buttons, which is what the rotor expects of a picker.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Duration")
        .accessibilityValue(DurationFormatter.spoken(minutes: minutes))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: minutes = Self.stepped(from: minutes, by: 1, in: options)
            case .decrement: minutes = Self.stepped(from: minutes, by: -1, in: options)
            default: break
            }
        }
    }

    private var wheel: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(options, id: \.self) { value in
                    Text(DurationFormatter.compact(minutes: value))
                        .font(FlowFont.durationChip)
                        .foregroundStyle(FlowTheme.accent)
                        .containerRelativeFrame(.horizontal)
                        .id(value)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolled)
        // HIG minimum tappable height, and the well the mock draws.
        .frame(height: 44)
        // Snapped, not assigned: a stored duration that is not one of the
        // options — a default of 35, say — matches no row, so the wheel would
        // open showing nothing at all.
        .onAppear {
            let snapped = Self.stepped(from: minutes, by: 0, in: options)
            if snapped != minutes { minutes = snapped }
            scrolled = snapped
        }
        .onChange(of: scrolled) { _, new in
            if let new, new != minutes { minutes = new }
        }
        .onChange(of: minutes) { _, new in
            if scrolled != new { scrolled = new }
        }
    }

    private func chevron(_ systemImage: String, by delta: Int) -> some View {
        Button {
            minutes = Self.stepped(from: minutes, by: delta, in: options)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    /// The next option along, clamped at both ends. A value that is not one of
    /// the options — a task saved before the set changed — snaps to the nearest
    /// one first rather than jumping to the start.
    public static func stepped(from minutes: Int, by delta: Int, in options: [Int]) -> Int {
        guard !options.isEmpty else { return minutes }
        let current = options.firstIndex(of: minutes)
            ?? options.indices.min(by: { abs(options[$0] - minutes) < abs(options[$1] - minutes) })
            ?? 0
        return options[min(options.count - 1, max(0, current + delta))]
    }
}
