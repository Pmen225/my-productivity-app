import Foundation

/// Selects the smallest safe tool set for an exchange.
@MainActor
public struct AssistantToolCatalog: Sendable {
    public init() {}

    public func definitions(for messages: [AssistantExchange]) -> [AssistantToolDefinition] {
        let needsCalendar = messages.contains(where: Self.isCalendarExchange)
            || messages.last(where: { $0.role == .user }).map { Self.isCalendarIntent($0.text) } == true
        if needsCalendar { return AssistantToolRouter.toolDefinitions }
        return AssistantToolRouter.toolDefinitions.filter { !Self.isCalendarToolName($0.name) }
    }

    public static func isCalendarIntent(_ text: String) -> Bool {
        let words = text.lowercased()
        return ["calendar", "calendars", "event", "events", "meeting", "meetings", "appointment", "appointments", "schedule", "scheduled", "busy", "availability", "free time", "connect apple", "connect google", "disconnect apple", "disconnect google"].contains(where: words.contains)
    }

    public static func isCalendarToolName(_ name: String) -> Bool {
        guard let tool = AssistantToolName(rawValue: name) else { return false }
        switch tool {
        case .listCalendarAccounts, .connectCalendarAccount, .disconnectCalendarAccount, .setCalendarSelection, .setCalendarConfiguration, .listCalendarEvents, .createCalendarEvent, .moveCalendarEvent, .deleteCalendarEvent:
            return true
        default:
            return false
        }
    }

    private static func isCalendarExchange(_ exchange: AssistantExchange) -> Bool {
        if exchange.toolName.map(isCalendarToolName) == true { return true }
        if exchange.toolCalls.contains(where: { isCalendarToolName($0.name) }) { return true }
        return exchange.role == .tool && isCalendarIntent(exchange.text)
    }
}
