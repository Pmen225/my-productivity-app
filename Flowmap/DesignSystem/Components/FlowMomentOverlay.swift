import SwiftUI

/// Renders whatever `FlowMomentService` is currently saying, over the whole
/// shell. Attached once per platform root — never per screen, or a moment
/// raised on one tab would vanish the instant the user moved to another.
///
/// Placement carries meaning: confirmations and milestones arrive at the top
/// where notifications do, a finished task lands as a band at the bottom near
/// the work it came from, and a rank crossing takes the middle because it is
/// the only one worth interrupting for.
public struct FlowMomentOverlay: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    private var moment: FlowMoment? { flow?.moments.current }

    public var body: some View {
        ZStack {
            if let moment {
                switch moment {
                case .hud(let text):
                    top { hudPill(text) }
                case .notif(let title, let subtitle):
                    top { notifBanner(title: title, subtitle: subtitle) }
                case .xp(let amount):
                    top { xpToast(amount) }
                case .rankUp(let level, let xp):
                    rankStamp(level: level, xp: xp)
                case .done(let title):
                    doneBand(title)
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: moment)
        // Nothing here is tappable: a moment must never swallow a tap meant
        // for the screen it is floating over.
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Placement

    private func top(@ViewBuilder _ content: () -> some View) -> some View {
        VStack {
            content()
                .padding(.top, FlowSpacing.s)
                .transition(.move(edge: .top).combined(with: .opacity))
            Spacer()
        }
        .padding(.horizontal, FlowSpacing.screen)
    }

    // MARK: - Moments

    /// Row 30: the mock's short dark pill — a confirmation (`Task added`) or a
    /// refusal (`No free slots left today`) in the same shape.
    private func hudPill(_ text: String) -> some View {
        Text(text)
            .font(FlowFont.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, FlowSpacing.l)
            .padding(.vertical, FlowSpacing.s)
            .background(FlowTheme.popoverSurface, in: Capsule())
            .shadow(color: FlowTheme.shadow(scheme), radius: 10, y: 4)
    }

    /// Row 41: the wind-down banner — a coloured dot, a title, and the line
    /// telling the user what to do with the time left.
    private func notifBanner(title: String, subtitle: String) -> some View {
        HStack(spacing: FlowSpacing.m) {
            Circle()
                .fill(FlowTheme.accent)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                Text(title)
                    .font(FlowFont.cardTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                Text(subtitle)
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }
            Spacer(minLength: 0)
        }
        .padding(FlowSpacing.l)
        .flowGlass(radius: FlowRadius.medium)
    }

    /// Row 39: the XP a single award earned, in the accent so it reads as a
    /// gain rather than a notice.
    private func xpToast(_ amount: Int) -> some View {
        Text("+\(amount) XP")
            .font(FlowFont.durationChip)
            .tracking(1)
            .foregroundStyle(.white)
            .padding(.horizontal, FlowSpacing.l)
            .padding(.vertical, FlowSpacing.s)
            .background(FlowTheme.accentFill, in: Capsule())
            .shadow(color: FlowTheme.accentShadow, radius: 10, y: 4)
            .accessibilityLabel("Earned \(amount) XP")
    }

    /// Row 40: the skewed `RANK / UP` stamp with the new level in a ring.
    private func rankStamp(level: Int, xp: Int) -> some View {
        HStack(spacing: FlowSpacing.l) {
            VStack(alignment: .leading, spacing: -2) {
                Text("RANK")
                Text("UP")
            }
            .font(FlowFont.dialogTitle)
            .tracking(2)
            .foregroundStyle(.white)

            Text("\(level)")
                .font(FlowFont.statNumber)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(FlowTheme.accent, lineWidth: 2))
        }
        .padding(.horizontal, FlowSpacing.xl)
        .padding(.vertical, FlowSpacing.l)
        .background(FlowTheme.popoverSurface, in: RoundedRectangle(cornerRadius: FlowRadius.medium))
        .rotationEffect(.degrees(-4))
        .shadow(color: FlowTheme.shadow(scheme), radius: 20, y: 8)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
        .accessibilityLabel("Rank up. Level \(level), \(xp) XP earned.")
    }

    /// Row 42: the dark band a finished task earns, sat above the tab bar so
    /// it reads as a footer to the work rather than a modal.
    private func doneBand(_ title: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: FlowSpacing.m) {
                Text("COMPLETE")
                    .font(FlowFont.eyebrow)
                    .tracking(1.5)
                    .foregroundStyle(FlowTheme.accent)
                    .padding(.horizontal, FlowSpacing.s)
                    .padding(.vertical, FlowSpacing.xs)
                    .overlay(
                        RoundedRectangle(cornerRadius: FlowRadius.tile)
                            .strokeBorder(FlowTheme.accent, lineWidth: 1.5)
                    )
                Text("\(title) — every finish moves the goal")
                    .font(FlowFont.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(FlowSpacing.l)
            .background(FlowTheme.popoverSurface, in: RoundedRectangle(cornerRadius: FlowRadius.medium))
            .shadow(color: FlowTheme.shadow(scheme), radius: 16, y: 6)
            .padding(.horizontal, FlowSpacing.screen)
            .padding(.bottom, FlowSpacing.s)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
