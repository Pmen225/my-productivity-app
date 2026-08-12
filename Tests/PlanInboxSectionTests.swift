import Foundation
import SwiftData
import Testing
@testable import Flowmap

/// `@MainActor` because `PlanInboxSection` is a `View`, so its statics are
/// main-actor isolated (the same trap `DurationWheelTests` and
/// `TaskRowViewTests` already note).
@MainActor
@Suite("Plan inbox: hierarchy and Today actions")
struct PlanInboxSectionTests {
    @Test("Dependencies sit immediately below their visible parent")
    func dependenciesFollowParent() throws {
        let world = try TestWorld()
        let parent = world.makeTask("Main task")
        let firstDependency = world.makeTask("First dependency")
        let secondDependency = world.makeTask("Second dependency")
        let independent = world.makeTask("Independent task")

        firstDependency.sortOrder = 0
        secondDependency.sortOrder = 1
        #expect(firstDependency.assignParent(parent))
        #expect(secondDependency.assignParent(parent))

        let rows = PlanInboxSection.hierarchyRows(
            for: [parent, firstDependency, secondDependency, independent]
        )

        #expect(rows.map { $0.task.title } == [
            "Main task",
            "First dependency",
            "Second dependency",
            "Independent task"
        ])
        #expect(rows.map(\.depth) == [0, 1, 1, 0])
        #expect(rows.indices.map { PlanInboxSection.hierarchyPosition(at: $0, in: rows) } == [
            .groupRoot,
            .groupMiddle,
            .groupEnd,
            .standalone
        ])
    }

    @Test("A dependency whose parent is off this page remains visible as a root")
    func filteredParentDoesNotHideDependency() throws {
        let world = try TestWorld()
        let parent = world.makeTask("Parent elsewhere")
        let dependency = world.makeTask("Visible dependency")
        #expect(dependency.assignParent(parent))

        let rows = PlanInboxSection.hierarchyRows(for: [dependency])

        #expect(rows.map { $0.task.title } == ["Visible dependency"])
        #expect(rows.map(\.depth) == [0])
    }

    @Test("Nested dependencies stay in pre-order without duplicate rows")
    func nestedDependenciesStayGrouped() throws {
        let world = try TestWorld()
        let parent = world.makeTask("Parent")
        let child = world.makeTask("Child")
        let grandchild = world.makeTask("Grandchild")
        #expect(child.assignParent(parent))
        #expect(grandchild.assignParent(child))

        let rows = PlanInboxSection.hierarchyRows(for: [grandchild, child, parent])

        #expect(rows.map { $0.task.title } == ["Parent", "Child", "Grandchild"])
        #expect(rows.map(\.depth) == [0, 1, 2])
        #expect(Set(rows.map(\.id)).count == 3)
        #expect(rows.indices.map { PlanInboxSection.hierarchyPosition(at: $0, in: rows) } == [
            .groupRoot,
            .groupMiddle,
            .groupEnd
        ])
    }

    @Test("Moving an inbox task to Today flags it, and Today's smart view then matches it")
    func moveToTodayFlagsTask() throws {
        let world = try TestWorld()
        let task = world.makeTask("Draft proposal")
        let now = world.date(hour: 9)

        #expect(task.isFlaggedForToday == false)
        #expect(SmartView.today.matches([task], now: now, calendar: world.calendar).isEmpty)

        PlanInboxSection.moveToToday(task, in: world.context)

        #expect(task.isFlaggedForToday == true)
        #expect(SmartView.today.matches([task], now: now, calendar: world.calendar).map(\.id) == [task.id])
    }
}
