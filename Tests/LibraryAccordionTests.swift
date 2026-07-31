import Foundation
import SwiftData
import Testing
@testable import Flowmap

/// `@MainActor` because `LibraryView` is a `View`, so its statics are
/// main-actor isolated (the same trap `DurationWheelTests` already notes).
@MainActor
@Suite("Plan task pages")
struct LibraryAccordionTests {
    @Test("Completed's empty copy is the mockup's own wording")
    func completedEmptyMessage() {
        #expect(SmartView.completed.emptyMessage == "Nothing completed yet.")
    }

    @Test("A task page's rows read the same Smart View filter")
    func pageContentMatchesSmartView() throws {
        let world = try TestWorld()
        let today = world.date(hour: 9)
        let todayTask1 = world.makeTask("Today one", flaggedForToday: true)
        let todayTask2 = world.makeTask("Today two", flaggedForToday: true)
        let elsewhere = world.makeTask("Not today")
        _ = elsewhere

        let allTasks = try world.context.fetch(FetchDescriptor<FlowTask>())
        let content = LibraryView.taskPageContent(for: .today, in: allTasks, now: today)

        #expect(content.count == SmartView.today.matches(allTasks, now: today).count)
        #expect(Set(content.map(\.id)) == Set([todayTask1.id, todayTask2.id]))
    }

    @Test("Task pages keep Inbox first and Completed last")
    func orderedPages() {
        #expect(LibraryView.taskPages.first == .inbox)
        #expect(LibraryView.taskPages.last == .completed)
        #expect(LibraryView.taskPages.map(\.title) == ["Inbox", "Today", "Upcoming", "Anytime", "All tasks", "Completed"])
    }

    @Test("Smart-view menu keeps the five views together and leaves Inbox outside")
    func smartViewMenuPages() {
        #expect(LibraryView.smartTaskPages.map(\.title) == ["Today", "Upcoming", "Anytime", "All tasks", "Completed"])
        #expect(!LibraryView.smartTaskPages.contains(.inbox))
    }

    @Test("Choosing a page changes current page once and is idempotent thereafter")
    func currentPageSelection() {
        let today = LibraryView.taskPageSelection(from: LibraryView.initialTaskPage, choosing: .today)
        #expect(today == .today)
        #expect(LibraryView.taskPageSelection(from: today, choosing: .today) == .today)
    }
}
