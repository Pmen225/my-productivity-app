import Foundation
import SwiftData
import Testing
@testable import Flowmap

/// `@MainActor` because `LibraryView` is a `View`, so its statics are
/// main-actor isolated (the same trap `LibraryAccordionTests` already notes).
@MainActor
@Suite("Notes attach — T6 stage 2")
struct NotesAttachTests {
    @Test("Attaching sets note.task to the chosen task")
    func attachSetsTask() throws {
        let world = try TestWorld()
        let note = Note(title: "Meeting notes")
        world.context.insert(note)
        let task = world.makeTask("Write agenda")
        try world.context.save()

        let result = LibraryView.attachToggleResult(current: note.task, tapped: task)

        #expect(result?.id == task.id)
    }

    @Test("Tapping the currently-attached task's chip detaches it")
    func tappingAttachedChipDetaches() throws {
        let world = try TestWorld()
        let task = world.makeTask("Write agenda")
        let note = Note(title: "Meeting notes", task: task)
        world.context.insert(note)
        try world.context.save()

        let result = LibraryView.attachToggleResult(current: note.task, tapped: task)

        #expect(result == nil)
    }

    @Test("Choosing a different task while one is attached re-assigns rather than adding")
    func choosingDifferentTaskReassigns() throws {
        let world = try TestWorld()
        let first = world.makeTask("Write agenda")
        let second = world.makeTask("Book room")
        let note = Note(title: "Meeting notes", task: first)
        world.context.insert(note)
        try world.context.save()

        let result = LibraryView.attachToggleResult(current: note.task, tapped: second)

        #expect(result?.id == second.id)
        // Single-select: the note ends up pointed at exactly one task, never
        // holding onto the old one alongside the new choice.
        #expect(result?.id != first.id)
    }

    @Test("Candidate tasks exclude completed and cancelled work")
    func candidatesExcludeClosedWork() throws {
        let world = try TestWorld()
        let open = world.makeTask("Open one")
        _ = world.makeTask("Done", status: .completed)
        _ = world.makeTask("Abandoned", status: .cancelled)
        let allTasks = try world.context.fetch(FetchDescriptor<FlowTask>())

        let candidates = LibraryView.noteAttachCandidates(in: allTasks)

        #expect(candidates.map(\.id) == [open.id])
    }

    @Test("A task that closes after being attached stays in the picker for detachment")
    func closedAttachedTaskStaysVisibleForDetach() throws {
        let world = try TestWorld()
        let open = world.makeTask("Open one")
        let wasAttached = world.makeTask("Now completed", status: .completed)
        let allTasks = try world.context.fetch(FetchDescriptor<FlowTask>())
        let candidates = LibraryView.noteAttachCandidates(in: allTasks)
        // Confirms the fixture: the completed task really is excluded from
        // the raw candidate list before checking the merge restores it.
        #expect(!candidates.contains { $0.id == wasAttached.id })

        let merged = NoteAttachCandidates.display(candidates, attached: wasAttached)

        #expect(merged.contains { $0.id == wasAttached.id })
        #expect(merged.contains { $0.id == open.id })
        // Already-open candidates are not duplicated when nothing needs merging.
        #expect(NoteAttachCandidates.display(candidates, attached: open).count == candidates.count)
    }

    @Test("Notes count excludes archived and trashed notes")
    func countExcludesArchivedAndTrashed() throws {
        let world = try TestWorld()
        let active = Note(title: "Keep me")
        let archived = Note(title: "Archived")
        archived.isArchived = true
        let trashed = Note(title: "Trashed")
        trashed.isTrashed = true
        world.context.insert(active)
        world.context.insert(archived)
        world.context.insert(trashed)
        try world.context.save()

        let allNotes = try world.context.fetch(FetchDescriptor<Note>())
        let visible = LibraryView.noteAccordionContent(in: allNotes)

        #expect(visible.map(\.id) == [active.id])
    }
}
