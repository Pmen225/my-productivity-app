import Foundation

/// Turns a scheduled segment's start into the short label the row and the
/// confirmation banner both show — "Today 09:00", "Tomorrow 09:00", or, once
/// it's further out than tomorrow, "Tue 4 Aug 09:00". Always 24-hour, and
/// locale-fixed so the label reads the same on every device.
public enum ScheduleWording {
    public static func startLabel(_ start: Date, now: Date, calendar: Calendar) -> String {
        let time = timeFormatter(calendar: calendar).string(from: start)
        if calendar.isDate(start, inSameDayAs: now) {
            return "Today \(time)"
        }
        let startOfToday = calendar.startOfDay(for: now)
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
           calendar.isDate(start, inSameDayAs: tomorrow) {
            return "Tomorrow \(time)"
        }
        return "\(dayFormatter(calendar: calendar).string(from: start)) \(time)"
    }

    private static func timeFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    private static func dayFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }
}
