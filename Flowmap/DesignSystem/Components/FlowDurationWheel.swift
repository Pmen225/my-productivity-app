import SwiftUI

/// The duration picker: a sunken well holding a spinning wheel of minute
/// values, scrolled to the one being committed to.
///
/// Shared on purpose — the create sheet and the Plan page both pick a duration
/// this way, and decision 7 settles that it is a wheel rather than the chips
/// this replaced.
///
/// A vertical wheel, not the chevron stepper this replaced: stepping one option
/// per tap made choosing an hour a run of taps, and the founder asked for the
/// scrolling picker directly ("that scrolly thing to choose mins, not a button
/// to press for the next minute").
public struct FlowDurationWheel: View {
    /// Five-minute steps up to two hours. Fine enough that the value people
    /// actually mean is on the wheel, coarse enough to spin through.
    public static let defaultOptions = Array(stride(from: 5, through: 120, by: 5))

    @Environment(\.colorScheme) private var scheme

    @Binding private var minutes: Int
    private let options: [Int]
    private let accessibilityLabel: String
    @State private var scrolled: Int?

    /// `accessibilityLabel` defaults to "Duration" for existing callers; the
    /// fused task card overrides it to "Worth" so VoiceOver matches the
    /// worth-framed copy above the control (wheel-philosophy.md, scoped to
    /// that card only — every other caller is unaffected).
    public init(
        minutes: Binding<Int>,
        options: [Int] = FlowDurationWheel.defaultOptions,
        accessibilityLabel: String = "Duration"
    ) {
        self._minutes = minutes
        self.options = options
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        Picker(accessibilityLabel, selection: $minutes) {
            ForEach(options, id: \.self) { value in
                Text(Self.label(for: value))
                    .font(FlowFont.durationChip)
                    .foregroundStyle(FlowTheme.accent)
                    .tag(value)
            }
        }
        .labelsHidden()
        #if os(iOS)
        .pickerStyle(.wheel)
        // Two rows of context either side of the choice: enough to see where a
        // spin is heading, without the well swallowing the sheet.
        .frame(height: 132)
        #else
        // macOS has no wheel style; a menu is the native equivalent there.
        .pickerStyle(.menu)
        #endif
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.field, style: .continuous)
                .fill(FlowTheme.surfaceSunken(scheme))
        )
        .accessibilityLabel(accessibilityLabel)
        // Snapped, not assigned: a stored duration that is not one of the
        // options — a task saved before the set changed — matches no row, so
        // the wheel would open showing nothing at all.
        .onAppear {
            let snapped = Self.stepped(from: minutes, by: 0, in: options)
            if snapped != minutes { minutes = snapped }
        }
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

    public static func label(for minutes: Int) -> String {
        "\(minutes) min"
    }
}
