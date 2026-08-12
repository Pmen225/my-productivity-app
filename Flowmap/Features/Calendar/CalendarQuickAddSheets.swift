import SwiftData
import SwiftUI

/// The Calendar `+` menu: deliberately exactly these three actions — never a
/// generic "New item" — so the calendar always shows the user which of the
/// three shapes they're creating.
struct CalendarQuickAddMenu: View {
    @Binding var activeSheet: CalendarQuickAddSheet?

    var body: some View {
        Menu {
            Button {
                activeSheet = .task
            } label: {
                Label("Add Task", systemImage: "circle")
            }
            Button {
                activeSheet = .event
            } label: {
                Label("Add Event", systemImage: "calendar.badge.plus")
            }
            Button {
                activeSheet = .focusBlock
            } label: {
                Label("Add Focus Block", systemImage: "timer")
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add to calendar")
    }
}

enum CalendarQuickAddSheet: Identifiable {
    case task
    case event
    case focusBlock

    var id: String {
        switch self {
        case .task: "task"
        case .event: "event"
        case .focusBlock: "focusBlock"
        }
    }
}

/// Presents the sheet matching `CalendarQuickAddMenu`'s selection, anchored to
/// a specific day so a tap in Day/Week/Agenda pre-fills a sensible time.
struct CalendarQuickAddSheetHost: View {
    let sheet: CalendarQuickAddSheet
    let anchorDate: Date
    let onDismiss: () -> Void

    var body: some View {
        switch sheet {
        case .task:
            // The single task-creation card (`FlowCreateSheet`, via
            // `QuickCaptureView`) — no second, unstyled `Form` implementation.
            // Seeded with the tapped day so that context is not lost.
            QuickCaptureView(initialDueDate: anchorDate)
        case .event:
            AddEventSheet(anchorDate: anchorDate, onDismiss: onDismiss)
        case .focusBlock:
            AddFocusBlockSheet(anchorDate: anchorDate, onDismiss: onDismiss)
        }
    }
}

/// A fixed, locked block on the calendar — the calendar equivalent of an
/// appointment. Modelled as a `FlowTask` with a locked `TaskSegment` rather
/// than a second "event" type, so it shows up everywhere a task does.
private struct AddEventSheet: View {
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    let anchorDate: Date
    let onDismiss: () -> Void

    @State private var title = ""
    @State private var start: Date
    @State private var end: Date
    /// Shown when the chosen slot is already taken.
    @State private var refusal: String?

    init(anchorDate: Date, onDismiss: @escaping () -> Void) {
        self.anchorDate = anchorDate
        self.onDismiss = onDismiss
        let snapped = CalendarDateMath.snapUpToFiveMinutes(anchorDate)
        _start = State(initialValue: snapped)
        _end = State(initialValue: snapped.addingTimeInterval(60 * 60))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Title", text: $title)
                    DatePicker("Starts", selection: $start)
                    DatePicker("Ends", selection: $end, in: start...)
                }
                if let refusal {
                    Section {
                        Label(refusal, systemImage: "exclamationmark.triangle")
                            .font(FlowFont.secondary)
                            .foregroundStyle(FlowTheme.accent)
                    }
                }
            }
            .navigationTitle("Add Event")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let minutes = max(SchedulingEngine.snapMinutes, Int(end.timeIntervalSince(start) / 60))
        // The slot has to be free. Inserting a segment directly would be a second
        // placement path with no overlap check, which is how double-booking gets in.
        guard let flow, flow.scheduling().canPlace(minutes: minutes, at: start) else {
            refusal = "That time is already taken. Pick a free slot."
            return
        }
        let task = FlowTask(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            estimatedMinutes: minutes,
            iconName: "calendar",
            workspace: nil
        )
        task.isLockedInSchedule = true
        _ = TaskCreationService.insert(task, in: context)
        guard let segment = flow.scheduling().schedule(task: task, at: start, minutes: minutes) else {
            context.delete(task)
            try? context.save()
            refusal = "That time is already taken. Pick a free slot."
            return
        }
        // An event is a fixed commitment, so its block is locked.
        segment.isLocked = true
        try? context.save()
        flow.notificationService.rescheduleAll(
            segments: flow.upcomingSegments(from: flow.now),
            settings: flow.settings
        )
        onDismiss()
    }
}

/// A dedicated block of focus time. A lightweight `FlowTask` plus an
/// unlocked, movable `TaskSegment` so it naturally surfaces in
/// `FocusEngine.queue(for:)`, which only offers open-status tasks.
private struct AddFocusBlockSheet: View {
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    let anchorDate: Date
    let onDismiss: () -> Void

    @State private var title = "Focus block"
    @State private var start: Date
    @State private var minutes = 25
    /// Shown when the chosen slot is already taken.
    @State private var refusal: String?

    init(anchorDate: Date, onDismiss: @escaping () -> Void) {
        self.anchorDate = anchorDate
        self.onDismiss = onDismiss
        _start = State(initialValue: CalendarDateMath.snapUpToFiveMinutes(anchorDate))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Focus block") {
                    TextField("Title", text: $title)
                    DatePicker("Starts", selection: $start)
                    Stepper("Length: \(DurationFormatter.compact(minutes: minutes))", value: $minutes, in: 5...240, step: 5)
                }
                if let refusal {
                    Section {
                        Label(refusal, systemImage: "exclamationmark.triangle")
                            .font(FlowFont.secondary)
                            .foregroundStyle(FlowTheme.accent)
                    }
                }
            }
            .navigationTitle("Add Focus Block")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let flow, flow.scheduling().canPlace(minutes: minutes, at: start) else {
            refusal = "That time is already taken. Pick a free slot."
            return
        }
        let task = FlowTask(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            estimatedMinutes: minutes,
            iconName: "timer",
            workspace: nil
        )
        _ = TaskCreationService.insert(task, in: context)
        guard flow.scheduling().schedule(task: task, at: start, minutes: minutes) != nil else {
            context.delete(task)
            try? context.save()
            refusal = "That time is already taken. Pick a free slot."
            return
        }
        try? context.save()
        flow.notificationService.rescheduleAll(
            segments: flow.upcomingSegments(from: flow.now),
            settings: flow.settings
        )
        onDismiss()
    }
}
