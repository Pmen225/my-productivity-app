import Foundation
import Testing
@testable import Flowmap

/// Wording gaps between the mockup's local-command grammar and the app's
/// `QuickCommandParser` (state/specs/pages/assistant.md rows 12, 13).
@Suite("Quick command parser wording")
struct QuickCommandParserTests {
    @Test("\"plan my day\" — the app's own suggestion-chip phrase — triggers the day auto-plan route")
    func planMyDayTriggersReschedule() {
        let command = QuickCommandParser.parse("plan my day")
        #expect(command?.toolName == AssistantToolName.rescheduleDay.rawValue)
    }

    @Test("Bare \"plan\" triggers the day auto-plan route")
    func barePlanTriggersReschedule() {
        let command = QuickCommandParser.parse("plan")
        #expect(command?.toolName == AssistantToolName.rescheduleDay.rawValue)
    }

    @Test("\"plan\" does not shadow the \"add …\" task-creation grammar")
    func planDoesNotShadowAddGrammar() {
        let command = QuickCommandParser.parse("add plan for meeting at 9")
        #expect(command?.toolName == AssistantToolName.createTask.rawValue)
    }

    @Test("\"status\" triggers the summary route")
    func statusTriggersSummary() {
        let command = QuickCommandParser.parse("status")
        #expect(command?.toolName == AssistantToolName.summariseToday.rawValue)
    }

    @Test("\"how's today going\" triggers the summary route")
    func howsTodayGoingTriggersSummary() {
        let command = QuickCommandParser.parse("how's today going")
        #expect(command?.toolName == AssistantToolName.summariseToday.rawValue)
    }

    @Test("\"how is today\" triggers the summary route")
    func howIsTodayTriggersSummary() {
        let command = QuickCommandParser.parse("how is today")
        #expect(command?.toolName == AssistantToolName.summariseToday.rawValue)
    }
}
