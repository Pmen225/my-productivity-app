import Foundation
import SwiftData
import Testing
@testable import Flowmap

@Suite("Calendar control API")
@MainActor
struct CalendarControlAPITests {
    private final class StubCalendarProvider: CalendarProvider {
        let kind: CalendarAccountKind = .google
        var connection = CalendarConnection(kind: .google, isConnected: true)
        var eventsToReturn: [ExternalCalendarEvent] = []
        var createResult: String?
        var moveResult = false
        var deleteResults: [String: Bool] = [:]
        var operations: [String] = []

        func connect() async -> Bool { true }
        func disconnect() {}
        func refreshCalendars() async {}
        func events(from start: Date, to end: Date, selectedIdentifiers: [String]) async -> [ExternalCalendarEvent] { eventsToReturn }
        func createEvent(title: String, start: Date, end: Date, calendarIdentifier: String) async -> String? {
            operations.append("create")
            if let createResult {
                eventsToReturn.append(ExternalCalendarEvent(
                    id: createResult, title: title, start: start, end: end, isAllDay: false,
                    calendarIdentifier: calendarIdentifier, calendarTitle: "Stub"
                ))
            }
            return createResult
        }
        func moveEvent(identifier: String, start: Date, end: Date) async -> Bool {
            operations.append("move")
            if moveResult, let index = eventsToReturn.firstIndex(where: { $0.id == identifier }) {
                let event = eventsToReturn[index]
                eventsToReturn[index] = ExternalCalendarEvent(
                    id: event.id, title: event.title, start: start, end: end, isAllDay: event.isAllDay,
                    calendarIdentifier: event.calendarIdentifier, calendarTitle: event.calendarTitle
                )
            }
            return moveResult
        }
        func deleteEvent(identifier: String) async -> Bool {
            operations.append("delete:\(identifier)")
            let result = deleteResults[identifier] ?? false
            if result { eventsToReturn.removeAll { $0.id == identifier } }
            return result
        }
    }

    private func makeFlow() throws -> AppEnvironment {
        let world = try TestWorld()
        return AppEnvironment(context: world.context)
    }

