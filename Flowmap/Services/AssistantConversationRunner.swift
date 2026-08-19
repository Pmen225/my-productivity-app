import Foundation

extension AssistantToolCallRequest: Equatable {
    public static func == (lhs: AssistantToolCallRequest, rhs: AssistantToolCallRequest) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.argumentsJSON == rhs.argumentsJSON
    }
}

public struct AssistantExchange: Sendable, Equatable {
    public enum Role: String, Sendable { case user, assistant, tool }

    public let role: Role
    public let text: String
    public let toolCallID: String?
    public let toolName: String?
    public let toolArgumentsJSON: String?
    public let toolCalls: [AssistantToolCallRequest]

    public init(
        role: Role,
        text: String,
        toolCallID: String? = nil,
        toolName: String? = nil,
        toolArgumentsJSON: String? = nil,
        toolCalls: [AssistantToolCallRequest] = []
    ) {
        self.role = role
        self.text = text
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.toolArgumentsJSON = toolArgumentsJSON
        self.toolCalls = toolCalls
    }

    public var toolResult: String? { role == .tool ? text : nil }
}

public struct AssistantTransportRequest: Sendable {
    public let provider: AssistantProvider
    public let model: String
    public let system: String
    public let messages: [AssistantExchange]
    public let tools: [AssistantToolDefinition]

    public init(provider: AssistantProvider, model: String, system: String, messages: [AssistantExchange], tools: [AssistantToolDefinition]) {
        self.provider = provider
        self.model = model
        self.system = system
        self.messages = messages
        self.tools = tools
    }
}

public protocol AssistantTransport: Sendable {
    func send(_ request: AssistantTransportRequest) async throws -> AssistantTurn
}

public enum AssistantToolExecution: Sendable, Equatable {
    case executed(String)
    case requiresConfirmation
}

public protocol AssistantToolExecutor: Sendable {
    func execute(_ call: AssistantToolCallRequest) async -> AssistantToolExecution
    func confirm(_ call: AssistantToolCallRequest) async -> AssistantToolExecution
}

public struct AssistantRunPolicy: Sendable, Equatable {
    public let maxTurns: Int
    public let maxToolCallsPerTurn: Int
    public let maxTotalToolCalls: Int
    public let maxContextMessages: Int
    public let maxContextCharacters: Int
    public let requestTimeout: TimeInterval
    public let maxRetries: Int
    public let retryDelay: TimeInterval
    public let retryAfterCap: TimeInterval
    public let circuitFailureThreshold: Int

    public init(
        maxTurns: Int = 4,
        maxToolCallsPerTurn: Int = 4,
        maxTotalToolCalls: Int = 8,
        maxContextMessages: Int = 20,
        maxContextCharacters: Int = 24_000,
        requestTimeout: TimeInterval = 30,
        maxRetries: Int = 2,
        retryDelay: TimeInterval = 0.5,
        retryAfterCap: TimeInterval = 5,
        circuitFailureThreshold: Int = 3
    ) {
        self.maxTurns = maxTurns
        self.maxToolCallsPerTurn = maxToolCallsPerTurn
        self.maxTotalToolCalls = maxTotalToolCalls
        self.maxContextMessages = maxContextMessages
        self.maxContextCharacters = maxContextCharacters
        self.requestTimeout = requestTimeout
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
        self.retryAfterCap = retryAfterCap
        self.circuitFailureThreshold = circuitFailureThreshold
    }
}

public struct AssistantDiagnosticEvent: Sendable, Equatable {
    public let provider: AssistantProvider
    public let latencyMilliseconds: Int
    public let retries: Int
    public let toolCount: Int
    public let outcome: String

    public init(provider: AssistantProvider, latencyMilliseconds: Int, retries: Int, toolCount: Int, outcome: String) {
        self.provider = provider
        self.latencyMilliseconds = latencyMilliseconds
        self.retries = retries
        self.toolCount = toolCount
        self.outcome = outcome
    }
}

public enum AssistantRunError: Error, Sendable, Equatable {
    case limitExceeded
    case timeout
    case transient(String, retryAfter: TimeInterval?)
    case circuitOpen
    case transport(String)
    case cancelled

    fileprivate var diagnosticCode: String {
        switch self {
        case .limitExceeded: return "limit_exceeded"
        case .timeout: return "timeout"
        case .transient: return "transient_failure"
        case .circuitOpen: return "circuit_open"
        case .transport: return "transport_failure"
        case .cancelled: return "cancelled"
        }
    }
}

public struct AssistantContinuation: Sendable {
    fileprivate let provider: AssistantProvider
    fileprivate let model: String
    fileprivate let system: String
    fileprivate let messages: [AssistantExchange]
    fileprivate let tools: [AssistantToolDefinition]
    fileprivate let turns: Int
    fileprivate let totalToolCalls: Int
    fileprivate let pendingCall: AssistantToolCallRequest

