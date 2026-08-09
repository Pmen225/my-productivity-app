import Foundation
import SwiftData
import Testing
@testable import Flowmap

@Suite("Project progress")
@MainActor
struct ProjectProgressTests {
    @Test("Progress is the share of actionable tasks completed")
    func progressFromCompletedTasks() throws {
        let world = try TestWorld()
        let project = Project(title: "Launch")
        world.context.insert(project)

        for index in 0..<4 {
            let task = world.makeTask("Task \(index)")
            task.project = project
            if index < 3 { task.markCompleted() }
        }
        try world.context.save()

        #expect(project.completedTaskCount == 3)
        #expect(abs(project.progress - 0.75) < 0.0001)
        #expect(project.progressPercentText == "75%")
    }

    @Test("Cancelled work is excluded so it cannot distort the ratio")
    func cancelledTasksDoNotDistortProgress() throws {
        let world = try TestWorld()
        let project = Project(title: "Launch")
        world.context.insert(project)

        let done = world.makeTask("Done")
        done.project = project
        done.markCompleted()

        let cancelled = world.makeTask("Dropped")
        cancelled.project = project
        cancelled.markCancelled()

        try world.context.save()

        // One actionable task, and it is done: 100%, not 50%.
        #expect(project.actionableTasks.count == 1)
        #expect(project.progress == 1.0)
    }

    @Test("Paused work still counts as outstanding")
    func pausedWorkCountsAsOutstanding() throws {
        let world = try TestWorld()
        let project = Project(title: "Launch")
        world.context.insert(project)

        let done = world.makeTask("Done")
        done.project = project
        done.markCompleted()

        let paused = world.makeTask("Paused")
        paused.project = project
        paused.status = .paused

        try world.context.save()
        #expect(project.progress == 0.5)
    }

    @Test("An empty project reports zero rather than dividing by zero")
    func emptyProjectIsZero() throws {
        let world = try TestWorld()
        let project = Project(title: "Empty")
        world.context.insert(project)
        try world.context.save()

        #expect(project.progress == 0)
        #expect(project.progressPercentText == "0%")
    }
}

@Suite("Backup validation and merge")
@MainActor
struct BackupTests {
    @Test("An exported archive round-trips into an empty store")
    func roundTrip() throws {
        let source = try TestWorld()
        let project = Project(title: "Launch")
        source.context.insert(project)
        let task = source.makeTask("Write the brief", minutes: 45)
        task.project = project
        source.makeSegment(for: task, start: source.date(hour: 10), minutes: 45)
        source.context.insert(Subtask(title: "Outline", sortOrder: 0, task: task))
        try source.context.save()

        let data = try BackupService.export(from: source.context)

        let destination = try TestWorld()
        let archive = try BackupService.validate(data)
        let summary = try BackupService.importArchive(archive, into: destination.context)

        let tasks = (try destination.context.fetch(FetchDescriptor<FlowTask>()))
        #expect(tasks.count == 1)
        #expect(tasks[0].title == "Write the brief")
        #expect(tasks[0].estimatedMinutes == 45)
        #expect(tasks[0].project?.title == "Launch")
        #expect(summary.created > 0)
    }

    @Test("Importing the same archive twice changes nothing the second time")
    func importIsDuplicateSafe() throws {
        let source = try TestWorld()
        source.makeTask("Only task")
        try source.context.save()
        let data = try BackupService.export(from: source.context)

        let destination = try TestWorld()
        let archive = try BackupService.validate(data)

        let first = try BackupService.importArchive(archive, into: destination.context)
        let second = try BackupService.importArchive(archive, into: destination.context)

        let tasks = try destination.context.fetch(FetchDescriptor<FlowTask>())
        #expect(tasks.count == 1)
        #expect(first.created >= 1)
        // Nothing was newer, so the second pass wrote nothing.
        #expect(second.created == 0)
        #expect(second.updated == 0)
    }

