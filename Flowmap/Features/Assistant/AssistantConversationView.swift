import SwiftUI

/// The transcript plus composer for one thread. Chat bubbles for user/
/// assistant prose; compact audit rows for tool calls and their results;
/// a proposal card blocks nothing else but must be resolved before the next
/// message goes out.
public struct AssistantConversationView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var viewModel: AssistantViewModel
    @FocusState private var isComposerFocused: Bool
    @State private var isDictating = false
    private let flow: AppEnvironment
    /// Overrides the default per-scheme background. The mini dock passes
    /// `.clear` so its own dark-glass panel shows through instead.
    private let background: Color?
    /// Fires when the disconnected status pill is tapped. The full screen
    /// opens the in-conversation setup sheet directly; the mini dock instead
    /// hands off to the full screen first (HIG: close one sheet before
    /// showing another, rather than stacking sheet-on-sheet).
    private let onConnectTapped: () -> Void

    public init(
        thread: AssistantThread,
        flow: AppEnvironment,
        background: Color? = nil,
        onConnectTapped: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: AssistantViewModel(thread: thread, flow: flow))
        self.flow = flow
        self.background = background
        self.onConnectTapped = onConnectTapped
    }

    public var body: some View {
        VStack(spacing: 0) {
            statusPill
            messagesList
            if let pending = viewModel.pendingProposal {
                AssistantProposalCard(
                    proposal: pending.proposal,
                    onConfirm: viewModel.confirmPendingProposal,
                    onCancel: viewModel.cancelPendingProposal
                )
                .padding(.horizontal, FlowSpacing.screen)
                .padding(.top, FlowSpacing.s)
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .padding(.horizontal, FlowSpacing.screen)
                    .padding(.top, FlowSpacing.xs)
            }
            composer
        }
        .background(background ?? FlowTheme.background(scheme))
    }

    /// A small status pill under the navigation title: whether a provider key
    /// is on file, so the quick-command-only ceiling is never a surprise.
    /// Tappable — disconnected routes to Settings → Assistant, connected
    /// opens a model-switching menu (row 28/29).
    private var statusPill: some View {
        Group {
            if viewModel.hasAPIKey {
                Menu {
                    ForEach(flow.settings.assistantProvider.availableModels, id: \.self) { model in
                        let isSelected = model == flow.settings.assistantModel
                        Button {
                            flow.settings.assistantModel = model
                            try? flow.context.save()
                        } label: {
                            if isSelected {
                                Label(model, systemImage: "checkmark")
                            } else {
                                Text(model)
                            }
                        }
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                } label: {
                    statusPillLabel(text: flow.settings.assistantModel, connected: true)
                }
                .accessibilityLabel("Connected. Model: \(flow.settings.assistantModel). Tap to change model.")
            } else {
                Button(action: onConnectTapped) {
                    statusPillLabel(text: "Local commands only — tap to connect", connected: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Local commands only. Tap to connect a provider.")
            }
        }
        .flowHitTarget()
        .padding(.top, FlowSpacing.s)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func statusPillLabel(text: String, connected: Bool) -> some View {
        HStack(spacing: FlowSpacing.xs) {
            Circle()
                .fill(connected ? FlowTheme.accent : FlowTheme.tertiaryText(scheme))
                .frame(width: 6, height: 6)
            Text(text)
                .font(FlowFont.caption.weight(.semibold))
                .foregroundStyle(FlowTheme.secondaryText(scheme))
        }
        .padding(.horizontal, FlowSpacing.m)
        .padding(.vertical, FlowSpacing.xs)
        .background(Capsule().fill(FlowTheme.surfaceSunken(scheme)))
        .overlay(Capsule().strokeBorder(FlowTheme.separator(scheme), lineWidth: 1))
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: FlowSpacing.m) {
                    if viewModel.thread.visibleMessages.isEmpty {
                        AssistantEmptyStateView(hasAPIKey: viewModel.hasAPIKey) { example in
                            viewModel.inputText = example
                            viewModel.send()
                        }
                        .padding(.top, FlowSpacing.xxl)
                    } else {
                        ForEach(viewModel.thread.visibleMessages) { message in
                            AssistantMessageRow(message: message, onUndo: viewModel.undo, onTapUserBubble: reedit)
                                .id(message.id)
                        }
                    }
                    if viewModel.isSending {
                        AssistantStreamingRow(text: viewModel.streamingText)
                            .id("streaming")
                    }
                }
                .padding(FlowSpacing.screen)
            }
            .onChange(of: viewModel.thread.visibleMessages.count) { scrollToEnd(proxy) }
            .onChange(of: viewModel.isSending) { scrollToEnd(proxy) }
        }
    }

    /// Tap a user bubble to re-edit: its text is loaded into the composer,
    /// ready to be changed and re-sent — the original message stays put.
    private func reedit(_ text: String) {
        viewModel.inputText = text
        isComposerFocused = true
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation {
            if viewModel.isSending {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let last = viewModel.thread.visibleMessages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: FlowSpacing.s) {
            HStack(spacing: FlowSpacing.s) {
                TextField(
                    isDictating ? "Listening…" : "Message, or tap the mic…",
                    text: $viewModel.inputText,
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .font(FlowFont.body)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .onSubmit(viewModel.send)

                DictationButton(
                    onTranscript: { transcript in
                        viewModel.inputText = transcript.isEmpty ? viewModel.inputText : transcript
                    },
                    onRecordingChange: { isDictating = $0 }
                )
            }
            .padding(.horizontal, FlowSpacing.m)
            .padding(.vertical, FlowSpacing.s)
            .background(Capsule().fill(FlowTheme.surface(scheme)))
            .overlay(Capsule().strokeBorder(FlowTheme.separatorStrong(scheme), lineWidth: 1))

            Button(action: viewModel.send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: FlowControlSize.secondary, height: FlowControlSize.secondary)
                    .background(Circle().fill(FlowTheme.accentFill))
            }
            .buttonStyle(.plain)
            .flowHitTarget()
            .opacity(sendIsEnabled ? 1 : 0.5)
            .disabled(!sendIsEnabled)
            .accessibilityLabel("Send")
        }
        .padding(FlowSpacing.screen)
    }

    private var sendIsEnabled: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSending
    }
}
