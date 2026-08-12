import SwiftData
import Testing
@testable import Flowmap

@Suite("Task hierarchy")
@MainActor
struct TaskHierarchyTests {
    @Test("Parent and ordered children persist as FlowTask relationships")
    func relationPersists() throws {
        let world = try TestWorld()
        let parent = FlowTask(title: "Launch", sortOrder: 0)
        let later = FlowTask(title: "Publish", sortOrder: 2)
        let earlier = FlowTask(title: "Review", sortOrder: 1)

        #expect(TaskCreationService.insert(parent, in: world.context))
        #expect(TaskCreationService.insert(later, parent: parent, in: world.context))
        #expect(TaskCreationService.insert(earlier, parent: parent, in: world.context))

        let verification = ModelContext(world.container)
        let tasks = try verification.fetch(FetchDescriptor<FlowTask>())
        guard let restoredParent = tasks.first(where: { $0.id == parent.id }),
              let restoredEarlier = tasks.first(where: { $0.id == earlier.id })
        else {
            Issue.record("Saved hierarchy was not fetched from a fresh context")
            return
        }

        #expect(restoredEarlier.parentTask?.id == parent.id)
        #expect(restoredParent.orderedChildTasks.map(\.title) == ["Review", "Publish"])
        #expect(restoredParent.hierarchyDepth == 0)
        #expect(restoredParent.descendantHeight == 1)
        #expect(restoredEarlier.hierarchyDepth == 1)
    }

    @Test("Self, descendant cycles and a fourth level are rejected")
    func invalidParentsAreRejected() throws {
        let world = try TestWorld()
        let root = FlowTask(title: "Root")
        let child = FlowTask(title: "Child")
        let grandchild = FlowTask(title: "Grandchild")

        #expect(TaskCreationService.insert(root, in: world.context))
        #expect(TaskCreationService.insert(child, parent: root, in: world.context))
        #expect(TaskCreationService.insert(grandchild, parent: child, in: world.context))

        #expect(root.hierarchyDepth == 0)
        #expect(child.hierarchyDepth == 1)
        #expect(grandchild.hierarchyDepth == 2)
        #expect(root.descendantHeight == 2)

        #expect(!root.canAssignParent(root))
        #expect(!root.assignParent(grandchild))
        #expect(!child.assignParent(grandchild))
        #expect(root.parentTask == nil)
        #expect(child.parentTask?.id == root.id)

        let fourth = FlowTask(title: "Fourth")
        #expect(!TaskCreationService.insert(fourth, parent: grandchild, in: world.context))
        let savedIDs = try world.context.fetch(FetchDescriptor<FlowTask>()).map(\.id)
        #expect(!savedIDs.contains(fourth.id))
    }

    @Test("A child inherits its parent's context and initial colour")
    func parentContextIsInherited() throws {
        let world = try TestWorld()
        let workspace = Workspace(name: "Work")
        let list = TaskList(name: "Next", workspace: workspace)
        let project = Project(title: "Launch", colourToken: ColourToken.peach.rawValue, workspace: workspace)
        let parent = FlowTask(
            title: "Campaign",
            colourToken: ColourToken.peach.rawValue,
            list: list,
            project: project,
            workspace: workspace
        )
        world.context.insert(workspace)
        world.context.insert(list)
        world.context.insert(project)
        #expect(TaskCreationService.insert(parent, in: world.context))

        let child = FlowTask(title: "Write copy", colourToken: ColourToken.violet.rawValue)
        #expect(TaskCreationService.insert(child, parent: parent, in: world.context))

        #expect(child.parentTask?.id == parent.id)
        #expect(child.workspace?.id == workspace.id)
        #expect(child.list?.id == list.id)
        #expect(child.project?.id == project.id)
        #expect(child.colourToken == parent.colourToken)
    }

    @Test("Deleting a parent promotes its children without deleting descendants")
    func parentDeletionNullifiesChildren() throws {
        let world = try TestWorld()
        let parent = FlowTask(title: "Parent")
        let child = FlowTask(title: "Child")
        let grandchild = FlowTask(title: "Grandchild")
        #expect(TaskCreationService.insert(parent, in: world.context))
        #expect(TaskCreationService.insert(child, parent: parent, in: world.context))
        #expect(TaskCreationService.insert(grandchild, parent: child, in: world.context))

        world.context.delete(parent)
        try world.context.save()

        let verification = ModelContext(world.container)
        let survivors = try verification.fetch(FetchDescriptor<FlowTask>())
        guard let promotedChild = survivors.first(where: { $0.id == child.id }),
              let survivingGrandchild = survivors.first(where: { $0.id == grandchild.id })
        else {
            Issue.record("Nullify deletion removed a descendant")
            return
        }

        #expect(survivors.count == 2)
        #expect(promotedChild.parentTask == nil)
        #expect(survivingGrandchild.parentTask?.id == promotedChild.id)
        #expect(promotedChild.hierarchyDepth == 0)
        #expect(survivingGrandchild.hierarchyDepth == 1)
    }

    @Test("Backup restores task parents after all tasks exist")
    func backupRoundTripRestoresParent() throws {
        let source = try TestWorld()
        let parent = FlowTask(title: "Parent")
        let child = FlowTask(title: "Child")
        #expect(TaskCreationService.insert(parent, in: source.context))
        #expect(TaskCreationService.insert(child, parent: parent, in: source.context))

        let archive = try BackupService.validate(BackupService.export(from: source.context))
        let destination = try TestWorld()
        try BackupService.importArchive(archive, into: destination.context)

        let tasks = try destination.context.fetch(FetchDescriptor<FlowTask>())
        guard let restoredChild = tasks.first(where: { $0.title == "Child" }) else {
            Issue.record("Imported child was not found")
            return
        }
        #expect(restoredChild.parentTask?.title == "Parent")
    }
}