    @Test("An older backup never overwrites a newer local edit")
    func olderRecordsDoNotClobberNewerOnes() throws {
        let source = try TestWorld()
        let task = source.makeTask("Original title")
        task.updatedAt = source.date(hour: 9)
        try source.context.save()
        let data = try BackupService.export(from: source.context)

        // The same record, edited more recently on this device.
        let archive = try BackupService.validate(data)
        let destination = try TestWorld()
        try BackupService.importArchive(archive, into: destination.context)

        let local = try destination.context.fetch(FetchDescriptor<FlowTask>())[0]
        local.title = "Newer local title"
        local.updatedAt = source.date(hour: 18)
        try destination.context.save()

        let summary = try BackupService.importArchive(archive, into: destination.context)
        #expect(local.title == "Newer local title")
        #expect(summary.updated == 0)
    }

    @Test("Malformed input is rejected with a readable reason, not a crash")
    func rejectsMalformedInput() throws {
        let notJSON = Data("this is not a backup".utf8)
        #expect(throws: (any Error).self) { try BackupService.validate(notJSON) }

        let wrongShape = Data(#"{"formatVersion": 1, "tasks": "nope"}"#.utf8)
        #expect(throws: (any Error).self) { try BackupService.validate(wrongShape) }
    }

    @Test("A backup from a newer format version is refused")
    func refusesNewerFormatVersions() throws {
        let world = try TestWorld()
        world.makeTask("Task")
        var data = try BackupService.export(from: world.context)
        let text = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\"formatVersion\" : 1", with: "\"formatVersion\" : 99")
        data = Data(text.utf8)

        #expect(throws: (any Error).self) { try BackupService.validate(data) }
    }

    @Test("Notes export as Markdown with unique filenames")
    func markdownExport() throws {
        let world = try TestWorld()
        for _ in 0..<2 {
            let note = Note(title: "Meeting")
            world.context.insert(note)
            world.context.insert(NoteBlock(type: .heading2, text: "Agenda", sortOrder: 0, note: note))
            world.context.insert(NoteBlock(type: .bullet, text: "Budget", sortOrder: 1, note: note))
        }
        try world.context.save()

        let files = BackupService.exportNotesAsMarkdown(from: world.context)
        #expect(files.count == 2)
        #expect(files.keys.contains("Meeting.md"))
        #expect(files.keys.contains("Meeting 2.md"))
        #expect(files["Meeting.md"]?.contains("## Agenda") == true)
        #expect(files["Meeting.md"]?.contains("- Budget") == true)
    }
}

@Suite("Quick capture parsing")
struct CaptureParserTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 8))!
    }

    @Test("Reads a day, a time and a duration out of one line")
    func parsesTheHeadlineExample() {
        let result = CaptureParser.parse("Add gym tomorrow at 9 for 1 hour", now: now, calendar: calendar)

        #expect(result.minutes == 60)
        #expect(result.date != nil)
        #expect(calendar.component(.hour, from: result.date!) == 9)
        #expect(calendar.component(.day, from: result.date!) == 11)
        #expect(result.title.localizedCaseInsensitiveContains("gym"))
        // The parsed parts are stripped out of the title.
        #expect(!result.title.localizedCaseInsensitiveContains("tomorrow"))
    }

    @Test("Understands minute durations and 12-hour times")
    func parsesMinutesAndMeridiem() {
        let result = CaptureParser.parse("Call the dentist today at 2pm for 15 minutes", now: now, calendar: calendar)
        #expect(result.minutes == 15)
        #expect(calendar.component(.hour, from: result.date!) == 14)
    }

    @Test("Understands compound durations like 1h30m")
    func parsesCompoundDuration() {
        let result = CaptureParser.parse("Deep work for 1h30m", now: now, calendar: calendar)
        #expect(result.minutes == 90)
    }

    @Test("A named weekday resolves to its next occurrence")
    func parsesWeekday() {
        // 2026-03-10 is a Tuesday, so Friday is three days later.
        let result = CaptureParser.parse("Review on Friday", now: now, calendar: calendar)
        #expect(result.date != nil)
        #expect(calendar.component(.day, from: result.date!) == 13)
    }

    @Test("Capture is never blocked: an unparseable line still becomes a title")
    func fallsBackToPlainTitle() {
        let result = CaptureParser.parse("Think about the thing", now: now, calendar: calendar)
        #expect(result.title == "Think about the thing")
        #expect(result.date == nil)
        #expect(result.minutes == nil)
    }

    @Test("A bare number is treated as part of the title, not a time")
    func doesNotInventTimesFromBareNumbers() {
        let result = CaptureParser.parse("Buy 4 apples", now: now, calendar: calendar)
        #expect(result.date == nil)
        #expect(result.title.contains("4"))
    }
}

