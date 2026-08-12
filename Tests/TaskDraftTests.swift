import Foundation
import SwiftData
import Testing
@testable import Flowmap

/// `TaskDraft` is the seam `TaskDetailInspector`'s creation mode writes
/// through: insert a blank `FlowTask`, apply the seed, then either keep it
/// (Done with a real title) or discard it (Cancel, or Done/dismissal with an
/// empty title). These tests exercise that seam directly, without any
/// SwiftUI view — the one-task-card spec's minimum coverage, cases 1–7.
@MainActor
@Suite("TaskDraft")
struct TaskDraftTests {
    @Test("Cancelling a draft leaves zero new tasks")
    func cancelLeavesNoTask() throws {
        let world = try TestWorld()
        let before = try world.context.fetch(FetchDescriptor<FlowTask>()).count

        let task = TaskDraft.makeTask(estimatedMinutes: 30)
        TaskDraft.insert(
            task,
            context: world.context,
            seed: TaskDraft.Seed(),
            projects: [],
            lists: [],
            tasks: [],
            resolvedDueDate: nil,
            shouldFlagToday: false
        )
        TaskDraft.cancel(task, context: world.context)

        let after = try world.context.fetch(FetchDescriptor<FlowTask>()).count
        #expect(after == before)
    }

    @Test("Typing a title then Done keeps exactly one task with that title")
    func doneWithTitleKeepsOneTask() throws {
        let world = try TestWorld()

        let task = TaskDraft.makeTask(estimatedMinutes: 30)
        TaskDraft.insert(
            task,
            context: world.context,
            seed: TaskDraft.Seed(),
            projects: [],
            lists: [],
            tasks: [],
            resolvedDueDate: nil,
            shouldFlagToday: false
        )
        task.title = "Buy milk"
        let kept = TaskDraft.finish(task, context: world.context)

        let after = try world.context.fetch(FetchDescriptor<FlowTask>())
        #expect(kept == true)
        #expect(after.count == 1)
        #expect(after.first?.title == "Buy milk")
    }

    @Test("Leaving the title empty then Done leaves zero tasks")
    func doneWithEmptyTitleDeletesDraft() throws {
        let world = try TestWorld()

        let task = TaskDraft.makeTask(estimatedMinutes: 30)
        TaskDraft.insert(
            task,
            context: world.context,
            seed: TaskDraft.Seed(),
            projects: [],
            lists: [],
            tasks: [],
            resolvedDueDate: nil,
            shouldFlagToday: false
        )
        task.title = "   "
        let kept = TaskDraft.finish(task, context: world.context)

        let after = try world.context.fetch(FetchDescriptor<FlowTask>()).count
        #expect(kept == false)
        #expect(after == 0)
    }

    @Test("A seeded project and list land on the created task")
    func seededProjectAndListApply() throws {
        let world = try TestWorld()
        let project = Project(title: "Launch", sortOrder: 0)
        let list = TaskList(name: "Errands", sortOrder: 0)
        world.context.insert(project)
        world.context.insert(list)

        let task = TaskDraft.makeTask(estimatedMinutes: 30)
        TaskDraft.insert(
            task,
            context: world.context,
            seed: TaskDraft.Seed(projectID: project.id, listID: list.id),
            projects: [project],
            lists: [list],
            tasks: [],
            resolvedDueDate: nil,
            shouldFlagToday: false
        )

        #expect(task.project?.id == project.id)
        #expect(task.list?.id == list.id)
    }

    @Test("Editing an existing task still writes through and creates nothing new")
    func editingExistingTaskCreatesNothingNew() throws {
        let world = try TestWorld()
        let existing = world.makeTask("Existing task")
        let before = try world.context.fetch(FetchDescriptor<FlowTask>()).count

        // The edit-mode write path: mutate the live task directly, exactly as
        // `TaskDetailInspector`'s `@Bindable` body does today — no `TaskDraft`
        // call at all. Also proves `finish`'s empty-title rule cannot delete a
        // task that already has real content, if it were ever mistakenly
        // called on one.
        existing.title = "Existing task — renamed"
        try world.context.save()
        let survivedFinish = TaskDraft.finish(existing, context: world.context)

        let after = try world.context.fetch(FetchDescriptor<FlowTask>())
        #expect(survivedFinish == true)
        #expect(after.count == before)
        #expect(after.first?.title == "Existing task — renamed")
    }

    @Test("An unseeded created task defaults to no list and no project")
    func unseededDefaultsToInboxAndNoProject() throws {
        let world = try TestWorld()

        let task = TaskDraft.makeTask(estimatedMinutes: 30)
        TaskDraft.insert(
            task,
            context: world.context,
            seed: TaskDraft.Seed(),
            projects: [],
            lists: [],
            tasks: [],
            resolvedDueDate: nil,
            shouldFlagToday: false
        )

        #expect(task.list == nil)
        #expect(task.project == nil)
    }

    @Test("A seeded created task keeps its seed, not the unseeded default")
    func seededOverridesDefault() throws {
        let world = try TestWorld()
        let project = Project(title: "Launch", sortOrder: 0)
        let list = TaskList(name: "Errands", sortOrder: 0)
        world.context.insert(project)
        world.context.insert(list)

        let task = TaskDraft.makeTask(estimatedMinutes: 30)
        TaskDraft.insert(
            task,
            context: world.context,
            seed: TaskDraft.Seed(projectID: project.id, listID: list.id),
            projects: [project],
            lists: [list],
            tasks: [],
            resolvedDueDate: nil,
            shouldFlagToday: false
        )

        #expect(task.list?.id == list.id)
        #expect(task.project?.id == project.id)
    }

    @Test("A parent seed creates a real child and inherits the branch context")
    func parentSeedCreatesChild() throws {
        let world = try TestWorld()
        let workspace = Workspace(name: "Work")
        let project = Project(title: "Launch", colourToken: ColourToken.pink.rawValue, workspace: workspace)
        let list = TaskList(name: "Next", workspace: workspace)
        world.context.insert(workspace)
        world.context.insert(project)
        world.context.insert(list)

        let parent = FlowTask(
            title: "Project A",
            colourToken: ColourToken.pink.rawValue,
            list: list,
            project: project,
            workspace: workspace
        )
        #expect(TaskCreationService.insert(parent, in: world.context))

        let child = TaskDraft.makeTask(estimatedMinutes: 30)
        let inserted = TaskDraft.insert(
            child,
            context: world.context,
            seed: TaskDraft.Seed(parentTaskID: parent.id),
            projects: [project],
            lists: [list],
            tasks: [parent],
            resolvedDueDate: nil,
            shouldFlagToday: false
        )

        #expect(inserted)
        #expect(child.parentTask?.id == parent.id)
        #expect(child.project?.id == project.id)
        #expect(child.list?.id == list.id)
        #expect(child.workspace?.id == workspace.id)
        #expect(child.colourToken == parent.colourToken)
    }
}
