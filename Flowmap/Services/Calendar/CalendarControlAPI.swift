import Foundation

/// The calendar half of the assistant tool surface.
///
/// Kept out of `AssistantToolRouter` so that file stays a thin dispatcher —
/// every method here returns a ready-to-render `AssistantToolResult`, exactly
/// like the router's own tool implementations. Only `CalendarHub` and
/// `CalendarAccountKind` are touched: never a concrete provider type, so a
/// second account (Google) slots in without this file changing.
///
/// `AssistantToolRouter.execute(_:argumentsJSON:)` is a synchronous function —
/// it is called directly (never awaited) from `Flowmap/Features/Assistant/AssistantViewModel.swift`,
/// which this task is not allowed to touch. `CalendarHub`'s connect/create/move/
/// delete calls are genuinely asynchronous (Google is a network round trip), so
/// those four operations here fire a `Task` and hand back an honest "started"
/// result immediately; the real outcome lands in `CalendarHub`'s own
/// `@Observable` state, which the UI already watches. This mirrors the
/// fire-and-forget pattern `CalendarHub.disconnect(_:)` already uses.
@MainActor
public struct CalendarControlAPI {
    private let flow: AppEnvironment

    public init(flow: AppEnvironment) {
        self.flow = flow
    }

    // MARK: - Arguments

    struct AccountArgs: Codable { let account: String }

    struct SetSelectionArgs: Codable {
        let account: String
        let calendarIds: [String]
    }

    struct SetConfigurationArgs: Codable {
        let account: String
        let enabled: Bool?
        let googleClientId: String?
        let writeBackCalendarId: String?
        let writesFocusBlocks: Bool?
    }

    struct ListEventsArgs: Codable {
        let startISO8601: String
        let endISO8601: String
        let account: String?
    }

    struct CreateEventArgs: Codable {
        let account: String
        let calendarId: String
        let title: String
        let startISO8601: String
        let endISO8601: String
    }

    struct MoveEventArgs: Codable {
        let account: String
        let eventId: String
        let startISO8601: String
        let endISO8601: String
    }

    struct DeleteEventArgs: Codable {
        let account: String
        let eventId: String
    }

    /// One event as handed back to an agent — the fields it needs to make a
    /// follow-up `moveCalendarEvent` or `deleteCalendarEvent` call.
    struct EventSummary: Codable {
        let id: String
        let title: String
        let startISO8601: String
        let endISO8601: String
        let isAllDay: Bool
        let account: String
    }

    // MARK: - 1. List accounts

    /// Read-only. Reports every `CalendarAccountKind`, even one with no
    /// provider registered yet (Google, before it lands), so an agent can
    /// always see the full account surface.
    public func listAccounts() -> AssistantToolResult {
        let lines = CalendarAccountKind.allCases.map { kind -> String in
            let connection = flow.calendarHub.connection(for: kind) ?? CalendarConnection(kind: kind)
            var line = "\(connection.kind.displayName): \(connection.isConnected ? "connected" : "not connected")"
            if let label = connection.accountLabel { line += " as \(label)" }
            if !connection.calendars.isEmpty {
                let names = connection.calendars.map { calendar -> String in
                    var name = calendar.title
                    if connection.selectedIdentifiers.contains(calendar.id) { name += " (selected)" }
                    if !calendar.allowsModification { name += " (read-only)" }
                    return name
                }
                line += " — calendars: \(names.joined(separator: ", "))"
            }
            if let error = connection.lastError { line += " — last error: \(KeychainService.redact(error))" }
            return line
        }
        return AssistantToolResult(
            toolName: AssistantToolName.listCalendarAccounts.rawValue,
            success: true,
            message: lines.joined(separator: "; ")
        )
    }

    // MARK: - 2. Connect

