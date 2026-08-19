import Foundation
import Testing
@testable import Flowmap

@Suite("Assistant conversation runner")
struct AssistantConversationRunnerTests {
    @Test("feeds tool results back and preserves call order")
    func feedsToolResultsBack() async throws {
        let transport = ScriptedAssistantTransport(turns: [
            AssistantTurn(text: "", toolCalls: [
                AssistantToolCallRequest(id: "one", name: "first", argumentsJSON: "{}"),
                AssistantToolCallRequest(id: "two", name: "second", argumentsJSON: "{}"),
            ]),
            AssistantTurn(text: "Done", toolCalls: []),
        ])
        let executor = ScriptedAssistantExecutor(results: [
            .executed("first result"),
            .executed("second result"),
        ])
        let runner = AssistantConversationRunner(transport: transport, policy: .test)

        let result = try await runner.run(
            provider: .openai,
            model: "test",
            system: "system",
            messages: [AssistantExchange.user("Do it")],
            tools: [],
            executor: executor
        )

        #expect(result.text == "Done")
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[1].messages.compactMap(\.toolResult) == ["first result", "second result"])
        #expect(await executor.calls == ["first", "second"])
    }

    @Test("pauses destructive work and resumes only after confirmation")
    func confirmationPauseAndResume() async throws {
        let transport = ScriptedAssistantTransport(turns: [
            AssistantTurn(text: "", toolCalls: [AssistantToolCallRequest(id: "delete", name: "deleteTask", argumentsJSON: "{}")]),
            AssistantTurn(text: "Deleted", toolCalls: []),
        ])
        let executor = ScriptedAssistantExecutor(results: [.requiresConfirmation])
        let runner = AssistantConversationRunner(transport: transport, policy: .test)

        let paused = try await runner.run(
            provider: .anthropic,
            model: "test",
            system: "system",
            messages: [AssistantExchange.user("Delete it")],
            tools: [],
            executor: executor
        )
        guard case .awaitingConfirmation(let continuation) = paused else {
            Issue.record("Expected a confirmation pause")
            return
        }

        let resumed = try await runner.resume(continuation, confirmed: true, executor: executor)
        #expect(resumed.text == "Deleted")
        #expect(await executor.confirmedCalls == ["deleteTask"])
    }

    @Test("enforces turn, per-turn call, total call, and context limits")
    func enforcesLimits() async throws {
        let transport = ScriptedAssistantTransport(turns: [
            AssistantTurn(text: "", toolCalls: (0..<5).map { AssistantToolCallRequest(id: "\($0)", name: "tool", argumentsJSON: "{}") }),
        ])
        let runner = AssistantConversationRunner(transport: transport, policy: AssistantRunPolicy(
            maxTurns: 4,
            maxToolCallsPerTurn: 4,
            maxTotalToolCalls: 8,
            maxContextMessages: 20,
            maxContextCharacters: 24_000,
            requestTimeout: 1,
            maxRetries: 0,
            retryDelay: 0,
            circuitFailureThreshold: 3
        ))

        let result = try await runner.run(
            provider: .openai,
            model: "test",
            system: "system",
            messages: (0..<30).map { AssistantExchange.user(String(repeating: "x", count: 2_000) + " \($0)") },
            tools: [],
            executor: ScriptedAssistantExecutor(results: [])
        )

        guard case .failed(.limitExceeded, let exchanges, _) = result else {
            Issue.record("Expected the per-turn limit to fail closed")
            return
        }
        #expect(exchanges.count <= 20)
        #expect(exchanges.contains { $0.role == .user && $0.text.contains("29") })
    }
}

private actor ScriptedAssistantTransport: AssistantTransport {
    var turns: [AssistantTurn]
    private(set) var requests: [AssistantTransportRequest] = []

    init(turns: [AssistantTurn]) { self.turns = turns }

    func send(_ request: AssistantTransportRequest) async throws -> AssistantTurn {
        requests.append(request)
        return turns.isEmpty ? AssistantTurn(text: "", toolCalls: []) : turns.removeFirst()
    }
}

private actor ScriptedAssistantExecutor: AssistantToolExecutor {
    var results: [AssistantToolExecution]
    private(set) var calls: [String] = []
    private(set) var confirmedCalls: [String] = []

    init(results: [AssistantToolExecution]) { self.results = results }

    func execute(_ call: AssistantToolCallRequest) async -> AssistantToolExecution {
        calls.append(call.name)
        return results.isEmpty ? .executed("ok") : results.removeFirst()
    }

    func confirm(_ call: AssistantToolCallRequest) async -> AssistantToolExecution {
        confirmedCalls.append(call.name)
        return .executed("confirmed")
    }
}

private extension AssistantExchange {
    static func user(_ text: String) -> AssistantExchange {
        AssistantExchange(role: .user, text: text)
    }
}

private extension AssistantRunPolicy {
    static let test = AssistantRunPolicy(
        maxTurns: 4,
        maxToolCallsPerTurn: 4,
        maxTotalToolCalls: 8,
        maxContextMessages: 20,
        maxContextCharacters: 24_000,
        requestTimeout: 1,
        maxRetries: 0,
        retryDelay: 0,
        circuitFailureThreshold: 3
    )
}
