import Foundation

/// A small, pure command grammar the assistant can run with no API key at
/// all. It recognises a handful of verbs and reuses `CaptureParser` (already
/// built for Quick Capture) for the date/time/duration parsing, so the same
/// "tomorrow at 9 for 1 hour" phrasing works in both places.
///
/// Output is shaped exactly like a model tool call — `(toolName,
/// argumentsJSON)` — so both the local and AI-driven paths run through the
/// same `AssistantToolRouter`.
public enum QuickCommandParser {
    public struct Command: Equatable, Sendable {
        public let toolName: String
        public let argumentsJSON: String
    }

    public static func parse(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> Command? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lowered = text.lowercased()

        for prefix in ["add ", "create ", "new task "] where lowered.hasPrefix(prefix) {
            return createTaskCommand(String(text.dropFirst(prefix.count)), now: now, calendar: calendar)
        }
        for prefix in ["complete ", "finish ", "done with ", "mark done "] where lowered.hasPrefix(prefix) {
            let query = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return nil }
            return Command(toolName: AssistantToolName.completeTask.rawValue, argumentsJSON: encode(TaskQueryPayload(taskQuery: query)))
        }
        for prefix in ["cancel "] where lowered.hasPrefix(prefix) {
            let query = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return nil }
            return Command(toolName: AssistantToolName.cancelTask.rawValue, argumentsJSON: encode(TaskQueryPayload(taskQuery: query)))
        }
        if lowered.hasPrefix("start focus") {
            var rest = String(text.dropFirst("start focus".count)).trimmingCharacters(in: .whitespaces)
            if rest.lowercased().hasPrefix("on ") { rest = String(rest.dropFirst(3)) }
            return Command(
                toolName: AssistantToolName.startFocus.rawValue,
                argumentsJSON: encode(FocusPayload(taskQuery: rest.isEmpty ? nil : rest))
            )
        }
        if lowered.contains("replan") || lowered.contains("reschedule") || lowered == "plan" || lowered.hasPrefix("plan ") {
            let replanExisting = lowered.contains("whole day") || lowered.contains("everything")
            return Command(
                toolName: AssistantToolName.rescheduleDay.rawValue,
                argumentsJSON: encode(RescheduleDayPayload(replanExisting: replanExisting))
            )
        }
        for prefix in ["search ", "find "] where lowered.hasPrefix(prefix) {
            let query = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return nil }
            return Command(toolName: AssistantToolName.searchAppContent.rawValue, argumentsJSON: encode(SearchPayload(query: query)))
        }
        if lowered.contains("summarise today") || lowered.contains("summarize today")
            || lowered == "status" || lowered.contains("how's today going") || lowered.contains("how is today") {
            return Command(toolName: AssistantToolName.summariseToday.rawValue, argumentsJSON: "{}")
        }
        return nil
    }

    private static func createTaskCommand(_ rest: String, now: Date, calendar: Calendar) -> Command? {
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parsed = CaptureParser.parse(trimmed, now: now, calendar: calendar)
        guard !parsed.title.isEmpty else { return nil }
        let iso = parsed.date.map { ISO8601DateFormatter().string(from: $0) }
        let payload = CreateTaskPayload(title: parsed.title, minutes: parsed.minutes, dueDateISO8601: iso)
        return Command(toolName: AssistantToolName.createTask.rawValue, argumentsJSON: encode(payload))
    }

    private struct TaskQueryPayload: Encodable { let taskQuery: String }
    private struct SearchPayload: Encodable { let query: String }
    private struct FocusPayload: Encodable { let taskQuery: String? }
    private struct RescheduleDayPayload: Encodable { let replanExisting: Bool }
    private struct CreateTaskPayload: Encodable {
        let title: String
        let minutes: Int?
        let dueDateISO8601: String?
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
}