    public func connect(_ json: String) -> AssistantToolResult {
        guard let args = decode(AccountArgs.self, json), let kind = CalendarAccountKind(rawValue: args.account) else {
            return failure(.connectCalendarAccount, "I don't recognise that calendar account.")
        }
        Task { await flow.calendarHub.connect(kind) }
        return AssistantToolResult(
            toolName: AssistantToolName.connectCalendarAccount.rawValue,
            success: true,
            message: "Starting the \(kind.displayName) connection — you'll see a sign-in sheet if one is needed."
        )
    }

    // MARK: - 3. Disconnect

    public func disconnect(_ json: String) -> AssistantToolResult {
        guard let args = decode(AccountArgs.self, json), let kind = CalendarAccountKind(rawValue: args.account) else {
            return failure(.disconnectCalendarAccount, "I don't recognise that calendar account.")
        }
        flow.calendarHub.disconnect(kind)
        clearSettings(for: kind)
        try? flow.context.save()
        return AssistantToolResult(
            toolName: AssistantToolName.disconnectCalendarAccount.rawValue,
            success: true,
            message: "Disconnected \(kind.displayName) and cleared its selected calendars."
        )
    }

    private func clearSettings(for kind: CalendarAccountKind) {
        switch kind {
        case .apple:
            flow.settings.calendarIntegrationEnabled = false
            flow.settings.selectedCalendarIdentifiers = []
        case .google:
            flow.settings.googleCalendarEnabled = false
            flow.settings.selectedGoogleCalendarIdentifiers = []
            flow.settings.googleAccountLabel = nil
        }
        flow.settings.touch()
    }

    // MARK: - 4. Set selection

    public func setSelection(_ json: String) -> AssistantToolResult {
        guard let args = decode(SetSelectionArgs.self, json), let kind = CalendarAccountKind(rawValue: args.account) else {
            return failure(.setCalendarSelection, "I don't recognise that calendar account.")
        }
        switch kind {
        case .apple: flow.settings.selectedCalendarIdentifiers = args.calendarIds
        case .google: flow.settings.selectedGoogleCalendarIdentifiers = args.calendarIds
        }
        flow.settings.touch()
        try? flow.context.save()
        flow.refreshCalendarWindow(around: flow.now)
        let count = args.calendarIds.count
        return AssistantToolResult(
            toolName: AssistantToolName.setCalendarSelection.rawValue,
            success: true,
            message: "Now showing \(count) calendar\(count == 1 ? "" : "s") from \(kind.displayName)."
        )
    }

    // MARK: - 5. Set configuration

