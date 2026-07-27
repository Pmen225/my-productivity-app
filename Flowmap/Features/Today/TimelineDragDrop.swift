import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The custom drag payload carried between the Inbox, timeline blocks and the
/// timeline's drop surface. Identifies a task and, when the drag started from
/// an already-scheduled block, the segment being moved.
struct TimelineDragPayload: Codable, Sendable {
    let taskID: UUID
    let segmentID: UUID?
    let minutes: Int

    func itemProvider() -> NSItemProvider {
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.flowmapTimelineItem.identifier,
            visibility: .all
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    /// `completion` touches SwiftData models and view state that are not, and
    /// need not be, `Sendable` — it always runs back on the main actor, right
    /// after `loadDataRepresentation`'s system completion handler fires on an
    /// arbitrary queue. The box carries it across that one hop.
    static func decode(from providers: [NSItemProvider], completion: @escaping (TimelineDragPayload?) -> Void) {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.flowmapTimelineItem.identifier)
        }) else {
            completion(nil)
            return
        }
        let box = SendableBox(completion)
        provider.loadDataRepresentation(forTypeIdentifier: UTType.flowmapTimelineItem.identifier) { data, _ in
            let payload = data.flatMap { try? JSONDecoder().decode(TimelineDragPayload.self, from: $0) }
            DispatchQueue.main.async { box.value(payload) }
        }
    }
}

/// Carries a known-single-threaded closure across one `@Sendable` boundary.
/// `@unchecked` because the compiler cannot see that `value` is only ever
/// invoked once, after the hop back to the main actor.
private struct SendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

extension UTType {
    static var flowmapTimelineItem: UTType {
        UTType(exportedAs: "com.flowmap.timelineitem")
    }
}

// MARK: - View helpers

extension View {
    /// Makes a scheduled block draggable for manual rescheduling. Locked
    /// segments and external events never become drag sources.
    @ViewBuilder
    func draggableTimelineBlock(_ block: TimelineBlock) -> some View {
        if !block.isExternal, !block.isLocked, let segment = block.segment, let task = segment.task {
            self.onDrag {
                TimelineHaptics.dragStarted()
                return TimelineDragPayload(taskID: task.id, segmentID: segment.id, minutes: block.minutes)
                    .itemProvider()
            }
        } else {
            self
        }
    }
}

// MARK: - Drop delegate

/// Tracks the drag as it crosses the timeline, snapping the pointer position
/// to a proposed start time and surfacing it as an insertion preview.
struct TimelineDropDelegate: DropDelegate {
    let dayStart: Date
    let dayEnd: Date
    let pointsPerMinute: CGFloat
    @Binding var previewStart: Date?
    @Binding var previewMinutes: Int?
    let resolveSegment: (UUID) -> TaskSegment?
    let resolveTask: (UUID) -> FlowTask?
    let onSchedule: (FlowTask, Date) -> Bool
    let onMove: (TaskSegment, Date) -> Bool
    let onRefusal: (String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.flowmapTimelineItem])
    }

    private func date(at location: CGPoint) -> Date {
        let rawMinutes = Double(location.y / pointsPerMinute)
        let snappedMinutes = (rawMinutes / 5).rounded() * 5
        let candidate = dayStart.addingTimeInterval(snappedMinutes * 60)
        return min(max(candidate, dayStart), dayEnd)
    }

    func dropEntered(info: DropInfo) {
        TimelineDragPayload.decode(from: info.itemProviders(for: [.flowmapTimelineItem])) { payload in
            previewMinutes = payload?.minutes ?? SchedulingEngine.snapMinutes
        }
        previewStart = date(at: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        previewStart = date(at: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        previewStart = nil
        previewMinutes = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = date(at: info.location)
        TimelineDragPayload.decode(from: info.itemProviders(for: [.flowmapTimelineItem])) { payload in
            defer {
                previewStart = nil
                previewMinutes = nil
            }
            guard let payload else { return }
            if let segmentID = payload.segmentID, let segment = resolveSegment(segmentID) {
                if !onMove(segment, target) { onRefusal("That time is already taken.") }
            } else if let task = resolveTask(payload.taskID) {
                if !onSchedule(task, target) { onRefusal("That time is already taken.") }
            }
        }
        return true
    }
}
