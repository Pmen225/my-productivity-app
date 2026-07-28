import SwiftUI

/// The transcript plus composer for one thread. Chat bubbles for user/
/// assistant prose; compact audit rows for tool calls and their results;
/// a proposal card blocks nothing else but must be resolved before the next
/// message goes out.
public struct AssistantConversationView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var viewModel: AssistantViewModel
    @FocusState private var isComposerFocused: Bool

    public init(thread: AssistantThread, flow: AppEnvironment) {
        _viewModel = State(initialValue: AssistantViewModel(thread: thread, flow: flow))
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
        .background(FlowTheme.background(scheme))
    }

    /// A small status pill under the navigation title: whether a provider key
    /// is on file, so the quick-command-only ceiling is never a surprise.
    private var statusPill: some View {
        HStack(spacing: FlowSpacing.xs) {
            Circle()
                .fill(viewModel.hasAPIKey ? FlowTheme.accent : FlowTheme.tertiaryText(scheme))
                .frame(width: 6, height: 6)
            Text(viewModel.hasAPIKey ? "Connected" : "Local commands only")
                .font(FlowFont.caption.weight(.semibold))
                .foregroundStyle(FlowTheme.secondaryText(scheme))
        }
        .padding(.horizontal, FlowSpacing.m)
        .padding(.vertical, FlowSpacing.xs)
        .background(Capsule().fill(FlowTheme.surfaceSunken(scheme)))
        .overlay(Capsule().strokeBorder(FlowTheme.separator(scheme), lineWidth: 1))
        .padding(.top, FlowSpacing.s)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
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
                            AssistantMessageRow(message: message, onUndo: viewModel.undo)
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
                TextField("Ask Flowmap, or type a quick command…", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(FlowFont.body)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .onSubmit(viewModel.send)

                DictationButton { transcript in
                    viewModel.inputText = transcript.isEmpty ? viewModel.inputText : transcript
                }
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
