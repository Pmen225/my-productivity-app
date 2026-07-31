import SwiftData
import SwiftUI

/// What the parser managed to read out of a captured line.
public struct ParsedCapture: Equatable, Sendable {
    public var title: String
    public var date: Date?
    public var minutes: Int?

    public var summary: String? {
        var parts: [String] = []
        if let date {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = Calendar.current.component(.hour, from: date) == 0 ? .none : .short
            parts.append(formatter.string(from: date))
        }
        if let minutes { parts.append(DurationFormatter.compact(minutes: minutes)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Reads dates, times and durations out of a single captured line.
///
/// Capture is never blocked by this: whatever cannot be understood simply stays
/// in the title, and the task lands in the Inbox for editing later.
public enum CaptureParser {
    public static func parse(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> ParsedCapture {
        var working = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return ParsedCapture(title: "", date: nil, minutes: nil) }

        var minutes: Int?
        var day: Date?
        var timeOfDay: DateComponents?

        // Duration: "for 1 hour", "for 90 minutes", "30m", "1h30"
        let durationPatterns: [(String, (NSTextCheckingResult, NSString) -> Int?)] = [
            ("(?:for\\s+)?(\\d+)\\s*(?:hours?|hrs?|h)\\s*(\\d+)\\s*(?:minutes?|mins?|m)\\b", { match, text in
                guard let hours = Int(text.substring(with: match.range(at: 1))),
                      let mins = Int(text.substring(with: match.range(at: 2))) else { return nil }
                return hours * 60 + mins
            }),
            ("(?:for\\s+)?(\\d+)\\s*(?:hours?|hrs?|h)\\b", { match, text in
                Int(text.substring(with: match.range(at: 1))).map { $0 * 60 }
            }),
            ("(?:for\\s+)?(\\d+)\\s*(?:minutes?|mins?|m)\\b", { match, text in
                Int(text.substring(with: match.range(at: 1)))
            }),
        ]

        for (pattern, extract) in durationPatterns {
            guard minutes == nil,
                  let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            else { continue }
            let text = working as NSString
            guard let match = regex.firstMatch(in: working, range: NSRange(location: 0, length: text.length))
            else { continue }
            minutes = extract(match, text)
            if minutes != nil {
                working = text.replacingCharacters(in: match.range, with: " ")
            }
        }

        // Relative days
        let dayWords: [(String, Int)] = [("today", 0), ("tomorrow", 1), ("tonight", 0)]
        for (word, offset) in dayWords {
            guard day == nil, let range = working.range(of: word, options: .caseInsensitive) else { continue }
            day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))
            working.removeSubrange(range)
        }

        // Named weekdays resolve to the next occurrence.
        if day == nil {
            let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            for (index, name) in weekdays.enumerated() {
                guard let range = working.range(of: name, options: .caseInsensitive) else { continue }
                let target = index + 1
                let current = calendar.component(.weekday, from: now)
                let delta = (target - current + 7) % 7
                day = calendar.date(
                    byAdding: .day,
                    value: delta == 0 ? 7 : delta,
                    to: calendar.startOfDay(for: now)
                )
                working.removeSubrange(range)
                break
            }
        }

        // Times: "at 9", "at 9:30", "at 9pm", "9am"
        if let regex = try? NSRegularExpression(
            pattern: "\\b(?:at\\s+)?(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?\\b",
            options: .caseInsensitive
        ) {
            let text = working as NSString
            let matches = regex.matches(in: working, range: NSRange(location: 0, length: text.length))
            for match in matches {
                guard let hourValue = Int(text.substring(with: match.range(at: 1))), hourValue <= 24 else { continue }
                let hasMinutes = match.range(at: 2).location != NSNotFound
                let meridiem = match.range(at: 3).location != NSNotFound
                    ? text.substring(with: match.range(at: 3)).lowercased()
                    : nil
                // A bare number with no am/pm and no colon is probably a count,
                // not a time — only trust it when the line said "at".
                let saidAt = text.substring(with: match.range).lowercased().contains("at")
                guard hasMinutes || meridiem != nil || saidAt else { continue }

                var hour = hourValue
                if meridiem == "pm", hour < 12 { hour += 12 }
                if meridiem == "am", hour == 12 { hour = 0 }
                // "at 9" during a working day means 09:00, not 21:00.
                timeOfDay = DateComponents(
                    hour: hour,
                    minute: hasMinutes ? Int(text.substring(with: match.range(at: 2))) ?? 0 : 0
                )
                working = text.replacingCharacters(in: match.range, with: " ")
                break
            }
        }

        var resolved: Date?
        if let timeOfDay {
            let base = day ?? calendar.startOfDay(for: now)
            resolved = calendar.date(
                bySettingHour: timeOfDay.hour ?? 9,
                minute: timeOfDay.minute ?? 0,
                second: 0,
                of: base
            )
            // "at 9" with no day, already past today, means tomorrow.
            if day == nil, let candidate = resolved, candidate < now {
                resolved = calendar.date(byAdding: .day, value: 1, to: candidate)
            }
        } else {
            resolved = day
        }

        let title = working
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedCapture(
            title: title.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : title,
            date: resolved,
            minutes: minutes
        )
    }
}

/// The floating create button's sheet: the mock's "New" bottom sheet, wired
/// to the same task-creation call `QuickCaptureView` always made — a title, a
/// duration and an optional project, saved straight to the Inbox. Voice
/// dictation and the natural-language date/duration parser (`CaptureParser`,
/// still used by anything that scans a typed line for "tomorrow at 9") are
/// unused here now that duration and project are picked explicitly instead of
/// guessed from text; `CaptureParser` stays for other callers.
struct QuickCaptureView: View {
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \Initiative.sortOrder) private var initiatives: [Initiative]

    @State private var kind: FlowCreateKind = .task
    @State private var title = ""
    @State private var minutes = 30
    @State private var projectID: UUID?
    @State private var hasDue = false
    @State private var dueDate = Date()
    @State private var recurrence: RecurrenceFrequency = .none
    @State private var subtaskTitles: [String] = []
    @State private var note = ""
    @State private var initiativeID: UUID?

    private var projectOptions: [FlowCreateChipOption] {
        projects.map { FlowCreateChipOption(id: $0.id, title: $0.title, colour: $0.colour) }
    }

    private var initiativeOptions: [FlowCreateChipOption] {
        initiatives.map { FlowCreateChipOption(id: $0.id, title: $0.title, colour: $0.colour) }
    }

    var body: some View {
        FlowCreateSheet(
            kind: $kind,
            title: $title,
            minutes: $minutes,
            projectID: $projectID,
            hasDue: $hasDue,
            dueDate: $dueDate,
            recurrence: $recurrence,
            subtaskTitles: $subtaskTitles,
            note: $note,
            initiativeID: $initiativeID,
            projects: projectOptions,
            initiatives: initiativeOptions,
            showsDurationAndProject: kind == .task,
            onClose: { dismiss() },
            onCreate: capture
        )
        .onAppear { minutes = flow?.settings.defaultTaskMinutes ?? 30 }
    }

    /// One kind, one entity: a task, a project, or the goal those hang off.
    private func capture() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // The mock answers an empty name with a "Give it a name first" pill.
        // This sheet disables Create until there is a name, so that pill can
        // never fire — the refusal is structural, which is the better of the
        // two. No HUD here on purpose.
        guard !trimmed.isEmpty else { return }

        switch kind {
        case .task:
            let project = projects.first { $0.id == projectID }
            let due = flow?.scheduling().dueDateForNewTask(
                hasDue ? dueDate : nil,
                now: flow?.now ?? Date()
            )
            let task = FlowTask(
                title: trimmed,
                status: .inbox,
                estimatedMinutes: minutes,
                dueDate: due,
                project: project
            )
            task.recurrence = recurrence
            context.insert(task)
            attachSubtasks(to: task)
            attachNote(to: task)
            // The mock says "Task added — Inbox + map"; nothing here puts it on
            // the map, so the pill claims only what actually happened. A future
            // due date routes the task into Upcoming instead of the Inbox
            // (SmartView.upcoming matches dueDate >= tomorrow), so the HUD
            // says where it actually went.
            flow?.moments.show(.hud("Task added — \(destination(for: due))"))
        case .project:
            let project = Project(title: trimmed, sortOrder: projects.count)
            project.initiative = initiatives.first { $0.id == initiativeID }
            context.insert(project)
            flow?.moments.show(.hud("Project added"))
        case .initiative:
            context.insert(Initiative(title: trimmed, sortOrder: initiatives.count))
            flow?.moments.show(.hud("Initiative added"))
        }
        try? context.save()

        title = ""
        subtaskTitles = []
        note = ""
        initiativeID = nil
        hasDue = false
        dueDate = Date()
        recurrence = .none
        dismiss()
    }

    /// Where a task with `due` actually lands, mirroring `SmartView`'s own
    /// day-boundary logic (dueDate >= tomorrow is Upcoming; anything before
    /// that, including today, is Today) so the HUD never claims a screen the
    /// task will not actually appear on.
    private func destination(for due: Date?) -> String {
        guard let due else { return "Inbox" }
        let calendar = Calendar.current
        let now = flow?.now ?? Date()
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return due >= dayEnd ? "Upcoming" : "Today"
    }

    private func attachSubtasks(to task: FlowTask) {
        for (index, subtaskTitle) in subtaskTitles.enumerated() {
            context.insert(Subtask(title: subtaskTitle, sortOrder: index, task: task))
        }
    }

    /// The sheet's note is one paragraph, so it becomes a `Note` with a single
    /// block — the same shape the notes screen writes, rather than a second
    /// way of storing text on a task.
    private func attachNote(to task: FlowTask) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let attached = Note(title: task.title, task: task)
        context.insert(attached)
        context.insert(NoteBlock(type: .paragraph, text: trimmed, note: attached))
    }
}
