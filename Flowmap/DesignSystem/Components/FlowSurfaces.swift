import SwiftUI

// MARK: - Eyebrow

/// The small uppercase label that names a region without taking a heading's
/// weight — `NOW`, `TODAY`, `SUBTASKS`. Distinct from `CompactSectionHeader`,
/// which owns a count and an add control; this one is pure labelling.
public struct FlowEyebrow: View {
    @Environment(\.colorScheme) private var scheme
    private let text: String
    private let tint: Color?

    public init(_ text: String, tint: Color? = nil) {
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        Text(text.uppercased())
            .font(FlowFont.eyebrow)
            .tracking(1.5)
            .foregroundStyle(tint ?? FlowTheme.tertiaryText(scheme))
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Glass

/// Floating controls sit on glass so the content behind them stays legible as
/// it scrolls past — the tab bar, the wheel's zoom chips, the map's control bar.
public struct GlassBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    private let radius: CGFloat

    public init(radius: CGFloat = FlowRadius.large) {
        self.radius = radius
    }

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(FlowTheme.glass(scheme))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(FlowTheme.glassBorder(scheme), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: FlowTheme.shadow(scheme), radius: 12, y: 6)
    }
}

extension View {
    /// See `GlassBackground`.
    public func flowGlass(radius: CGFloat = FlowRadius.large) -> some View {
        modifier(GlassBackground(radius: radius))
    }
}

// MARK: - Hit target

extension View {
    /// Guarantees Apple's 44×44pt minimum touch target without changing what is
    /// drawn.
    ///
    /// The design's controls are 38 and 42pt circles. Scaling them up would lose
    /// the look; leaving them at 38pt would lose the thumb. So the artwork stays
    /// its own size and only the tappable area grows around it.
    public func flowHitTarget(_ size: CGFloat = FlowControlSize.minimumTouch) -> some View {
        frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }
}

// MARK: - Statistic tile

/// One figure and its label. Tiles are always used in a row of two or three —
/// a single tile is a sentence, not a tile.
public struct StatTile: View {
    @Environment(\.colorScheme) private var scheme
    private let value: String
    private let label: String
    private let tint: Color?

    public init(value: String, label: String, tint: Color? = nil) {
        self.value = value
        self.label = label
        self.tint = tint
    }

    public var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(FlowFont.statNumber)
                .foregroundStyle(tint ?? FlowTheme.primaryText(scheme))
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FlowSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .fill(FlowTheme.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .strokeBorder(FlowTheme.separator(scheme), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Now strip

/// The live task, wherever the live task is not already the whole screen:
/// what is running, how long is left, and the two controls that matter.
///
/// Presentational by design — the caller reads `FocusEngine` and passes the
/// result down, so the strip can be shown in Today, on the map pane, and in a
/// preview without three different sources of truth.
public struct NowStrip: View {
    @Environment(\.colorScheme) private var scheme

    private let title: String
    private let countdown: String
    private let endsLabel: String
    private let progress: Double
    private let tint: ColourToken
    private let isPaused: Bool
    private let onTogglePause: () -> Void
    private let onComplete: () -> Void
    private let onOpen: (() -> Void)?

    public init(
        title: String,
        countdown: String,
        endsLabel: String,
        progress: Double,
        tint: ColourToken,
        isPaused: Bool,
        onTogglePause: @escaping () -> Void,
        onComplete: @escaping () -> Void,
        onOpen: (() -> Void)? = nil
    ) {
        self.title = title
        self.countdown = countdown
        self.endsLabel = endsLabel
        self.progress = progress
        self.tint = tint
        self.isPaused = isPaused
        self.onTogglePause = onTogglePause
        self.onComplete = onComplete
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            HStack {
                FlowEyebrow("Now", tint: FlowTheme.accentDeep)
                Spacer(minLength: FlowSpacing.s)
                Text(endsLabel)
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }

            Text(title)
                .font(FlowFont.sectionTitle)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .lineLimit(2)

            Text(countdown)
                .font(FlowFont.countdown)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .accessibilityLabel("\(countdown) remaining")

            ProgressView(value: progress.isFinite ? min(max(progress, 0), 1) : 0)
                .progressViewStyle(.linear)
                .tint(FlowTheme.accent)
                .padding(.top, FlowSpacing.xs)

            HStack(spacing: FlowSpacing.s) {
                Button(action: onTogglePause) {
                    Label(
                        isPaused ? "Resume" : "Pause",
                        systemImage: isPaused ? "play.fill" : "pause.fill"
                    )
                    .font(FlowFont.secondary.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FlowSpacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                            .fill(FlowTheme.accentFill)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button(action: onComplete) {
                    Label("Done", systemImage: "checkmark")
                        .font(FlowFont.secondary.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FlowSpacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                                .fill(FlowTheme.surface(scheme).opacity(0.85))
                        )
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, FlowSpacing.xs)
        }
        .padding(FlowSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.large, style: .continuous)
                .fill(tint.soft)
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
    }
}
