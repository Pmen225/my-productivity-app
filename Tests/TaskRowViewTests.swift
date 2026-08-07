import Foundation
import SwiftData
import Testing
@testable import Flowmap

/// `@MainActor` because `TaskRowView` is a `View`, so its statics are
/// main-actor isolated (the same trap `DurationWheelTests` already notes).
@MainActor
@Suite("Task row: sub-task progress and quick actions")
struct TaskRowViewTests {
    @Test("No sub-tasks reads as zero, never a division by zero")
    func fractionEmpty() throws {
        let world = try TestWorld()
        let task = world.makeTask("No checklist")
        #expect(task.subtaskCompletionFraction == 0)
    }

    @Test("Fraction is completed over total, computed live")
    func fractionPartial() throws {
        let world = try TestWorld()
        let task = world.makeTask("Checklist")
        for index in 0..<4 {
            let subtask = Subtask(title: "Step \(index)", isCompleted: index < 1, sortOrder: index, task: task)
            world.context.insert(subtask)
        }
        try? world.context.save()
        #expect(task.subtaskCompletionFraction == 0.25)
    }

    @Test("All sub-tasks complete reads as 1")
    func fractionFull() throws {
        let world = try TestWorld()
        let task = world.makeTask("Checklist")
        for index in 0..<2 {
            let subtask = Subtask(title: "Step \(index)", isCompleted: true, sortOrder: index, task: task)
            world.context.insert(subtask)
        }
        try? world.context.save()
        #expect(task.subtaskCompletionFraction == 1)
    }

    @Test("Copy carries title, colour, duration and sub-task titles into the same list/project")
    func duplicateCopiesFields() throws {
        let world = try TestWorld()
        let list = TaskList(name: "Personal", iconName: "tray", colourToken: ColourToken.violet.rawValue, sortOrder: 0)
        world.context.insert(list)
        let project = Project(title: "Learning", colourToken: ColourToken.blue.rawValue, sortOrder: 0)
        world.context.insert(project)

        let original = FlowTask(
            title: "Reading",
            estimatedMinutes: 45,
            colourToken: ColourToken.blue.rawValue,
            sortOrder: 3,
            list: list,
            project: project
        )
        world.context.insert(original)
        world.context.insert(Subtask(title: "Choose chapter", isCompleted: true, sortOrder: 0, task: original))
        world.context.insert(Subtask(title: "Read 10 pages", isCompleted: false, sortOrder: 1, task: original))
        try? world.context.save()

        let copy = TaskRowView.duplicate(original, in: world.context)

        #expect(copy.title == "Reading")
        #expect(copy.colourToken == ColourToken.blue.rawValue)
        #expect(copy.estimatedMinutes == 45)
        #expect(copy.list?.id == list.id)
        #expect(copy.project?.id == project.id)
        #expect(copy.orderedSubtasks.map(\.title) == ["Choose chapter", "Read 10 pages"])
    }

    @Test("Copy never carries completion state or schedule, even when the original has both")
    func duplicateResetsCompletionAndSchedule() throws {
        let world = try TestWorld()
        let original = world.makeTask("Deep Work", status: .planned)
        original.dueDate = world.date(hour: 9)
        original.markCompleted(at: world.date(hour: 10))
        world.context.insert(Subtask(title: "Define deliverable", isCompleted: true, sortOrder: 0, task: original))
        try? world.context.save()

        let copy = TaskRowView.duplicate(original, in: world.context)

        #expect(copy.status == .inbox)
        #expect(copy.completedAt == nil)
        #expect(copy.dueDate == nil)
        #expect(copy.liveSegments.isEmpty)
        // The marker guarded by the negative test below: a fresh copy's
        // sub-tasks always start unticked, regardless of the original's state.
        #expect(copy.orderedSubtasks.allSatisfy { $0.isCompleted == false })
    }

    @Test("Tomorrow's start is midnight the day after, regardless of the time of day passed in")
    func tomorrowStartMaths() throws {
        let world = try TestWorld()
        let lateEvening = world.date(hour: 23, minute: 45)
        let tomorrow = TaskRowView.tomorrowStart(after: lateEvening, calendar: world.calendar)

        let expected = world.date(hour: 0, dayOffset: 1)
        #expect(tomorrow == expected)
        #expect(world.calendar.component(.hour, from: tomorrow) == 0)
        #expect(world.calendar.isDate(tomorrow, inSameDayAs: world.date(hour: 0, dayOffset: 1)))
    }
}
