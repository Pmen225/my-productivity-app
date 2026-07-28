import AppIntents
import Foundation

/// A picker-friendly mirror of `CalendarAccountKind` for Shortcuts/Siri —
/// kept here rather than making the domain type itself conform to `AppEnum`,
/// so `Services/Calendar/CalendarProvider.swift` stays untouched.
enum CalendarAccountParameter: String, AppEnum {
    case apple
    case google

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Calendar Account"
    static let caseDisplayRepresentations: [CalendarAccountParameter: DisplayRepresentation] = [
        .apple: "Apple Calendar",
        .google: "Google Calendar",
    ]

    var kind: CalendarAccountKind { CalendarAccountKind(rawValue: rawValue) ?? .apple }
}

/// See which calendar accounts are connected, without opening the app.
struct ListCalendarAccountsIntent: AppIntent {
    static let title: LocalizedStringResource = "List Calendar Accounts"
    static let description = IntentDescription("See which calendar accounts Flowmap has connected.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let flow = AppEnvironment(context: IntentStore.context)
        let result = CalendarControlAPI(flow: flow).listAccounts()
        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }
}

/// Start connecting a calendar account. Opens the app, because the sign-in
/// sheet (Apple's permission prompt, or Google's OAuth sheet) lives there.
struct ConnectCalendarAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Connect Calendar Account"
    static let description = IntentDescription("Start connecting a calendar account to Flowmap.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Account")
    var account: CalendarAccountParameter

    static var parameterSummary: some ParameterSummary {
        Summary("Connect \(\.$account) to Flowmap")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let flow = AppEnvironment(context: IntentStore.context)
        let connected = await flow.calendarHub.connect(account.kind)
        let message = connected
            ? "Connected \(account.kind.displayName)."
            : "Couldn't connect \(account.kind.displayName)."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// Disconnect a calendar account and clear its selected calendars.
struct DisconnectCalendarAccountIntent: AppIntent {
    static let title: LocalizedStringResource = "Disconnect Calendar Account"
    static let description = IntentDescription("Disconnect a calendar account from Flowmap and clear its selected calendars.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Account")
    var account: CalendarAccountParameter

    static var parameterSummary: some ParameterSummary {
        Summary("Disconnect \(\.$account) from Flowmap")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let flow = AppEnvironment(context: IntentStore.context)
        let json = "{\"account\":\"\(account.kind.rawValue)\"}"
        let result = CalendarControlAPI(flow: flow).disconnect(json)
        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }
}

/// List merged busy calendar events between two dates. Read-only.
struct ListCalendarEventsIntent: AppIntent {
    static let title: LocalizedStringResource = "List Calendar Events"
    static let description = IntentDescription("List Flowmap's merged busy calendar events between two dates.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Start")
    var start: Date

    @Parameter(title: "End")
    var end: Date

    @Parameter(title: "Account")
    var account: CalendarAccountParameter?

    static var parameterSummary: some ParameterSummary {
        Summary("List calendar events from \(\.$start) to \(\.$end)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let flow = AppEnvironment(context: IntentStore.context)
        // Reload the window fresh: an intent may ask about a range far from
        // whatever the app last had loaded.
        await flow.calendarHub.loadEvents(from: start, to: end, selection: flow.calendarSelection)

        let isoFormatter = ISO8601DateFormatter()
        var arguments: [String: String] = [
            "startISO8601": isoFormatter.string(from: start),
            "endISO8601": isoFormatter.string(from: end),
        ]
        if let account { arguments["account"] = account.kind.rawValue }
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8)
        else {
            return .result(dialog: "I couldn't read that date range.")
        }

        let result = CalendarControlAPI(flow: flow).listEvents(json)
        guard result.success else {
            return .result(dialog: IntentDialog(stringLiteral: result.message))
        }
        guard let eventsData = result.message.data(using: .utf8),
              let events = try? JSONDecoder().decode([CalendarControlAPI.EventSummary].self, from: eventsData)
        else {
            return .result(dialog: IntentDialog(stringLiteral: result.message))
        }
        guard !events.isEmpty else {
            return .result(dialog: "No events in that range.")
        }
        let lines = events.prefix(5).map { "\($0.title) (\($0.account))" }
        var dialog = "\(events.count) event\(events.count == 1 ? "" : "s"): \(lines.joined(separator: ", "))"
        if events.count > 5 { dialog += ", and \(events.count - 5) more." }
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

/// Add an event straight to a connected calendar, without opening the app.
///
/// Unlike the assistant's chat tool (which must return synchronously and so
/// only reports the write as started), an intent's `perform()` is genuinely
/// async — this awaits the real write and reports whether it actually landed.
struct CreateCalendarBlockIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Calendar Block"
    static let description = IntentDescription("Add an event to one of your connected calendars.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Account")
    var account: CalendarAccountParameter

    @Parameter(title: "Calendar ID", requestValueDialog: "Which calendar (its identifier)?")
    var calendarId: String

    @Parameter(title: "Title", requestValueDialog: "What's the event called?")
    var eventTitle: String

    @Parameter(title: "Start")
    var start: Date

    @Parameter(title: "End")
    var end: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$eventTitle) to \(\.$account) from \(\.$start) to \(\.$end)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let flow = AppEnvironment(context: IntentStore.context)
        let title = eventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return .result(dialog: "I need a title for the event.")
        }
        guard end > start else {
            return .result(dialog: "The end time needs to be after the start time.")
        }
        guard flow.calendarHub.connection(for: account.kind)?.isConnected == true else {
            return .result(dialog: IntentDialog(stringLiteral: "\(account.kind.displayName) isn't connected, so I can't add that event."))
        }
        guard await flow.calendarHub.createEvent(
            kind: account.kind,
            title: title,
            start: start,
            end: end,
            calendarIdentifier: calendarId
        ) != nil else {
            return .result(dialog: IntentDialog(stringLiteral: "Couldn't create \"\(title)\" on \(account.kind.displayName)."))
        }
        return .result(dialog: IntentDialog(stringLiteral: "Added \"\(title)\" to \(account.kind.displayName)."))
    }
}
