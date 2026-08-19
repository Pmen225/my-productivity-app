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
    private var providerRunner: AssistantConversationRunner?
    private var providerExecutor: AssistantRouterToolExecutor?
    private var providerContinuation: AssistantContinuation?

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
        if let continuation = providerContinuation, let runner = providerRunner, let executor = providerExecutor {
            Task { [weak self] in
                guard let result = try? await runner.resume(continuation, confirmed: true, executor: executor) else { return }
                self?.providerContinuation = nil
                self?.applyProviderResult(result, pendingMessage: message)
            }
            return
        }
        Task {
            let result = await router.confirm(proposal)
            message.toolResultJSON = encode(result)
            message.isApplied = true
            thread.touch()
            try? context.save()
        }
    }

    public func cancelPendingProposal() {
        guard let (message, _) = pendingProposal else { return }
        providerContinuation = nil
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

        let runner = AssistantConversationRunner(
            transport: LiveAssistantTransport(provider: flow.settings.assistantProvider, model: flow.settings.assistantModel)
        )
        let executor = AssistantRouterToolExecutor(flow: flow)
        providerRunner = runner
        providerExecutor = executor
        let messages = thread.visibleMessages.flatMap { message -> [AssistantExchange] in
            switch message.role {
            case .user:
                return [AssistantExchange(role: .user, text: message.text)]
            case .assistant:
                return [AssistantExchange(role: .assistant, text: message.text)]
            case .tool:
                guard let result = message.toolResultJSON else { return [] }
                return [AssistantExchange(role: .tool, text: result, toolName: message.toolName)]
            case .system:
                return []
            }
        }
        let result = try? await runner.run(
            provider: flow.settings.assistantProvider,
            model: flow.settings.assistantModel,
            system: systemPrompt(),
            messages: messages,
            tools: AssistantToolRouter.toolDefinitions,
            executor: executor
        )
        streamingText = ""
        if let result { applyProviderResult(result) }
    }

    private func applyProviderResult(_ result: AssistantRunResult, pendingMessage: AssistantMessage? = nil) {
        switch result {
        case .completed(let text, let exchanges, _):
            providerContinuation = nil
            if let pendingMessage, let toolResult = exchanges.last(where: { $0.role == .tool }) {
                pendingMessage.toolResultJSON = encode(AssistantToolResult(toolName: pendingMessage.toolName ?? "", success: true, message: toolResult.text))
                pendingMessage.isApplied = true
                thread.touch()
                try? context.save()
            }
            if !text.isEmpty {
                appendMessage(role: .assistant, text: text)
            } else if pendingMessage == nil {
                appendMessage(role: .assistant, text: "(No response.)")
            }
        case .awaitingConfirmation(let continuation):
            providerContinuation = continuation
            let call = continuation.pendingToolCall
            let message = pendingMessage ?? appendMessage(role: .tool, text: "", toolName: call.name)
            if case .pendingConfirmation(let proposal) = router.handle(toolName: call.name, argumentsJSON: call.argumentsJSON) {
                message.toolProposalJSON = encode(proposal)
                try? context.save()
            }
        case .failed(let error, _, _):
            providerContinuation = nil
            let message: String
            switch error {
            case .limitExceeded: message = "The assistant stopped safely because the request exceeded its action limit."
            case .timeout: message = "The assistant took too long to respond."
            case .circuitOpen: message = "The assistant is temporarily paused after repeated connection failures."
            case .transport: message = "The assistant could not complete the request."
            case .cancelled: message = "Cancelled."
            }
            errorMessage = message
            appendMessage(role: .assistant, text: message)
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
