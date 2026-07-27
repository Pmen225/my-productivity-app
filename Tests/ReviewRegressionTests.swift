import Foundation
import SwiftData
import Testing
@testable import Flowmap

/// Covers the invariants that the code review found were only *intended*, not
/// enforced. Each test here failed against the code as reviewed.
@Suite("Review regressions")
@MainActor
struct ReviewRegressionTests {

    @Test("A block running through midnight still blocks the next morning")
    func midnightSpanningBusyTimeIsSeen() throws {
        // A day that starts early enough for an overnight block to collide.
        let world = try TestWorld(workdayStartHour: 5, workdayEndHour: 21)

        // 22:00 yesterday → 06:00 today. Bucketed under yesterday's key.
        let overnight = world.makeTask("Night shift", minutes: 480)
        world.makeSegment(
            for: overnight,
            start: world.date(hour: 22, dayOffset: -1),
            minutes: 480,
            locked: true
        )

        let morning = world.makeTask("Morning work", minutes: 60)
        let now = world.date(hour: 5)

        let service = world.service()
        service.apply(service.proposePlan(for: now, now: now), for: now)

        #expect(hasNoOverlaps(world.allSegments))
        for segment in world.liveSegments(of: morning) {
            #expect(segment.startDate >= world.date(hour: 6))
        }
    }

    @Test("A manual drop onto a block that started yesterday is refused")
    func canPlaceSeesOvernightBlocks() throws {
        let world = try TestWorld(workdayStartHour: 5, workdayEndHour: 21)
        let overnight = world.makeTask("Night shift", minutes: 480)
        world.makeSegment(for: overnight, start: world.date(hour: 22, dayOffset: -1), minutes: 480)

        let service = world.service()
        // 05:30 today sits inside the 22:00–06:00 block.
        #expect(service.canPlace(minutes: 30, at: world.date(hour: 5, minute: 30)) == false)
        // 06:30 is clear of it.
        #expect(service.canPlace(minutes: 30, at: world.date(hour: 6, minute: 30)) == true)
    }

    @Test("A full replan never leaves a task planned with no time")
    func replanReturnsUnplaceableWorkToTheInbox() throws {
        let world = try TestWorld()
        let now = world.date(hour: 8)

        // Fills the whole working day and cannot be moved.
        let blocker = world.makeTask("All day", minutes: 780)
        world.makeSegment(for: blocker, start: world.date(hour: 8), minutes: 780, locked: true)

        // Already placed, but with a window that has since closed, so a replan
        // lifts it and then cannot put it back anywhere.
        let stranded = world.makeTask("Stranded", minutes: 60, splittable: false)
        stranded.latestFinish = world.date(hour: 9)
        world.makeSegment(for: stranded, start: world.date(hour: 8), minutes: 60)
        stranded.status = .planned

        let service = world.service()
        service.apply(
            service.proposePlan(for: now, now: now, replanExisting: true),
            replanExisting: true,
            for: now
        )

        // It must be visible somewhere. A `.planned` task with no segments
        // matches neither Inbox nor Today, so it would have vanished.
        if world.liveSegments(of: stranded).isEmpty {
            #expect(stranded.status == .inbox)
        }
    }

    @Test("Importing an older backup does not reparent a newer local node")
    func staleImportDoesNotReparentNewerNodes() throws {
        let source = try TestWorld()
        let map = MapDocument(title: "Plan")
        source.context.insert(map)
        let root = MapNode(title: "Root", map: map)
        let branchA = MapNode(title: "A", map: map, parent: root)
        let branchB = MapNode(title: "B", map: map, parent: root)
        let leaf = MapNode(title: "Leaf", map: map, parent: branchA)
        for node in [root, branchA, branchB, leaf] { source.context.insert(node) }
        try source.context.save()

        let archive = try BackupService.validate(try BackupService.export(from: source.context))

        let destination = try TestWorld()
        try BackupService.importArchive(archive, into: destination.context)

        // The user then moves the leaf under B and that edit is newer.
        let nodes = try destination.context.fetch(FetchDescriptor<MapNode>())
        guard let localLeaf = nodes.first(where: { $0.title == "Leaf" }),
              let localB = nodes.first(where: { $0.title == "B" })
        else {
            Issue.record("Imported nodes were not found")
            return
        }
        localLeaf.parent = localB
        localLeaf.updatedAt = Date().addingTimeInterval(3600)
        try destination.context.save()

        // Re-importing the same, now-older archive must not drag it back.
        try BackupService.importArchive(archive, into: destination.context)
        #expect(localLeaf.parent?.title == "B")
    }

    @Test("A cyclic parent in a backup cannot be imported, and reading is safe")
    func cyclicParentIsRejected() throws {
        let source = try TestWorld()
        let map = MapDocument(title: "Plan")
        source.context.insert(map)
        let root = MapNode(title: "Root", map: map)
        let child = MapNode(title: "Child", map: map, parent: root)
        source.context.insert(root)
        source.context.insert(child)
        try source.context.save()

        var archive = try BackupService.validate(try BackupService.export(from: source.context))

        // Corrupt it the way a hand-edited or truncated file could: the root now
        // claims its own descendant as its parent.
        archive.mapNodes = archive.mapNodes.map { node in
            guard node.title == "Root" else { return node }
            var copy = node
            copy.parentID = archive.mapNodes.first { $0.title == "Child" }?.id
            return copy
        }

        let destination = try TestWorld()
        try BackupService.importArchive(archive, into: destination.context)

        let nodes = try destination.context.fetch(FetchDescriptor<MapNode>())
        guard let importedRoot = nodes.first(where: { $0.title == "Root" }) else {
            Issue.record("Root was not imported")
            return
        }
        // The cycle was refused, and walking the tree terminates either way.
        #expect(importedRoot.parent == nil)
        #expect(importedRoot.subtreeNodes.count <= nodes.count)
    }

    @Test("Seeding twice creates exactly one demo workspace")
    func seedIsIdempotent() throws {
        let world = try TestWorld()

        SeedData.load(into: world.context, settings: world.settings)
        let firstTaskCount = (try world.context.fetch(FetchDescriptor<FlowTask>())).count

        SeedData.load(into: world.context, settings: world.settings)
        let secondTaskCount = (try world.context.fetch(FetchDescriptor<FlowTask>())).count

        let workspaces = try world.context.fetch(FetchDescriptor<Workspace>())
        #expect(workspaces.count == 1)
        #expect(firstTaskCount == secondTaskCount)
        #expect(firstTaskCount == 7)
    }
}
