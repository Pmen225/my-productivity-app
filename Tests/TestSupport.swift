import Foundation
import SwiftData
import Testing
@testable import Flowmap

/// A fresh in-memory store plus the settings record, for one test.
@MainActor
struct TestWorld {
    let container: ModelContainer
    let context: ModelContext
    let settings: AppSettings
    /// A fixed calendar so tests never depend on the machine's locale.
    let calendar: Calendar

    init(workdayStartHour: Int = 8, workdayEndHour: Int = 21) throws {
        container = try ModelContainerFactory.makeInMemoryContainer()
        context = ModelContext(container)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.firstWeekday = 2
        self.calendar = calendar

        settings = AppSettings()
        settings.workdayStartHour = workdayStartHour
        settings.workdayEndHour = workdayEndHour
        context.insert(settings)
        try? context.save()
    }

    /// A concrete moment: 2026-03-10 at the given time, in UTC.
    func date(hour: Int, minute: Int = 0, dayOffset: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 10 + dayOffset
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    func service(externalEvents: [ExternalCalendarEvent] = []) -> SchedulingService {
        SchedulingService(
            context: context,
            settings: settings,
            externalEvents: externalEvents,
            calendar: calendar
        )
    }

    func engine() -> SchedulingEngine {
        SchedulingEngine(settings: settings, calendar: calendar)
    }

    @discardableResult
    func makeTask(
        _ title: String,
        minutes: Int = 30,
        priority: TaskPriority = .none,
        due: Date? = nil,
        splittable: Bool = false,
        minimumChunk: Int = 15,
        status: TaskStatus = .inbox,
        sortOrder: Int = 0,
        flaggedForToday: Bool = false,
        // Defaults `true` so every existing call site — written before the
        // compulsory planning gate existed — keeps starting immediately.
        // Gate-specific tests pass `planned: false` explicitly.
        planned: Bool = true
    ) -> FlowTask {
        let task = FlowTask(
            title: title,
            status: status,
            priority: priority,
            estimatedMinutes: minutes,
            dueDate: due,
            sortOrder: sortOrder
        )
        task.isSplittable = splittable
        task.minimumChunkMinutes = minimumChunk
        task.isFlaggedForToday = flaggedForToday
        task.hasBeenPlanned = planned
        context.insert(task)
        try? context.save()
        return task
    }

    @discardableResult
    func makeSegment(
        for task: FlowTask,
        start: Date,
        minutes: Int,
        locked: Bool = false,
        state: SegmentState = .scheduled,
        source: SegmentSource = .manual
    ) -> TaskSegment {
        let segment = TaskSegment(
            task: task,
            startDate: start,
            endDate: start.addingTimeInterval(Double(minutes) * 60),
            state: state,
            isLocked: locked,
            source: source
        )
        context.insert(segment)
        if task.status == .inbox { task.status = .planned }
        try? context.save()
        return segment
    }

    var allSegments: [TaskSegment] {
        (try? context.fetch(FetchDescriptor<TaskSegment>())) ?? []
    }

    func liveSegments(of task: FlowTask) -> [TaskSegment] {
        allSegments
            .filter { $0.task?.id == task.id && $0.state.occupiesTimeline }
            .sorted { $0.startDate < $1.startDate }
    }
}

/// True when no two segments that hold time overlap each other.
@MainActor
func hasNoOverlaps(_ segments: [TaskSegment]) -> Bool {
    let live = segments
        .filter { $0.state.occupiesTimeline }
        .sorted { $0.startDate < $1.startDate }
    for (index, segment) in live.enumerated() where index + 1 < live.count {
        if live[index + 1].startDate < segment.endDate { return false }
    }
    return true
}
