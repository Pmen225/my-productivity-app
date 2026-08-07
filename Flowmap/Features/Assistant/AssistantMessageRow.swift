import SwiftUI

/// One row in the transcript: a chat bubble for user/assistant prose, or a
/// compact audit row for a tool call's result (with Undo, when offered).
struct AssistantMessageRow: View {
    @Environment(\.colorScheme) private var scheme
    let message: AssistantMessage
    let onUndo: (AssistantToolResult.UndoAction) -> Void
    /// Tap-to-re-edit (row 30): fires with the bubble's own text, so the
    /// caller can load it back into the composer without resending it.
    var onTapUserBubble: ((String) -> Void)? = nil

    var body: some View {
        switch message.role {
        case .user:
            bubble(trailing: true, background: FlowTheme.accent, foreground: .white)
                .onTapGesture { onTapUserBubble?(message.text) }
        case .assistant:
            bubble(trailing: false, background: FlowTheme.surface(scheme), foreground: FlowTheme.primaryText(scheme), showsBorder: true)
        case .tool:
            auditRow
        case .system:
            EmptyView()
        }
    }

    /// The corner nearest the sender's edge is pinched to `FlowRadius.small`
    /// so the bubble reads a tail without a literal pointer shape.
    private func bubbleShape(trailing: Bool) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: FlowRadius.medium,
            bottomLeadingRadius: trailing ? FlowRadius.medium : FlowRadius.small,
            bottomTrailingRadius: trailing ? FlowRadius.small : FlowRadius.medium,
            topTrailingRadius: FlowRadius.medium,
            style: .continuous
        )
    }

    @ViewBuilder
    private func bubble(trailing: Bool, background: Color, foreground: Color, showsBorder: Bool = false) -> some View {
        let shape = bubbleShape(trailing: trailing)
        HStack {
            if trailing { Spacer(minLength: 40) }
            Text(message.text)
                .font(FlowFont.body)
                .foregroundStyle(foreground)
                .padding(.horizontal, FlowSpacing.m)
                .padding(.vertical, FlowSpacing.s)
                .background(shape.fill(background))
                .overlay {
                    if showsBorder {
                        shape.strokeBorder(FlowTheme.separator(scheme), lineWidth: 1)
                    }
                }
            if !trailing { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var auditRow: some View {
        if let json = message.toolResultJSON, let result = decode(AssistantToolResult.self, json) {
            HStack(alignment: .top, spacing: FlowSpacing.s) {
                Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(result.success ? FlowTheme.accent : FlowTheme.secondaryText(scheme))
                VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                    Text(result.message)
                        .font(FlowFont.caption)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                    if let undo = result.undo {
                        Button("Undo") { onUndo(undo) }
                            .buttonStyle(.plain)
                            .font(FlowFont.caption.weight(.semibold))
                            .foregroundStyle(FlowTheme.accent)
                    }
                }
            }
        } else if message.toolProposalJSON != nil {
            HStack(spacing: FlowSpacing.s) {
                Image(systemName: "hourglass")
                    .font(.system(size: 13))
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                Text("Waiting for confirmation…")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

/// A destructive/bulk change the user must explicitly confirm before
/// anything is written — currently only `rescheduleDay`.
struct AssistantProposalCard: View {
    @Environment(\.colorScheme) private var scheme
    let proposal: AssistantToolProposal
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        FlowCard {
            VStack(alignment: .leading, spacing: FlowSpacing.m) {
                Text(proposal.title)
                    .font(FlowFont.cardTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                if !proposal.summary.isEmpty {
                    Text(proposal.summary)
                        .font(FlowFont.secondary)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                }
                VStack(spacing: FlowSpacing.s) {
                    PrimaryActionButton("Confirm", action: onConfirm)
                    SecondaryActionButton("Cancel", action: onCancel)
                }
            }
        }
    }
}

/// Shown while a provider turn is in flight: live tokens once they arrive,
/// a plain "Thinking…" indicator before the first one lands.
struct AssistantStreamingRow: View {
    @Environment(\.colorScheme) private var scheme
    let text: String

    var body: some View {
        HStack(alignment: .top) {
            Group {
                if text.isEmpty {
                    HStack(spacing: FlowSpacing.xs) {
                        ProgressView().controlSize(.small)
                        Text("Thinking…")
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                    }
                } else {
                    Text(text)
                        .font(FlowFont.body)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                }
            }
            .padding(.horizontal, FlowSpacing.m)
            .padding(.vertical, FlowSpacing.s)
            .background(RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous).fill(FlowTheme.surface(scheme)))
            .overlay(
                RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                    .strokeBorder(FlowTheme.separator(scheme), lineWidth: 1)
            )
            Spacer(minLength: 40)
        }
    }
}

/// Default state: a short pitch plus tappable examples that work whether or
/// not an API key is saved.
struct AssistantEmptyStateView: View {
    @Environment(\.colorScheme) private var scheme
    let hasAPIKey: Bool
    let onExample: (String) -> Void

    private var examples: [String] {
        hasAPIKey
            ? ["Plan my day", "Summarise today", "Add reading for 30 min"]
            : ["Add gym tomorrow at 9 for 1 hour", "Complete <task title>", "Start focus", "Search <text>"]
    }

    var body: some View {
        VStack(spacing: FlowSpacing.l) {
            FlowEmptyState(
                symbol: "sparkles",
                title: hasAPIKey ? "Ask Flowmap anything" : "Quick commands, no key needed",
                message: hasAPIKey
                    ? "I can add and reschedule tasks, start focus, search your workspace and more."
                    : "Add an API key in Settings → Assistant to chat freely. Until then, these work straight away:"
            )
            VStack(alignment: .leading, spacing: FlowSpacing.s) {
                ForEach(examples, id: \.self) { example in
                    Button {
                        onExample(example)
                    } label: {
                        Text(example)
                            .font(FlowFont.secondary)
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                            .padding(.horizontal, FlowSpacing.m)
                            .padding(.vertical, FlowSpacing.s)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(Capsule().strokeBorder(FlowTheme.separatorStrong(scheme), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
    }
}