    public var pendingToolCall: AssistantToolCallRequest { pendingCall }
}

public enum AssistantRunResult: Sendable {
    case completed(String, [AssistantExchange], [AssistantDiagnosticEvent])
    case awaitingConfirmation(AssistantContinuation)
    case failed(AssistantRunError, [AssistantExchange], [AssistantDiagnosticEvent])

    public var text: String {
        if case .completed(let text, _, _) = self { return text }
        return ""
    }
}

public actor AssistantConversationRunner {
    private let transport: AssistantTransport
    private let policy: AssistantRunPolicy
    private var consecutiveTransientFailures = 0

    public init(transport: AssistantTransport, policy: AssistantRunPolicy = AssistantRunPolicy()) {
        self.transport = transport
        self.policy = policy
    }

    public func run(
        provider: AssistantProvider,
        model: String,
        system: String,
        messages: [AssistantExchange],
        tools: [AssistantToolDefinition],
        executor: AssistantToolExecutor
    ) async throws -> AssistantRunResult {
        guard consecutiveTransientFailures < policy.circuitFailureThreshold else {
            return .failed(.circuitOpen, trim(messages), [])
        }
        return try await drive(
            provider: provider,
            model: model,
            system: system,
            messages: trim(messages),
            tools: tools,
            turns: 0,
            totalToolCalls: 0,
            executor: executor,
            diagnostics: []
        )
    }

    public func resume(
        _ continuation: AssistantContinuation,
        confirmed: Bool,
        executor: AssistantToolExecutor
    ) async throws -> AssistantRunResult {
        var messages = continuation.messages
        let execution: AssistantToolExecution
        if confirmed {
            execution = await executor.confirm(continuation.pendingCall)
        } else {
            execution = .executed("Cancelled — nothing was changed.")
        }
        guard case .executed(let result) = execution else {
            return .failed(.transport("Confirmation did not produce a tool result."), messages, [])
        }
        messages.append(AssistantExchange(
            role: .tool,
            text: result,
            toolCallID: continuation.pendingCall.id,
            toolName: continuation.pendingCall.name,
            toolArgumentsJSON: continuation.pendingCall.argumentsJSON
        ))
        return try await drive(
            provider: continuation.provider,
            model: continuation.model,
            system: continuation.system,
            messages: trim(messages),
            tools: continuation.tools,
            turns: continuation.turns,
            totalToolCalls: continuation.totalToolCalls + 1,
            executor: executor,
            diagnostics: []
        )
    }

    private func drive(
        provider: AssistantProvider,
        model: String,
        system: String,
        messages: [AssistantExchange],
        tools: [AssistantToolDefinition],
        turns: Int,
        totalToolCalls: Int,
        executor: AssistantToolExecutor,
        diagnostics: [AssistantDiagnosticEvent]
    ) async throws -> AssistantRunResult {
        guard turns < policy.maxTurns else { return .failed(.limitExceeded, messages, diagnostics) }
        try Task.checkCancellation()

        let request = AssistantTransportRequest(provider: provider, model: model, system: system, messages: trim(messages), tools: tools)
        let started = Date()
        let response: AssistantTurn
        let retries: Int
        do {
            (response, retries) = try await sendWithRetry(request)
            consecutiveTransientFailures = 0
        } catch let error as AssistantRunError {
            if case .timeout = error { consecutiveTransientFailures += 1 }
            if case .transient = error { consecutiveTransientFailures += 1 }
            let event = diagnostic(provider: provider, started: started, retries: 0, toolCount: totalToolCalls, outcome: error.diagnosticCode)
            return .failed(error, messages, diagnostics + [event])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            consecutiveTransientFailures += 1
            let event = diagnostic(provider: provider, started: started, retries: 0, toolCount: totalToolCalls, outcome: "transport_failure")
            return .failed(.transport("The assistant request failed."), messages, diagnostics + [event])
        }

        var nextMessages = messages
        if !response.text.isEmpty || !response.toolCalls.isEmpty {
            nextMessages.append(AssistantExchange(role: .assistant, text: response.text, toolCalls: response.toolCalls))
        }
        let event = diagnostic(provider: provider, started: started, retries: retries, toolCount: totalToolCalls + response.toolCalls.count, outcome: "turn")
        let nextDiagnostics = diagnostics + [event]

        guard response.toolCalls.count <= policy.maxToolCallsPerTurn else {
            return .failed(.limitExceeded, trim(nextMessages), nextDiagnostics)
        }
        guard totalToolCalls + response.toolCalls.count <= policy.maxTotalToolCalls else {
            return .failed(.limitExceeded, trim(nextMessages), nextDiagnostics)
        }

        for call in response.toolCalls {
            switch await executor.execute(call) {
            case .requiresConfirmation:
                return .awaitingConfirmation(AssistantContinuation(
                    provider: provider,
                    model: model,
                    system: system,
                    messages: trim(nextMessages),
                    tools: tools,
                    turns: turns + 1,
                    totalToolCalls: totalToolCalls,
                    pendingCall: call
                ))
            case .executed(let result):
                nextMessages.append(AssistantExchange(
                    role: .tool,
                    text: result,
                    toolCallID: call.id,
                    toolName: call.name,
                    toolArgumentsJSON: call.argumentsJSON
                ))
            }
        }

        if response.toolCalls.isEmpty {
            return .completed(response.text, trim(nextMessages), nextDiagnostics)
        }
        return try await drive(
            provider: provider,
            model: model,
            system: system,
            messages: trim(nextMessages),
            tools: tools,
            turns: turns + 1,
            totalToolCalls: totalToolCalls + response.toolCalls.count,
            executor: executor,
            diagnostics: nextDiagnostics
        )
    }

    private func sendWithRetry(_ request: AssistantTransportRequest) async throws -> (AssistantTurn, Int) {
        var retries = 0
        while true {
            do {
                return (try await withTimeout(policy.requestTimeout) { [transport] in
                    try await transport.send(request)
                }, retries)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as AssistantRunError where error == .timeout {
                if retries >= policy.maxRetries { throw error }
            } catch let error as AssistantRunError {
                guard case .transient(_, let retryAfter) = error else { throw error }
                if retries >= policy.maxRetries { throw error }
                retries += 1
                let delay = min(retryAfter ?? policy.retryDelay, policy.retryAfterCap)
                if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
                continue
            } catch {
                throw AssistantRunError.transport("The assistant request failed.")
            }
            retries += 1
            if policy.retryDelay > 0 {
                try await Task.sleep(for: .seconds(policy.retryDelay))
            }
        }
    }

    private func withTimeout<T: Sendable>(_ seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw AssistantRunError.timeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private func trim(_ messages: [AssistantExchange]) -> [AssistantExchange] {
        var retained = Array(messages.suffix(policy.maxContextMessages))
        if let latestUser = messages.last(where: { $0.role == .user }), !retained.contains(latestUser) {
            retained.insert(latestUser, at: 0)
        }
        while retained.count > 1 && retained.reduce(0, { $0 + $1.text.count }) > policy.maxContextCharacters {
            retained.removeFirst()
        }
        return retained
    }

    private func diagnostic(provider: AssistantProvider, started: Date, retries: Int, toolCount: Int, outcome: String) -> AssistantDiagnosticEvent {
        AssistantDiagnosticEvent(provider: provider, latencyMilliseconds: Int(Date().timeIntervalSince(started) * 1_000), retries: retries, toolCount: toolCount, outcome: outcome)
    }
}

/// Bridges the bounded runner to the existing confirmation-aware router.
/// The router remains the only place that can execute app mutations.
public final class AssistantRouterToolExecutor: @unchecked Sendable, AssistantToolExecutor {
    private let flow: AppEnvironment

    public init(flow: AppEnvironment) { self.flow = flow }

    public func execute(_ call: AssistantToolCallRequest) async -> AssistantToolExecution {
        await MainActor.run {
            switch AssistantToolRouter(flow: flow).handle(toolName: call.name, argumentsJSON: call.argumentsJSON) {
            case .pendingConfirmation:
                return .requiresConfirmation
            case .executed(let result):
                return .executed(result.message)
            }
        }
    }

    public func confirm(_ call: AssistantToolCallRequest) async -> AssistantToolExecution {
        let router = await MainActor.run { AssistantToolRouter(flow: flow) }
        guard case .pendingConfirmation(let proposal) = await router.handle(toolName: call.name, argumentsJSON: call.argumentsJSON) else {
            return .executed("The confirmation was no longer needed.")
        }
        let result = await router.confirm(proposal)
        return .executed(result.message)
    }
}

public struct LiveAssistantTransport: AssistantTransport {
    private let provider: AssistantProvider
    private let model: String

    public init(provider: AssistantProvider, model: String) {
        self.provider = provider
        self.model = model
    }

    public func send(_ request: AssistantTransportRequest) async throws -> AssistantTurn {
        let service = await MainActor.run { AssistantService(provider: provider, model: model) }
        let history = request.messages.map {
            AssistantChatMessage(
                role: AssistantChatMessage.Role(rawValue: $0.role.rawValue) ?? .user,
                text: $0.text,
                toolCallID: $0.toolCallID,
                toolCalls: $0.toolCalls
            )
        }
        switch await service.send(system: request.system, history: history, tools: request.tools) {
        case .success(let turn):
            return turn
        case .failure(let error):
            switch error {
            case .http(let status, _, let retryAfter) where [408, 425, 429].contains(status) || status >= 500:
                throw AssistantRunError.transient("HTTP \(status)", retryAfter: retryAfter)
            case .network(let message):
                throw AssistantRunError.transient(message, retryAfter: nil)
            case .cancelled:
                throw CancellationError()
            default:
                throw error
            }
        }
    }
}
