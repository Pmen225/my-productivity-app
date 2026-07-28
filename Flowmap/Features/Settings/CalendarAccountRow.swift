import SwiftUI

/// Shared chrome for one calendar account in Settings: name, connection tick
/// (or a quiet "Not connected"), the signed-in label when there is one, and
/// any inline error. Account-specific controls — connect/disconnect, the
/// Google client id field, the calendar checklist — are supplied by the
/// caller, since Apple and Google need different content but the same frame.
struct CalendarAccountRow<Content: View>: View {
    @Environment(\.colorScheme) private var scheme

    private let kind: CalendarAccountKind
    private let connection: CalendarConnection
    private let content: () -> Content

    init(
        kind: CalendarAccountKind,
        connection: CalendarConnection,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.kind = kind
        self.connection = connection
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.m) {
            HStack(spacing: FlowSpacing.s) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                    Text(kind.displayName)
                        .font(FlowFont.cardTitle)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                    if connection.isConnected, let accountLabel = connection.accountLabel {
                        Text(accountLabel)
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                    } else if !connection.isConnected {
                        Text("Not connected")
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.tertiaryText(scheme))
                    }
                }

                Spacer(minLength: FlowSpacing.s)

                if connection.isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(FlowTheme.accent)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                connection.isConnected
                    ? "\(kind.displayName), connected\(connection.accountLabel.map { ", \($0)" } ?? "")"
                    : "\(kind.displayName), not connected"
            )

            if let lastError = connection.lastError {
                Text(lastError)
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .padding(FlowSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .fill(FlowTheme.surfaceSunken(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .strokeBorder(FlowTheme.separator(scheme), lineWidth: 1)
        )
    }
}