@Suite("Smart views")
@MainActor
struct SmartViewTests {
    @Test("Inbox holds only unscheduled captured work")
    func inboxContents() throws {
        let world = try TestWorld()
        let loose = world.makeTask("Loose")
        let scheduled = world.makeTask("Scheduled")
        world.makeSegment(for: scheduled, start: world.date(hour: 10), minutes: 30)

        let tasks = [loose, scheduled]
        let inbox = SmartView.inbox.matches(tasks, now: world.date(hour: 9), calendar: world.calendar)
        #expect(inbox.map(\.title) == ["Loose"])
    }

    @Test("Inbox also holds the old Someday resident: open, undated, unscheduled, non-inbox status")
    func inboxAbsorbsFormerSomeday() throws {
        let world = try TestWorld()
        let parked = world.makeTask("Parked", status: .planned)
        let dated = world.makeTask("Dated", due: world.date(hour: 17), status: .planned)
        let scheduled = world.makeTask("Scheduled", status: .planned)
        world.makeSegment(for: scheduled, start: world.date(hour: 10), minutes: 30)
        let done = world.makeTask("Done", status: .planned)
        done.markCompleted()

        let tasks = [parked, dated, scheduled, done]
        let inbox = SmartView.inbox.matches(tasks, now: world.date(hour: 9), calendar: world.calendar)
        #expect(inbox.map(\.title) == ["Parked"])
    }

    @Test("Today includes work scheduled today, due today, or flagged for today")
    func todayContents() throws {
        let world = try TestWorld()
        let now = world.date(hour: 9)

        let scheduled = world.makeTask("Scheduled today")
        world.makeSegment(for: scheduled, start: world.date(hour: 14), minutes: 30)
        let due = world.makeTask("Due today", due: world.date(hour: 17))
        let flagged = world.makeTask("Flagged", flaggedForToday: true)
        let later = world.makeTask("Next week", due: world.date(hour: 9, dayOffset: 7))

        let today = SmartView.today.matches(
            [scheduled, due, flagged, later], now: now, calendar: world.calendar
        )
        #expect(Set(today.map(\.title)) == ["Scheduled today", "Due today", "Flagged"])
    }

    @Test("Completed collects finished work and nothing else")
    func completedContents() throws {
        let world = try TestWorld()
        let done = world.makeTask("Done")
        done.markCompleted()
        let open = world.makeTask("Open")

        let completed = SmartView.completed.matches([done, open], now: world.date(hour: 9), calendar: world.calendar)
        #expect(completed.map(\.title) == ["Done"])
    }

    @Test("Priority grouping sorts high to low and omits empty groups")
    func prioritySections() throws {
        let world = try TestWorld()
        let high = world.makeTask("High", priority: .high)
        let low = world.makeTask("Low", priority: .low)

        let sections = SmartView.allTasks.sections([low, high], grouping: .priority)
        #expect(sections.map(\.title) == ["High", "Low"])
        #expect(sections[0].tasks.map(\.title) == ["High"])
    }
}
