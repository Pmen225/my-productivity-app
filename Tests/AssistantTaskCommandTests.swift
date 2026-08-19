import Foundation
import SwiftData
import Testing
@testable import Flowmap

@Suite("Assistant task command contract")
@MainActor
struct AssistantTaskCommandTests {
    @Test("Create, rename and schedule mutate the persisted task through the router")
    func createRenameAndSchedulePersist() throws {
        let world = try TestWorld()
        let router = AssistantToolRouter(flow: AppEnvironment(context: world.context))

        guard case .executed(let created) = router.handle(
            toolName: AssistantToolName.createTask.rawValue,
            argumentsJSON: #"{"title":"Router sample","minutes":30}"#
        ) else { Issue.record("createTask did not execute"); return }
        #expect(created.success)
        let task = try #require(world.context.fetch(FetchDescriptor<FlowTask>()).first { $0.title == "Router sample" })

        guard case .executed(let renamed) = router.handle(
            toolName: AssistantToolName.updateTask.rawValue,
            argumentsJSON: #"{"taskQuery":"Router sample","title":"Router renamed"}"#
        ) else { Issue.record("updateTask did not execute"); return }
        #expect(renamed.success)
        #expect(task.title == "Router renamed")

        guard case .executed(let scheduled) = router.handle(
            toolName: AssistantToolName.scheduleTask.rawValue,
            argumentsJSON: #"{"taskQuery":"Router renamed","dateISO8601":"2026-03-10T10:00:00Z"}"#
        ) else { Issue.record("scheduleTask did not execute"); return }
        #expect(scheduled.success)
        #expect(world.liveSegments(of: task).count == 1)
    }

    @Test("Every assistant command is defined once and reaches both providers")
    func providerToolParity() {
        let definitions = AssistantToolRouter.toolDefinitions
        let expectedNames = Set(AssistantToolName.allCases.map(\.rawValue))
        #expect(Set(definitions.map(\.name)) == expectedNames)
        #expect(definitions.map(\.name).count == expectedNames.count)

        let anthropic = AssistantService(provider: .anthropic, model: "test")
            .anthropicToolsPayload(definitions)
        let openAI = AssistantService(provider: .openai, model: "test")
            .openAIToolsPayload(definitions)
        #expect(Set(anthropic.compactMap { $0["name"] as? String }) == expectedNames)
        #expect(Set(openAI.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }) == expectedNames)
    }

    @Test("Deleting a task requires confirmation and removes the persisted task")
    func deleteTaskRequiresConfirmation() async throws {
        let world = try TestWorld()
        let task = world.makeTask("Remove me")
        let router = AssistantToolRouter(flow: AppEnvironment(context: world.context))

        let outcome = router.handle(
            toolName: AssistantToolName.deleteTask.rawValue,
            argumentsJSON: #"{"taskQuery":"Remove me"}"#
        )
        guard case .pendingConfirmation(let proposal) = outcome else {
            Issue.record("deleteTask executed without confirmation")
            return
        }
        #expect((try world.context.fetch(FetchDescriptor<FlowTask>())).contains { $0.id == task.id })

        let result = await router.confirm(proposal)
        #expect(result.success)
        #expect(!(try world.context.fetch(FetchDescriptor<FlowTask>())).contains { $0.id == task.id })
    }

    @Test("Rescheduling moves the existing segment without creating another")
    func rescheduleTaskMovesExistingSegment() throws {
        let world = try TestWorld()
        let task = world.makeTask("Move me")
        let oldStart = world.date(hour: 10)
        let newStart = world.date(hour: 14)
        let segment = world.makeSegment(for: task, start: oldStart, minutes: 30)
        let router = AssistantToolRouter(flow: AppEnvironment(context: world.context))

        let result: AssistantToolResult
        switch router.handle(
            toolName: AssistantToolName.rescheduleTask.rawValue,
            argumentsJSON: #"{"taskQuery":"Move me","dateISO8601":"2026-03-10T14:00:00Z"}"#
        ) {
        case .executed(let executed): result = executed
        case .pendingConfirmation:
            Issue.record("rescheduleTask unexpectedly required confirmation")
            return
        }

        #expect(result.success)
        #expect(segment.startDate == newStart)
        #expect(world.liveSegments(of: task).map(\.id) == [segment.id])
    }
}