    @Test("An unknown account string returns a failure result, not a crash")
    func unknownAccountFails() throws {
        let api = CalendarControlAPI(flow: try makeFlow())
        let result = api.setSelection(#"{"account":"outlook","calendarIds":[]}"#)
        #expect(result.success == false)
        #expect(!result.message.isEmpty)
    }

    @Test("setCalendarSelection writes to the Apple settings field")
    func setsAppleSelection() throws {
        let flow = try makeFlow()
        let api = CalendarControlAPI(flow: flow)
        let result = api.setSelection(#"{"account":"apple","calendarIds":["cal-1","cal-2"]}"#)
        #expect(result.success == true)
        #expect(flow.settings.selectedCalendarIdentifiers == ["cal-1", "cal-2"])
        #expect(flow.settings.selectedGoogleCalendarIdentifiers.isEmpty)
    }

    @Test("setCalendarSelection writes to the Google settings field")
    func setsGoogleSelection() throws {
        let flow = try makeFlow()
        let api = CalendarControlAPI(flow: flow)
        let result = api.setSelection(#"{"account":"google","calendarIds":["g-1"]}"#)
        #expect(result.success == true)
        #expect(flow.settings.selectedGoogleCalendarIdentifiers == ["g-1"])
        #expect(flow.settings.selectedCalendarIdentifiers.isEmpty)
    }

    @Test("Destructive calendar tools come back pending confirmation, never executed outright")
    func destructiveToolsRequireConfirmation() throws {
        let flow = try makeFlow()
        let router = AssistantToolRouter(flow: flow)

        let cases: [(AssistantToolName, String)] = [
            (.disconnectCalendarAccount, #"{"account":"apple"}"#),
            (.createCalendarEvent, #"{"account":"apple","calendarId":"cal-1","title":"Standup","startISO8601":"2026-07-27T09:00:00Z","endISO8601":"2026-07-27T09:15:00Z"}"#),
            (.moveCalendarEvent, #"{"account":"apple","eventId":"evt-1","startISO8601":"2026-07-27T09:00:00Z","endISO8601":"2026-07-27T09:15:00Z"}"#),
            (.deleteCalendarEvent, #"{"account":"apple","eventId":"evt-1"}"#),
        ]

        for (tool, json) in cases {
            switch router.handle(toolName: tool.rawValue, argumentsJSON: json) {
            case .pendingConfirmation:
                break
            case .executed:
                Issue.record("\(tool.rawValue) executed immediately instead of coming back as a proposal to confirm")
            }
        }
    }

    @Test("Confirmed calendar create reports provider failure")
    func confirmedCreateReportsProviderFailure() async throws {
        let flow = try makeFlow()
        let provider = StubCalendarProvider()
        let hub = CalendarHub(providers: [provider])
        let api = CalendarControlAPI(flow: flow, calendarHub: hub)

        let result = await api.createEvent(
            #"{"account":"google","calendarId":"cal-1","title":"Standup","startISO8601":"2026-07-27T09:00:00Z","endISO8601":"2026-07-27T09:15:00Z"}"#
        )

        #expect(result.success == false)
        #expect(result.message.contains("couldn't create"))
    }

    @Test("Move fallback creates first and removes replacement when old deletion fails")
    func moveFallbackRollsBackReplacement() async throws {
        let flow = try makeFlow()
        let provider = StubCalendarProvider()
        let oldStart = Date(timeIntervalSince1970: 1_785_139_200)
        provider.eventsToReturn = [ExternalCalendarEvent(
            id: "old", title: "Standup", start: oldStart, end: oldStart.addingTimeInterval(900),
            isAllDay: false, calendarIdentifier: "cal-1", calendarTitle: "Work"
        )]
        provider.createResult = "replacement"
        provider.deleteResults = ["old": false, "replacement": true]
        let hub = CalendarHub(providers: [provider])
        await hub.loadEvents(from: oldStart, to: oldStart.addingTimeInterval(86_400), selection: [.google: []])
        let api = CalendarControlAPI(flow: flow, calendarHub: hub)

        let result = await api.moveEvent(
            #"{"account":"google","eventId":"old","startISO8601":"2026-07-27T10:00:00Z","endISO8601":"2026-07-27T10:15:00Z"}"#
        )

        #expect(result.success == false)
        #expect(provider.operations == ["move", "create", "delete:old", "delete:replacement"])
    }

    @Test("Create move and delete refresh provider state used by replanning")
    func mutationsRefreshSchedulingInputs() async throws {
        let world = try TestWorld()
        let flow = AppEnvironment(context: world.context)
        let provider = StubCalendarProvider()
        provider.createResult = "event-1"
        provider.moveResult = true
        provider.deleteResults = ["event-1": true]
        let hub = CalendarHub(providers: [provider])
        let api = CalendarControlAPI(flow: flow, calendarHub: hub)
        let task = world.makeTask("Deep work", minutes: 60, splittable: false)
        let now = world.date(hour: 8)
        let iso = ISO8601DateFormatter()

        let create = await api.createEvent(
            #"{"account":"google","calendarId":"cal-1","title":"Meeting","startISO8601":"\#(iso.string(from: world.date(hour: 8)))","endISO8601":"\#(iso.string(from: world.date(hour: 10)))"}"#
        )
        let blockedPlan = world.service(externalEvents: hub.events).proposePlan(for: now, now: now)

        let move = await api.moveEvent(
            #"{"account":"google","eventId":"event-1","startISO8601":"\#(iso.string(from: world.date(hour: 12)))","endISO8601":"\#(iso.string(from: world.date(hour: 13)))"}"#
        )
        let movedPlan = world.service(externalEvents: hub.events).proposePlan(for: now, now: now)

        let delete = await api.deleteEvent(#"{"account":"google","eventId":"event-1"}"#)

        #expect(create.success && move.success && delete.success)
        #expect(provider.operations == ["create", "move", "delete:event-1"])
        #expect(blockedPlan.blocks.first(where: { $0.taskID == task.id })?.start == world.date(hour: 10))
        #expect(movedPlan.blocks.first(where: { $0.taskID == task.id })?.start == world.date(hour: 8))
        #expect(hub.events.isEmpty)
    }

    @Test("A malformed ISO 8601 date is rejected with a helpful message, not a crash")
    func malformedDateRejected() throws {
        let api = CalendarControlAPI(flow: try makeFlow())
        let result = api.listEvents(#"{"startISO8601":"not-a-date","endISO8601":"2026-07-27T10:00:00Z"}"#)
        #expect(result.success == false)
        #expect(result.message.contains("date"))
    }

    @Test("A credential-shaped configuration value never appears in the result message")
    func redactsCredentialLookingValue() throws {
        let api = CalendarControlAPI(flow: try makeFlow())
        let secret = "sk-ant-abcdef1234567890"
        let json = #"{"account":"google","googleClientId":"\#(secret)"}"#
        let result = api.setConfiguration(json)
        #expect(result.success == true)
        #expect(!result.message.contains(secret))
    }
}
