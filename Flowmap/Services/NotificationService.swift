import Foundation
import Observation
import UserNotifications

/// Local notifications for task starts, ends, warnings and carried work.
///
/// Identifiers are derived from segment ids, so rescheduling a task replaces its
/// notifications instead of stacking a second set — no duplicates after a sync
/// or a relaunch.
@Observable
@MainActor
public final class NotificationService {
    public enum Authorisation: Equatable, Sendable {
        case notDetermined
        case denied
        case authorised

        public var explanation: String {
            switch self {
            case .notDetermined: "Flowmap has not asked to send notifications yet."
            case .denied: "Notifications are off. Turn them on in System Settings to get task reminders."
            case .authorised: "Flowmap can remind you when tasks start and finish."
            }
        }
    }

    /// How far ahead notifications are scheduled. The system caps pending
    /// requests, so there is no value in queueing a fortnight of them.
    private static let horizonHours: Double = 36
    private static let warningLeadMinutes: Double = 5

    public private(set) var authorisation: Authorisation = .notDetermined
    public private(set) var lastError: String?

    private let centre = UNUserNotificationCenter.current()

    public init() {
        Task { await refreshAuthorisation() }
    }

    public func refreshAuthorisation() async {
        let settings = await centre.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: authorisation = .authorised
        case .denied: authorisation = .denied
        case .notDetermined: authorisation = .notDetermined
        @unknown default: authorisation = .notDetermined
        }
    }

    /// Asks for permission in context — when the user first schedules something
    /// worth being reminded about, not at launch.
    @discardableResult
    public func requestAuthorisation() async -> Bool {
        do {
            let granted = try await centre.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorisation()
            return granted
        } catch {
            lastError = "Notification permission could not be requested."
            await refreshAuthorisation()
            return false
        }
    }

    // MARK: - Identifiers

    private enum Kind: String, CaseIterable {
        case warning
        case start
        case end

        func identifier(for segmentID: UUID) -> String { "segment.\(segmentID.uuidString).\(rawValue)" }
    }

    private static let carryoverIdentifier = "flowmap.carryover.summary"

    // MARK: - Scheduling

    /// Replaces every pending task notification with a fresh set built from the
    /// current schedule. Cancelled and completed work simply is not re-added.
    public func rescheduleAll(segments: [TaskSegment], settings: AppSettings) {
        guard authorisation == .authorised else { return }

        let now = Date()
        let horizon = now.addingTimeInterval(Self.horizonHours * 3600)
        let relevant = segments
            .filter { $0.state == .scheduled && $0.startDate < horizon }
            .filter { $0.task?.status.isOpen ?? false }
            .sorted { $0.startDate < $1.startDate }

        Task {
            let pending = await centre.pendingNotificationRequests()
            let staleIdentifiers = pending
                .map(\.identifier)
                .filter { $0.hasPrefix("segment.") }
            centre.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)

            for segment in relevant {
                await add(for: segment, settings: settings, now: now)
            }
        }
    }

    private func add(for segment: TaskSegment, settings: AppSettings, now: Date) async {
        guard let task = segment.task else { return }
        let duration = segment.durationLabel

        if settings.notifyFiveMinuteWarning {
            let fireDate = segment.startDate.addingTimeInterval(-Self.warningLeadMinutes * 60)
            await schedule(
                identifier: Kind.warning.identifier(for: segment.id),
                title: "\(task.title) starts in 5 minutes",
                body: "\(duration) · \(DurationFormatter.timeRange(from: segment.startDate, to: segment.endDate))",
                at: fireDate,
                now: now,
                taskID: task.id,
                segmentID: segment.id
            )
        }

        if settings.notifyTaskStart {
            await schedule(
                identifier: Kind.start.identifier(for: segment.id),
                title: task.title,
                body: "Starting now · \(duration)",
                at: segment.startDate,
                now: now,
                taskID: task.id,
                segmentID: segment.id
            )
        }

        if settings.notifyTaskEnd {
            await schedule(
                identifier: Kind.end.identifier(for: segment.id),
                title: "\(task.title) — time's up",
                body: "Mark it done or let Flowmap find it another slot.",
                at: segment.endDate,
                now: now,
                taskID: task.id,
                segmentID: segment.id
            )
        }
    }

    private func schedule(
        identifier: String,
        title: String,
        body: String,
        at fireDate: Date,
        now: Date,
        taskID: UUID,
        segmentID: UUID
    ) async {
        guard fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Taps deep-link straight to the right task.
        content.userInfo = [
            "taskID": taskID.uuidString,
            "segmentID": segmentID.uuidString,
            "route": DeepLink.focus.rawValue,
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, fireDate.timeIntervalSince(now)),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await centre.add(request)
        } catch {
            lastError = "A reminder could not be scheduled."
        }
    }

    /// One quiet summary of work that moved, rather than a notification per task.
    public func postCarryoverSummary(_ outcomes: [RequeueOutcome], settings: AppSettings) {
        guard settings.notifyCarryoverSummary, authorisation == .authorised, !outcomes.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = outcomes.count == 1
            ? "1 task moved"
            : "\(outcomes.count) tasks moved"
        content.body = outcomes.prefix(3).map(\.bannerText).joined(separator: "\n")
        content.sound = nil
        content.userInfo = ["route": DeepLink.today.rawValue]

        let request = UNNotificationRequest(
            identifier: Self.carryoverIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        centre.removePendingNotificationRequests(withIdentifiers: [Self.carryoverIdentifier])
        Task { try? await centre.add(request) }
    }

    /// Removes everything tied to a segment — used when work is completed,
    /// cancelled or unscheduled.
    public func cancelNotifications(forSegmentID id: UUID) {
        centre.removePendingNotificationRequests(
            withIdentifiers: Kind.allCases.map { $0.identifier(for: id) }
        )
    }

    public func cancelAll() {
        centre.removeAllPendingNotificationRequests()
    }
}
