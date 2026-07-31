import Foundation
import SwiftData
import Testing
@testable import Flowmap

/// The initiative card must stop counting a project's work the moment it is
/// untracked — `ProgressMetrics.initiativeTaskCounts(tasks:)` is the single
/// place that filter lives, so the card's `done/total` and the counting
/// logic can never disagree.
@MainActor
struct StatsTrackingTests {
    private func world() throws -> TestWorld { try TestWorld() }

    @Test func untrackedProjectsTasksAreExcludedFromCompletedAndTotal() throws {
        let world = try world()
        let tracked = Project(title: "Tracked")
        let untracked = Project(title: "Untracked")
        untracked.isTrackedInStats = false
        world.context.insert(tracked)
        world.context.insert(untracked)

        let trackedDone = FlowTask(title: "Tracked done", project: tracked)
        trackedDone.markCompleted()
        let trackedOpen = FlowTask(title: "Tracked open", project: tracked)
        let untrackedDone = FlowTask(title: "Untracked done", project: untracked)
        untrackedDone.markCompleted()
        let untrackedOpen = FlowTask(title: "Untracked open", project: untracked)
        for task in [trackedDone, trackedOpen, untrackedDone, untrackedOpen] {
            world.context.insert(task)
        }
        try world.context.save()

        let counts = ProgressMetrics.initiativeTaskCounts(
            tasks: [trackedDone, trackedOpen, untrackedDone, untrackedOpen]
        )

        #expect(counts.total == 2)
        #expect(counts.completed == 1)
    }

    @Test func aTaskWithNoProjectIsIncluded() throws {
        let world = try world()
        let projectLess = FlowTask(title: "No project")
        world.context.insert(projectLess)
        try world.context.save()

        let counts = ProgressMetrics.initiativeTaskCounts(tasks: [projectLess])

        #expect(counts.total == 1)
    }

    @Test func newProjectsAreTrackedByDefault() throws {
        let project = Project(title: "Whatever")
        #expect(project.isTrackedInStats == true)
    }
}
