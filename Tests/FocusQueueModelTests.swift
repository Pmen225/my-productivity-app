import Foundation
import SwiftData
import Testing
@testable import Flowmap

/// `FocusQueueModel` is the pure derivation behind Task 58's now-bar and its
/// queue sheet (founder ruling 2026-08-08, option B). `@MainActor` because it
/// is built through `TestWorld`, which is main-actor isolated.
@MainActor
@Suite("Focus queue model: bar fallback chain and sheet seeding")
struct FocusQueueModelTests {
    @Test("Case 1: active task with an incomplete subtask names that subtask, captioned with its progress")
    func activeTaskWithIncompleteSubtaskNamesTheSubtask() throws {
        let world = try TestWorld()
        let task = world.makeTask("Write report", minutes: 30)
        let first = Subtask(title: "Outline", isCompleted: true, sortOrder: 0, task: task)
        let second = Subtask(title: "Draft intro", isCompleted: false, sortOrder: 1, task: task)
        world.context.insert(first)
        world.context.insert(second)
        try world.context.save()

        let model = FocusQueueModel(queue: [], activeTask: task, activeSegmentID: nil)

        #expect(model.isBarVisible)
        #expect(model.barTitle == "Draft intro")
        #expect(model.barCaption == "1 of 2")
    }

    @Test("Case 2a: active task with no checklist falls back to its own title")
    func activeTaskWithNoChecklistNamesTheTask() throws {
        let world = try TestWorld()
        let task = world.makeTask("Plan the week", minutes: 20)

        let model = FocusQueueModel(queue: [], activeTask: task, activeSegmentID: nil)

        #expect(model.isBarVisible)
        #expect(model.barTitle == "Plan the week")
        #expect(model.barCaption == "Ready to finish")
    }

    @Test("Case 2b: active task whose checklist is entirely complete also falls back to its own title")
    func activeTaskWithCompletedChecklistNamesTheTask() throws {
        let world = try TestWorld()
        let task = world.makeTask("Plan the week", minutes: 20)
        let subtask = Subtask(title: "Review calendar", isCompleted: true, sortOrder: 0, task: task)
        world.context.insert(subtask)
        try world.context.save()

        let model = FocusQueueModel(queue: [], activeTask: task, activeSegmentID: nil)

        #expect(model.barTitle == "Plan the week")
        #expect(model.barCaption == "Ready to finish")
    }

    @Test("Case 3: no active task but a non-empty queue names the queue")
    func noActiveTaskWithQueueNamesTheQueue() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30)
        let start = world.date(hour: 9)
        let segment = world.makeSegment(for: task, start: start, minutes: 30)

        let model = FocusQueueModel(queue: [segment], activeTask: nil, activeSegmentID: nil)

        #expect(model.isBarVisible)
        #expect(model.barTitle == "Today's queue")
        #expect(model.barCaption == "1 tasks")
    }

    @Test("Case 4: no active task and an empty queue means the bar does not show")
    func noActiveTaskNoQueueHidesTheBar() {
        let model = FocusQueueModel(queue: [], activeTask: nil, activeSegmentID: nil)

        #expect(model.isBarVisible == false)
        #expect(model.barTitle == "")
        #expect(model.barCaption == "")
    }

    @Test("A fresh sheet presentation seeds its expanded row from the active segment")
    func expandedIDSeedsFromActiveSegment() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30)
        let start = world.date(hour: 9)
        let segment = world.makeSegment(for: task, start: start, minutes: 30)

        let model = FocusQueueModel(queue: [segment], activeTask: task, activeSegmentID: segment.id)

        #expect(model.initiallyExpandedSegmentID == segment.id)
    }

    @Test("With nothing active, the sheet seeds to nothing expanded")
    func expandedIDIsNilWithNoActiveSegment() {
        let model = FocusQueueModel(queue: [], activeTask: nil, activeSegmentID: nil)

        #expect(model.initiallyExpandedSegmentID == nil)
    }
}
