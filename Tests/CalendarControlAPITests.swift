import Foundation
import SwiftData
import Testing
@testable import Flowmap

@Suite("Calendar control API")
@MainActor
struct CalendarControlAPITests {
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
