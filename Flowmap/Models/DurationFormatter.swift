import Foundation

/// Compact duration labels — `15M`, `30M`, `1H`, `1H 30M` — plus spoken
/// equivalents, because VoiceOver reads `30M` as two letters.
public enum DurationFormatter {
    public static func compact(minutes: Int) -> String {
        let total = max(0, minutes)
        let hours = total / 60
        let mins = total % 60
        switch (hours, mins) {
        case (0, _): return "\(mins)M"
        case (_, 0): return "\(hours)H"
        default: return "\(hours)H \(mins)M"
        }
    }

    public static func spoken(minutes: Int) -> String {
        let total = max(0, minutes)
        let hours = total / 60
        let mins = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hour\(hours == 1 ? "" : "s")") }
        if mins > 0 { parts.append("\(mins) minute\(mins == 1 ? "" : "s")") }
        return parts.isEmpty ? "0 minutes" : parts.joined(separator: " ")
    }

    /// `24:36` / `1:04:09` for the focus countdown.
    public static func countdown(seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    public static func spokenCountdown(seconds: TimeInterval) -> String {
        spoken(minutes: Int((max(0, seconds) / 60).rounded())) + " remaining"
    }

    /// `09:00 – 09:30`
    public static func timeRange(from start: Date, to end: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    public static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
