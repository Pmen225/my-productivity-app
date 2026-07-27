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

/// One field plus optional voice input. Capture is never blocked by a long form.
struct QuickCaptureView: View {
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @FocusState private var isFieldFocused: Bool

    private var parsed: ParsedCapture {
        CaptureParser.parse(text, now: flow?.now ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.l) {
            Text("Quick capture")
                .font(FlowFont.sectionTitle)
                .foregroundStyle(FlowTheme.primaryText(scheme))

            HStack(spacing: FlowSpacing.s) {
                TextField("Add gym tomorrow at 9 for 1 hour", text: $text)
                    .textFieldStyle(.plain)
                    .font(FlowFont.body)
                    .focused($isFieldFocused)
                    .onSubmit(capture)

                DictationButton { transcript in
                    text = transcript.isEmpty ? text : transcript
                }
            }
            .padding(FlowSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                    .fill(FlowTheme.surfaceSunken(scheme))
            )

            if let summary = parsed.summary {
                Label(summary, systemImage: "wand.and.stars")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }

            PrimaryActionButton("Add to Inbox", systemImage: "tray.and.arrow.down", action: capture)

            Text("Anything Flowmap can't read stays in the title. You can add details later.")
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.secondaryText(scheme))
        }
        .padding(FlowSpacing.screen)
        .frame(minWidth: 340)
        .background(FlowTheme.background(scheme))
        .onAppear { isFieldFocused = true }
    }

    private func capture() {
        let result = parsed
        guard !result.title.isEmpty else { return }

        let task = FlowTask(
            title: result.title,
            status: .inbox,
            estimatedMinutes: result.minutes ?? flow?.settings.defaultTaskMinutes ?? 30,
            dueDate: result.date
        )
        context.insert(task)
        try? context.save()

        // A captured time is an intention to do it then, so honour it if free.
        if let date = result.date, let flow, date > flow.now {
            _ = flow.scheduling().schedule(task: task, at: date)
        }

        text = ""
        dismiss()
    }
}
