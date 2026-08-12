import SwiftUI

// MARK: - Duration chip

/// The compact `30M` / `1H 30M` label. Always present wherever a duration is.
public struct DurationChip: View {
    @Environment(\.colorScheme) private var scheme
    private let minutes: Int
    private let tint: ColourToken?

    public init(minutes: Int, tint: ColourToken? = nil) {
        self.minutes = minutes
        self.tint = tint
    }

    public var body: some View {
        Text(DurationFormatter.compact(minutes: minutes))
            .font(FlowFont.durationChip)
            .foregroundStyle(tint?.onSoft ?? FlowTheme.secondaryText(scheme))
            .padding(.horizontal, FlowSpacing.s)
            .padding(.vertical, FlowSpacing.xxs)
            .background(
                Capsule().fill(tint?.soft ?? FlowTheme.separator(scheme).opacity(0.6))
            )
            .accessibilityLabel(DurationFormatter.spoken(minutes: minutes))
    }
}

// MARK: - Section header

/// `PROJECTS (0)` style header with a compact `+` beside it.
///
/// Deliberately *not* a full-width add row — creation inputs appear only after
/// pressing the compact control.
public struct CompactSectionHeader: View {
    @Environment(\.colorScheme) private var scheme
    private let title: String
    private let count: Int?
    private let addLabel: String?
    private let onAdd: (() -> Void)?

    public init(title: String, count: Int? = nil, addLabel: String? = nil, onAdd: (() -> Void)? = nil) {
        self.title = title
        self.count = count
        self.addLabel = addLabel
        self.onAdd = onAdd
    }

    public var body: some View {
        HStack(spacing: FlowSpacing.s) {
            Text(count.map { "\(title.uppercased()) (\($0))" } ?? title.uppercased())
                .font(FlowFont.caption.weight(.semibold))
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .tracking(0.6)

            Spacer(minLength: FlowSpacing.s)

            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .regular))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(FlowTheme.separator(scheme).opacity(0.7)))
                        .flowHitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(addLabel ?? "Add \(title)")
            }
        }
    }
}

// MARK: - Cards

/// The standard raised surface: soft radius, one-pixel border, restrained shadow.
public struct FlowCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    private let padding: CGFloat
    private let radius: CGFloat
    private let content: Content

    public init(
        padding: CGFloat = FlowSpacing.l,
        radius: CGFloat = FlowRadius.medium,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.radius = radius
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(FlowTheme.surface(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(FlowTheme.separator(scheme), lineWidth: 1)
            )
            .shadow(color: FlowTheme.shadow(scheme), radius: 8, y: 2)
    }
}

// MARK: - Primary action

/// The single dominant button on a screen. There is never more than one.
public struct PrimaryActionButton: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    private let title: String
    private let systemImage: String?
    private let tint: Color
    private let action: () -> Void

    /// `tint` exists for the one destructive case — the delete card — and is
    /// the accent everywhere else.
    public init(
        _ title: String,
        systemImage: String? = nil,
        tint: Color = FlowTheme.accentFill,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: FlowSpacing.s) {
                if let systemImage {
                    Image(systemName: systemImage).font(FlowFont.cardTitle)
                }
                Text(title).font(FlowFont.cardTitle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, FlowSpacing.m)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                    .fill(tint.opacity(isEnabled ? 1 : 0.4))
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

/// Quieter sibling for reversible secondary actions.
public struct SecondaryActionButton: View {
    @Environment(\.colorScheme) private var scheme
    private let title: String
    private let systemImage: String?
    private let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: FlowSpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage).font(FlowFont.secondary)
                }
                Text(title).font(FlowFont.secondary)
            }
            .padding(.horizontal, FlowSpacing.m)
            .padding(.vertical, FlowSpacing.s)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                    .fill(FlowTheme.separator(scheme).opacity(0.6))
            )
            .foregroundStyle(FlowTheme.primaryText(scheme))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty state

/// Useful but short. Never a permanent full-width add row.
public struct FlowEmptyState: View {
    @Environment(\.colorScheme) private var scheme
    private let symbol: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(
        symbol: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: FlowSpacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(FlowTheme.secondaryText(scheme).opacity(0.7))
            Text(title)
                .font(FlowFont.cardTitle)
                .foregroundStyle(FlowTheme.primaryText(scheme))
            Text(message)
                .font(FlowFont.secondary)
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                SecondaryActionButton(actionTitle, systemImage: "plus", action: action)
                    .padding(.top, FlowSpacing.xs)
            }
        }
        .frame(maxWidth: 320)
        .padding(.vertical, FlowSpacing.xxl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Status dot

/// Status is never conveyed by colour alone — the symbol carries it too.
public struct StatusIndicator: View {
    private let token: ColourToken
    private let symbolName: String
    private let label: String

    public init(token: ColourToken, symbolName: String, label: String) {
        self.token = token
        self.symbolName = symbolName
        self.label = label
    }

    public var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(token.onSoft)
            .frame(width: 20, height: 20)
            .background(Circle().fill(token.soft))
            .accessibilityLabel(label)
    }
}

// MARK: - Banner

/// Non-blocking notice used for requeues and undo. Never a modal question.
public struct FlowBanner: View {
    @Environment(\.colorScheme) private var scheme
    private let text: String
    private let actions: [(title: String, handler: () -> Void)]
    private let onDismiss: () -> Void

    public init(
        text: String,
        actions: [(title: String, handler: () -> Void)] = [],
        onDismiss: @escaping () -> Void
    ) {
        self.text = text
        self.actions = actions
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            HStack(alignment: .top, spacing: FlowSpacing.s) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FlowTheme.accent)
                    .padding(.top, 2)
                Text(text)
                    .font(FlowFont.secondary)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: FlowSpacing.s)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            if !actions.isEmpty {
                HStack(spacing: FlowSpacing.s) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        Button(action.title, action: action.handler)
                            .font(FlowFont.caption.weight(.semibold))
                            .buttonStyle(.plain)
                            // Clay AS text needs the deeper value: the fill clay
                            // reads at only 3.66:1 on a light card.
                            .foregroundStyle(FlowTheme.accentText(scheme))
                            .flowHitTarget()
                    }
                }
            }
        }
        .padding(FlowSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                .fill(FlowTheme.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                .strokeBorder(FlowTheme.separator(scheme), lineWidth: 1)
        )
        .shadow(color: FlowTheme.shadow(scheme), radius: 12, y: 4)
    }
}

// MARK: - Icon picker source

/// A small, curated symbol set. Enough choice to be expressive, short enough to scan.
public enum FlowSymbols {
    public static let taskSymbols = [
        "circle", "book", "figure.run", "cup.and.saucer", "calendar",
        "graduationcap", "target", "hammer", "envelope", "phone",
        "cart", "heart", "leaf", "lightbulb", "music.note",
        "paintbrush", "pencil", "wrench.and.screwdriver", "airplane", "house",
    ]

    public static let listSymbols = [
        "list.bullet", "tray", "star", "flag", "bookmark",
        "folder", "archivebox", "briefcase", "person.2", "sparkles",
    ]
}
