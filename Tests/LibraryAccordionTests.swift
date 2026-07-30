import Foundation
import SwiftData
import Testing
@testable import Flowmap

/// `@MainActor` because `LibraryView` is a `View`, so its statics are
/// main-actor isolated (the same trap `DurationWheelTests` already notes).
@MainActor
@Suite("Plan page accordion")
struct LibraryAccordionTests {
    @Test("Completed's empty copy is the mockup's own wording")
    func completedEmptyMessage() {
        #expect(SmartView.completed.emptyMessage == "Nothing completed yet.")
    }

    @Test("A row's count and its unfolded rows read the same tasks, so they cannot disagree")
    func countMatchesUnfoldedRows() throws {
        let world = try TestWorld()
        let today = world.date(hour: 9)
        let todayTask1 = world.makeTask("Today one", flaggedForToday: true)
        let todayTask2 = world.makeTask("Today two", flaggedForToday: true)
        let elsewhere = world.makeTask("Not today")
        _ = elsewhere

        let allTasks = try world.context.fetch(FetchDescriptor<FlowTask>())
        let content = LibraryView.taskAccordionContent(for: .today, in: allTasks, now: today)

        #expect(content.count == SmartView.today.matches(allTasks, now: today).count)
        #expect(Set(content.map(\.id)) == Set([todayTask1.id, todayTask2.id]))
    }

    @Test("Inbox is not one of the TASKS section's accordion rows")
    func inboxExcludedFromAccordions() {
        #expect(!LibraryView.taskAccordionViews.contains(.inbox))
        #expect(LibraryView.taskAccordionViews.count == 6)
    }
}
