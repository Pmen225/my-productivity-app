import CoreGraphics
import Foundation
import Testing
@testable import Flowmap

/// The Calendar page's two pieces of pure logic: the month grid's swipe, and
/// the Weekly Plan's grouping.
@MainActor
struct CalendarPageTests {

    // MARK: - Month grid swipe (decision 17)

    @Test func aDragPastTheThresholdStepsAMonth() {
        #expect(CalendarDateMath.monthStep(forDrag: CGSize(width: -60, height: 4)) == 1)
        #expect(CalendarDateMath.monthStep(forDrag: CGSize(width: 60, height: 4)) == -1)
    }

    @Test func aShortDragStepsNothing() {
        #expect(CalendarDateMath.monthStep(forDrag: CGSize(width: -49, height: 0)) == 0)
        #expect(CalendarDateMath.monthStep(forDrag: CGSize(width: 49, height: 0)) == 0)
    }

    /// The whole vertical-versus-horizontal conflict: a drag heading down the
    /// screen belongs to the panel underneath, not to the grid.
    @Test func aMostlyVerticalDragStepsNothing() {
        #expect(CalendarDateMath.monthStep(forDrag: CGSize(width: -80, height: 120)) == 0)
        #expect(CalendarDateMath.monthStep(forDrag: CGSize(width: 80, height: -120)) == 0)
    }

    // MARK: - Weekly Plan grouping

    @Test func aTaskWithNoMapNodeFallsBackToItsProject() throws {
        let world = try TestWorld()
        let project = Project(title: "Website")
        world.context.insert(project)

        let task = world.makeTask("Write the brief", minutes: 30)
        task.project = project
        world.makeSegment(for: task, start: world.date(hour: 10), minutes: 30)

        let groups = CalendarWeeklyPlan.groups(
            segments: world.allSegments,
            week: CalendarDateMath.weekInterval(containing: world.date(hour: 10), calendar: world.calendar)
        )

        #expect(groups.map(\.title) == ["Website"])
    }

    /// A split task holds several segments in one week. The row stands for the
    /// task, so it must appear exactly once.
    @Test func aTaskSplitAcrossTheWeekAppearsOnce() throws {
        let world = try TestWorld()
        let task = world.makeTask("Long write-up", minutes: 90)
        world.makeSegment(for: task, start: world.date(hour: 9), minutes: 45)
        world.makeSegment(for: task, start: world.date(hour: 9, dayOffset: 1), minutes: 45)

        let groups = CalendarWeeklyPlan.groups(
            segments: world.allSegments,
            week: CalendarDateMath.weekInterval(containing: world.date(hour: 9), calendar: world.calendar)
        )

        #expect(groups.flatMap(\.items).count == 1)
    }

    @Test func workOutsideTheWeekIsLeftOut() throws {
        let world = try TestWorld()
        let task = world.makeTask("Next month", minutes: 30)
        world.makeSegment(for: task, start: world.date(hour: 9, dayOffset: 21), minutes: 30)

        let groups = CalendarWeeklyPlan.groups(
            segments: world.allSegments,
            week: CalendarDateMath.weekInterval(containing: world.date(hour: 9), calendar: world.calendar)
        )

        #expect(groups.isEmpty)
    }

    /// A completed task still holds its slot on the timeline, so it stays in
    /// the plan — struck through, which is why the flag has to survive.
    @Test func aCompletedTaskStaysInThePlanAsDone() throws {
        let world = try TestWorld()
        let task = world.makeTask("Ship it", minutes: 30)
        world.makeSegment(for: task, start: world.date(hour: 9), minutes: 30, state: .completed)
        task.status = .completed

        let groups = CalendarWeeklyPlan.groups(
            segments: world.allSegments,
            week: CalendarDateMath.weekInterval(containing: world.date(hour: 9), calendar: world.calendar)
        )

        #expect(groups.flatMap(\.items).first?.isCompleted == true)
    }

    @Test func cancelledWorkIsLeftOut() throws {
        let world = try TestWorld()
        let task = world.makeTask("Dropped", minutes: 30)
        world.makeSegment(for: task, start: world.date(hour: 9), minutes: 30, state: .cancelled)

        let groups = CalendarWeeklyPlan.groups(
            segments: world.allSegments,
            week: CalendarDateMath.weekInterval(containing: world.date(hour: 9), calendar: world.calendar)
        )

        #expect(groups.isEmpty)
    }
}