    /// Configuration only — never a token or secret. `googleOAuthClientID` is
    /// public by design (PKCE has no client secret), but any value here still
    /// goes through `KeychainService.redact(_:)` before it can reach a message,
    /// in case an agent pastes something credential-shaped by mistake.
    public func setConfiguration(_ json: String) -> AssistantToolResult {
        guard let args = decode(SetConfigurationArgs.self, json), let kind = CalendarAccountKind(rawValue: args.account) else {
            return failure(.setCalendarConfiguration, "I don't recognise that calendar account.")
        }
        var changes: [String] = []
        if let enabled = args.enabled {
            switch kind {
            case .apple: flow.settings.calendarIntegrationEnabled = enabled
            case .google: flow.settings.googleCalendarEnabled = enabled
            }
            changes.append(enabled ? "turned it on" : "turned it off")
        }
        if let clientId = args.googleClientId, kind == .google {
            let trimmed = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                flow.settings.googleOAuthClientID = trimmed
                // The client id itself isn't a secret (PKCE has no client
                // secret), but the value is echoed here and the whole message
                // still goes through `redact` below — belt and braces in case
                // an agent pastes a real token into the wrong field.
                changes.append("updated the Google client id to \(trimmed)")
            }
        }
        if let writeBackId = args.writeBackCalendarId {
            flow.settings.writeBackCalendarIdentifier = writeBackId
            changes.append("set the write-back calendar")
        }
        if let writesFocusBlocks = args.writesFocusBlocks {
            flow.settings.writesFocusBlocksToCalendar = writesFocusBlocks
            changes.append(writesFocusBlocks ? "will write focus blocks to your calendar" : "will stop writing focus blocks to your calendar")
        }
        guard !changes.isEmpty else {
            return failure(.setCalendarConfiguration, "I need at least one setting to change.")
        }
        flow.settings.touch()
        try? flow.context.save()
        flow.refreshCalendarWindow(around: flow.now)
        let message = "Updated \(kind.displayName): \(changes.joined(separator: ", "))."
        return AssistantToolResult(
            toolName: AssistantToolName.setCalendarConfiguration.rawValue,
            success: true,
            message: KeychainService.redact(message)
        )
    }

    // MARK: - 6. List events

    /// Read-only. Answers from `CalendarHub`'s already-merged, already-loaded
    /// window rather than forcing a fresh network round trip — the same cache
    /// the planner and timeline read from. The message is a JSON array (not a
    /// single sentence, unlike the other tools here) because an agent needs the
    /// real `id` back to make a follow-up `moveCalendarEvent` or
    /// `deleteCalendarEvent` call.
    public func listEvents(_ json: String) -> AssistantToolResult {
        guard let args = decode(ListEventsArgs.self, json) else {
            return failure(.listCalendarEvents, "I need a start and end date to list events.")
        }
        guard let start = parseDate(args.startISO8601) else {
            return failure(.listCalendarEvents, "\"\(args.startISO8601)\" isn't a date I can read — use ISO 8601, like 2026-07-27T09:00:00Z.")
        }
        guard let end = parseDate(args.endISO8601) else {
            return failure(.listCalendarEvents, "\"\(args.endISO8601)\" isn't a date I can read — use ISO 8601, like 2026-07-27T09:00:00Z.")
        }
        guard end > start else {
            return failure(.listCalendarEvents, "The end time needs to be after the start time.")
        }
        var kinds = CalendarAccountKind.allCases
        if let accountString = args.account {
            guard let kind = CalendarAccountKind(rawValue: accountString) else {
                return failure(.listCalendarEvents, "I don't recognise that calendar account.")
            }
            kinds = [kind]
        }

        let isoFormatter = ISO8601DateFormatter()
        var summaries: [EventSummary] = []
        for kind in kinds {
            let events = flow.calendarHub.busyEvents(in: flow.calendarHub.eventsByKind[kind] ?? [])
            for event in events where event.start < end && event.end > start {
                summaries.append(
                    EventSummary(
                        id: event.id,
                        title: event.title,
                        startISO8601: isoFormatter.string(from: event.start),
                        endISO8601: isoFormatter.string(from: event.end),
                        isAllDay: event.isAllDay,
                        account: kind.rawValue
                    )
                )
            }
        }
        summaries.sort { $0.startISO8601 < $1.startISO8601 }

        guard let data = try? JSONEncoder().encode(summaries), let message = String(data: data, encoding: .utf8) else {
            return failure(.listCalendarEvents, "I couldn't put that list of events together.")
        }
        return AssistantToolResult(toolName: AssistantToolName.listCalendarEvents.rawValue, success: true, message: message)
    }

    // MARK: - 7. Create event

    public func createEvent(_ json: String) -> AssistantToolResult {
        guard let args = decode(CreateEventArgs.self, json), let kind = CalendarAccountKind(rawValue: args.account) else {
            return failure(.createCalendarEvent, "I don't recognise that calendar account.")
        }
        let title = args.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return failure(.createCalendarEvent, "I need a title for the event.")
        }
        guard let start = parseDate(args.startISO8601) else {
            return failure(.createCalendarEvent, "\"\(args.startISO8601)\" isn't a date I can read — use ISO 8601, like 2026-07-27T09:00:00Z.")
        }
        guard let end = parseDate(args.endISO8601), end > start else {
            return failure(.createCalendarEvent, "I need a valid end time after the start time.")
        }
        guard flow.calendarHub.connection(for: kind)?.isConnected == true else {
            return failure(.createCalendarEvent, "\(kind.displayName) isn't connected, so I can't create that event.")
        }
        let calendarId = args.calendarId
        Task { _ = await flow.calendarHub.createEvent(kind: kind, title: title, start: start, end: end, calendarIdentifier: calendarId) }
        // The write happens on `CalendarHub` in the background, so the real
        // event id — and therefore a working undo — only exists after this
        // call returns. Saying so beats offering an undo that would silently
        // fail to find anything to delete.
        return AssistantToolResult(
            toolName: AssistantToolName.createCalendarEvent.rawValue,
            success: true,
            message: "Creating \"\(title)\" on \(kind.displayName) — it'll appear on your calendar in a moment. This happens in the background, so it can't be undone from here; delete it directly if you change your mind."
        )
    }

    // MARK: - 8. Move event

    public func moveEvent(_ json: String) -> AssistantToolResult {
        guard let args = decode(MoveEventArgs.self, json), let kind = CalendarAccountKind(rawValue: args.account) else {
            return failure(.moveCalendarEvent, "I don't recognise that calendar account.")
        }
        guard let start = parseDate(args.startISO8601) else {
            return failure(.moveCalendarEvent, "\"\(args.startISO8601)\" isn't a date I can read — use ISO 8601, like 2026-07-27T09:00:00Z.")
        }
        guard let end = parseDate(args.endISO8601), end > start else {
            return failure(.moveCalendarEvent, "I need a valid end time after the start time.")
        }
        guard let existing = (flow.calendarHub.eventsByKind[kind] ?? []).first(where: { $0.id == args.eventId }) else {
            return failure(.moveCalendarEvent, "I couldn't find that event on \(kind.displayName) to move.")
        }
        guard let provider = flow.calendarHub.providers[kind] else {
            return failure(.moveCalendarEvent, "\(kind.displayName) isn't connected, so I can't move that event.")
        }
        let eventId = args.eventId
        Task {
            let moved = await provider.moveEvent(identifier: eventId, start: start, end: end)
            guard !moved else { return }
            // Some providers (Apple's EventKit write-back) never edit an event
            // in place — the documented alternative is to delete and recreate it.
            _ = await flow.calendarHub.deleteEvent(kind: kind, identifier: eventId)
            _ = await flow.calendarHub.createEvent(
                kind: kind,
                title: existing.title,
                start: start,
                end: end,
                calendarIdentifier: existing.calendarIdentifier
            )
        }
        return AssistantToolResult(
            toolName: AssistantToolName.moveCalendarEvent.rawValue,
            success: true,
            message: "Moving \"\(existing.title)\" on \(kind.displayName) to its new time."
        )
    }

    // MARK: - 9. Delete event

    public func deleteEvent(_ json: String) -> AssistantToolResult {
        guard let args = decode(DeleteEventArgs.self, json), let kind = CalendarAccountKind(rawValue: args.account) else {
            return failure(.deleteCalendarEvent, "I don't recognise that calendar account.")
        }
        guard flow.calendarHub.connection(for: kind)?.isConnected == true else {
            return failure(.deleteCalendarEvent, "\(kind.displayName) isn't connected, so there's nothing to delete.")
        }
        let eventId = args.eventId
        Task { _ = await flow.calendarHub.deleteEvent(kind: kind, identifier: eventId) }
        return AssistantToolResult(
            toolName: AssistantToolName.deleteCalendarEvent.rawValue,
            success: true,
            message: "Deleting that event from \(kind.displayName) — this can't be undone."
        )
    }

    // MARK: - Helpers

    private func failure(_ tool: AssistantToolName, _ message: String) -> AssistantToolResult {
        AssistantToolResult(toolName: tool.rawValue, success: false, message: message)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func parseDate(_ iso: String) -> Date? {
        guard !iso.isEmpty else { return nil }
        if let date = ISO8601DateFormatter().date(from: iso) { return date }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: iso)
    }
}
