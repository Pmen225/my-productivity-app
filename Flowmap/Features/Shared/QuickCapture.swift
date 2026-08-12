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

    /// Preselects the project chip — set by callers that already know which
    /// project the new task belongs to (e.g. a project's own task list).
    var initialProjectID: UUID?
    /// Preselects a due date — set by callers anchored to a specific day
    /// (e.g. Calendar's quick-add), so that context is not lost when they
    /// route through this shared sheet instead of their own form.
    var initialDueDate: Date?
    /// Files the new task straight onto a user list — set by that list's own
    /// screen so the task lands where it was created, not in the Inbox.
    var initialListID: UUID?
    /// Creates the new task as a real child of an existing `FlowTask`. Map
    /// uses this route, so node authoring and ordinary capture never diverge.
    var initialParentTaskID: UUID?
    /// Mirrors the old Today quick-add's behaviour: an undated task created
    /// from the Today list is flagged onto today rather than left in the
    /// Inbox, as long as today's plan isn't already sealed.
    var flagForTodayIfUndated: Bool = false

    @State private var kind: FlowCreateKind = .task
    @State private var title = ""
    @State private var minutes = 30
    @State private var projectID: UUID?
    @State private var hasDue = false
    @State private var dueDate = Date()
    @State private var preferredPeriod: DayPeriod = .anytime
    @State private var recurrence: RecurrenceFrequency = .none
    @State private var subtaskTitles: [String] = []
    @State private var note = ""
    @State private var initiativeID: UUID?
    /// The creation draft lives HERE, not in `TaskDetailInspector` — `@State`
    /// survives the body re-evaluations that re-init the inspector struct.
    @State private var draftTask = TaskDraft.makeTask(estimatedMinutes: 30)

    private var projectOptions: [FlowCreateChipOption] {
        projects.map { FlowCreateChipOption(id: $0.id, title: $0.title, colour: $0.colour) }
    }

    private var initiativeOptions: [FlowCreateChipOption] {
        initiatives.map { FlowCreateChipOption(id: $0.id, title: $0.title, colour: $0.colour) }
    }

    var body: some View {
        // One-task-card spec (2026-08-10): a task now opens the fused
        // `TaskDetailInspector` card, never this sheet's own design — the
        // founder rejected having two differently designed task-creation
        // surfaces. Project and Initiative are a different model each and
        // keep `FlowCreateSheet` unchanged. `kind` stays shared so switching
        // kind from either surface's own header menu re-routes here.
        Group {
            if kind == .task {
                NavigationStack {
                    TaskDetailInspector(draftTask: draftTask, draftSeed: draftSeed, kindSelection: $kind)
                }
            } else {
                FlowCreateSheet(
                    kind: $kind,
                    title: $title,
                    minutes: $minutes,
                    projectID: $projectID,
                    hasDue: $hasDue,
                    dueDate: $dueDate,
                    preferredPeriod: $preferredPeriod,
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
            }
        }
        .onAppear {
            minutes = flow?.settings.defaultTaskMinutes ?? 30
            if let initialProjectID { projectID = initialProjectID }
            if let initialDueDate {
                hasDue = true
                dueDate = initialDueDate
            }
        }
    }

    /// The task card's seed — the same context `capture()`'s `.task` branch
    /// used to apply directly (project/list/due date/"flag for today"), now
    /// handed to `TaskDetailInspector` since it owns the insert.
    private var draftSeed: TaskDraft.Seed {
        TaskDraft.Seed(
            projectID: initialProjectID,
            listID: initialListID,
            parentTaskID: initialParentTaskID,
            dueDate: initialDueDate,
            flagForTodayIfUndated: flagForTodayIfUndated
        )
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
            // Unreachable: `kind == .task` renders the fused
            // `TaskDetailInspector`, never this sheet — the task draft
            // lifecycle lives in `TaskDraft`.
            return
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
        preferredPeriod = .anytime
        recurrence = .none
        dismiss()
    }
}
