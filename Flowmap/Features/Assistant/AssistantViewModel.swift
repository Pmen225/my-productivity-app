import Foundation
import SwiftData

/// Drives one conversation: sends the user's text either to a local quick
/// command (no key needed) or to the configured provider, and persists every
/// tool call/result onto the thread so the transcript is a durable audit
/// trail, not just chat text.
@Observable
@MainActor
public final class AssistantViewModel {
    public let thread: AssistantThread
    private let flow: AppEnvironment
    private var context: ModelContext { flow.context }
    private var router: AssistantToolRouter { AssistantToolRouter(flow: flow) }

    public var inputText: String = ""
    public var isSending = false
    public var streamingText: String = ""
    public var errorMessage: String?

    public init(thread: AssistantThread, flow: AppEnvironment) {
        self.thread = thread
        self.flow = flow
    }

    public var hasAPIKey: Bool {
        KeychainService.hasKey(account: flow.settings.assistantProvider.keychainAccount)
    }

    /// The most recent unresolved proposal, if any — derived from the thread
    /// itself so it survives relaunch and never drifts from what's persisted.
    public var pendingProposal: (message: AssistantMessage, proposal: AssistantToolProposal)? {
        guard let message = thread.visibleMessages.last(where: { $0.isPendingProposal }),
              let json = message.toolProposalJSON,
              let proposal = decode(AssistantToolProposal.self, json)
        else { return nil }
        return (message, proposal)
    }

    public func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        inputText = ""
        appendMessage(role: .user, text: text)

        if hasAPIKey {
            Task { await sendToProvider() }
        } else if let command = QuickCommandParser.parse(text, now: flow.now) {
            runLocalCommand(command)
        } else {
            appendMessage(
                role: .assistant,
                text: "Locally I can run quick commands like \"Add gym tomorrow at 9 for 1 hour\", \"Complete <task>\", \"Cancel <task>\", \"Start focus\", \"Search <text>\", or \"Plan my day\" / \"Summarise today\". For full conversation, connect a provider — tap ⋯ top right."
            )
        }
    }

    public func confirmPendingProposal() {
        guard let (message, proposal) = pendingProposal else { return }
        let result = router.confirm(proposal)
        message.toolResultJSON = encode(result)
        message.isApplied = true
        thread.touch()
        try? context.save()
    }

    public func cancelPendingProposal() {
        guard let (message, _) = pendingProposal else { return }
        message.toolResultJSON = encode(AssistantToolResult(toolName: message.toolName ?? "", success: false, message: "Cancelled — nothing was changed."))
        message.isApplied = true
        thread.touch()
        try? context.save()
    }

    /// Undoes a previously-executed tool call, recording the undo itself as
    /// its own audit entry so the trail stays honest about order.
    public func undo(_ action: AssistantToolResult.UndoAction) {
        let result = router.undo(action)
        let undoMessage = AssistantMessage(role: .tool, text: "", thread: thread, toolName: "undo", toolResultJSON: encode(result))
        context.insert(undoMessage)
        thread.touch()
        try? context.save()
    }

    // MARK: - Local path

    private func runLocalCommand(_ command: QuickCommandParser.Command) {
        let message = appendMessage(role: .tool, text: "", toolName: command.toolName)
        applyToolCall(AssistantToolCallRequest(id: UUID().uuidString, name: command.toolName, argumentsJSON: command.argumentsJSON), to: message)
    }

    // MARK: - Provider path

    private func sendToProvider() async {
        isSending = true
        streamingText = ""
        errorMessage = nil
        defer { isSending = false }

        let service = AssistantService(provider: flow.settings.assistantProvider, model: flow.settings.assistantModel)
        let history = thread.visibleMessages
            .filter { $0.role == .user || $0.role == .assistant }
            .map { AssistantChatMessage(role: $0.role == .assistant ? .assistant : .user, text: $0.text) }

        let result = await service.streamSend(
            system: systemPrompt(),
            history: history,
            tools: AssistantToolRouter.toolDefinitions
        ) { [weak self] token in
            Task { @MainActor in self?.streamingText += token }
        }
        streamingText = ""

        switch result {
        case .success(let turn):
            if !turn.text.isEmpty {
                appendMessage(role: .assistant, text: turn.text)
            }
            if let call = turn.toolCalls.first {
                let message = appendMessage(role: .tool, text: "", toolName: call.name)
                applyToolCall(call, to: message)
            } else if turn.text.isEmpty {
                appendMessage(role: .assistant, text: "(No response.)")
            }
        case .failure(let error):
            errorMessage = error.errorDescription
            appendMessage(role: .assistant, text: error.errorDescription ?? "Something went wrong.")
        }
    }

    private func applyToolCall(_ call: AssistantToolCallRequest, to message: AssistantMessage) {
        switch router.handle(toolName: call.name, argumentsJSON: call.argumentsJSON) {
        case .pendingConfirmation(let proposal):
            message.toolProposalJSON = encode(proposal)
        case .executed(let result):
            message.toolResultJSON = encode(result)
            message.isApplied = true
        }
        try? context.save()
    }

    private func systemPrompt() -> String {
        let dateText = ISO8601DateFormatter().string(from: flow.now)
        return """
        You are the assistant inside Flowmap, a personal task and focus app. \
        The current date and time is \(dateText) (ISO 8601, local time). \
        When a tool needs a date or time, compute it relative to now and pass ISO 8601. \
        Use the provided tools to actually change the user's data — never claim an \
        action happened unless you called the matching tool and it succeeded. \
        Keep replies brief and concrete. Use UK spelling.
        """
    }

    // MARK: - Persistence helpers

    @discardableResult
    private func appendMessage(role: AssistantRole, text: String, toolName: String? = nil) -> AssistantMessage {
        let message = AssistantMessage(role: role, text: text, thread: thread, toolName: toolName)
        context.insert(message)
        thread.touch()
        try? context.save()
        return message
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
