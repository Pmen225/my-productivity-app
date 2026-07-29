import Foundation
import SwiftData
import Testing
@testable import Flowmap

/// An initiative owns no work of its own: everything it reports is walked down
/// through its projects, so the number can never disagree with the tasks.
@MainActor
struct InitiativeTests {
    private func world() throws -> TestWorld { try TestWorld() }

    @Test func anInitiativeWithNoProjectsHasNotStarted() throws {
        let world = try world()
        let initiative = Initiative(title: "Ship v1")
        world.context.insert(initiative)

        #expect(initiative.progress == 0)
        #expect(initiative.isComplete == false)
    }

    @Test func progressCountsEveryTaskUnderEveryProject() throws {
        let world = try world()
        let initiative = Initiative(title: "Ship v1")
        let site = Project(title: "Marketing site")
        let onboarding = Project(title: "Onboarding")
        world.context.insert(initiative)
        world.context.insert(site)
        world.context.insert(onboarding)
        site.initiative = initiative
        onboarding.initiative = initiative

        let done = FlowTask(title: "Write copy", project: site)
        done.markCompleted()
        world.context.insert(done)
        world.context.insert(FlowTask(title: "Design hero", project: site))
        world.context.insert(FlowTask(title: "Welcome email", project: onboarding))
        try world.context.save()

        #expect(initiative.actionableTasks.count == 3)
        #expect(initiative.completedTaskCount == 1)
        #expect(initiative.progressPercentText == "33%")
        #expect(initiative.isComplete == false)
    }

    @Test func itIsCompleteOnlyWhenEveryTaskUnderItIs() throws {
        let world = try world()
        let initiative = Initiative(title: "Ship v1")
        let project = Project(title: "Marketing site")
        world.context.insert(initiative)
        world.context.insert(project)
        project.initiative = initiative

        let task = FlowTask(title: "Write copy", project: project)
        world.context.insert(task)
        try world.context.save()
        #expect(initiative.isComplete == false)

        task.markCompleted()
        try world.context.save()
        #expect(initiative.isComplete)
        #expect(initiative.progress == 1)
    }

    /// Dropping the goal must not delete the work done toward it.
    @Test func deletingTheInitiativeLeavesItsProjectsAlone() throws {
        let world = try world()
        let initiative = Initiative(title: "Ship v1")
        let project = Project(title: "Marketing site")
        world.context.insert(initiative)
        world.context.insert(project)
        project.initiative = initiative
        try world.context.save()

        world.context.delete(initiative)
        try world.context.save()

        #expect(project.initiative == nil)
        let remaining = try world.context.fetch(FetchDescriptor<Project>())
        #expect(remaining.count == 1)
    }
}
