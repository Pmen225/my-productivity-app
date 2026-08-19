import SwiftData
import SwiftUI

/// The always-visible strip above the tab bar: the one active subtask (or
/// its nearest fallback), tapped to open `FocusQueueSheet`.
///
/// Task 58 (founder ruling 2026-08-08, option B) replaces the old
/// three-detent, two-page `FocusTaskCard` with this bar plus a native
/// resizable sheet — the horizontal page swipe was unreliable, the handle
/// band wasted space, and the card duplicated what a bar can say in one row.
struct FocusNowBar: View {
    @Environment(\.colorScheme) private var scheme

    let queue: [TaskSegment]
    let activeTask: FlowTask?
    let activeSegmentID: UUID?
    let onTap: () -> Void

    /// Reserve the two-line active-task/subtask card before the wheel is sized;
    /// the expanded context must not collide with the dial or home indicator.
    static let height: CGFloat = FlowControlSize.hero + FlowSpacing.l * 2

    private var model: FocusQueueModel {
        FocusQueueModel(queue: queue, activeTask: activeTask, activeSegmentID: activeSegmentID)
    }

    private var showsSubtaskContext: Bool {
        guard let activeTask else { return false }
        return model.barTitle != activeTask.title
    }

    var body: some View {
        if model.isBarVisible {
            Button(action: onTap) {
                HStack(spacing: FlowSpacing.m) {
                    Circle()
                        .fill((activeTask?.colour ?? .violet).onSoft)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                        if showsSubtaskContext, let activeTask {
                            Text(activeTask.title)
                                .font(FlowFont.caption)
                                .foregroundStyle(FlowTheme.secondaryText(scheme))
                                .lineLimit(1)
                        }
                        Text(model.barTitle)
                            .font(FlowFont.body.weight(.semibold))
                            .foregroundStyle(FlowTheme.primaryText(scheme))
                            .lineLimit(1)
                    }

                    Spacer(minLength: FlowSpacing.s)

                    VStack(alignment: .trailing, spacing: FlowSpacing.xxs) {
                        Text(model.barCaption)
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                            .lineLimit(1)
                        Image(systemName: "chevron.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FlowTheme.tertiaryText(scheme))
                    }
                }
                .padding(.horizontal, FlowSpacing.l)
                .padding(.vertical, FlowSpacing.m)
                .frame(minHeight: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                    .fill(FlowTheme.surface(scheme))
            )
            .overlay {
                RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                    .stroke(FlowTheme.separator(scheme), lineWidth: 0.5)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("focus-now-bar")
            .accessibilityLabel("\(model.barTitle), \(model.barCaption)")
            .accessibilityHint("Opens today's queue")
        }
    }
}

/// Today's whole queue as one list, the active task's checklist nested under
/// its own row (decision 15 stands: a row's tap unfolds it, starting a task
/// keeps its own control). Shared verbatim between the iPhone sheet
/// (`FocusQueueSheet`) and the Mac's inline pane.
struct FocusQueueListView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.flow) private var flow
    /// Closes the iPhone sheet before "Plan your day" switches the tab
    /// underneath it (HIG: never leave a modal floating over a changed
    /// context). Inline on the Mac pane it is a harmless no-op.
    @Environment(\.dismiss) private var dismiss

    let queue: [TaskSegment]
    let activeTask: FlowTask?
    let activeSegmentID: UUID?

    /// Which queue row has been unfolded. One at a time — the existing rule.
    /// Seeded from the active segment when the view first appears, never
    /// re-seeded afterwards: the founder's own taps are what move this.
    @State private var expandedSegmentID: UUID?

    /// Ticks with the same clock `FocusScreen` uses, so the active row's
    /// remaining time counts down without a timer of its own.
    private var now: Date { flow?.now ?? Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Premium-UX mandate (2026-08-08): a sheet's main header is a real
            // title, not a tracked all-caps eyebrow — the founder rejected the
            // eyebrow here on device. Eyebrows stay for labels INSIDE content.
            Text("Today's queue")
                .font(FlowFont.sectionTitle)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, FlowSpacing.screen)
                // Clear of the sheet grabber, with air on both sides — the
                // founder rejected the cramped 16pt version on device.
                .padding(.top, FlowSpacing.xl)
                .padding(.bottom, FlowSpacing.l)

            if queue.isEmpty {
                // Task 61: the old copy named a "Today screen" that is not a
                // tab and offered no route. Signpost the real one — Plan.
                VStack(spacing: FlowSpacing.l) {
                    FlowEmptyState(
                        symbol: "tray",
                        title: "Nothing on the wheel",
                        message: "Tasks join the wheel when you plan your day."
                    )
                    SecondaryActionButton("Plan your day", systemImage: "square.stack") {
                        dismiss()
                        NotificationCenter.default.post(
                            name: .flowmapOpenDeepLink,
                            object: DeepLinkRequest(destination: .inbox)
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, FlowSpacing.screen)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: FlowSpacing.s) {
                        ForEach(queue) { segment in
                            queueRow(segment)
                            if expandedSegmentID == segment.id {
                                queueRowDetail(segment)
                            }
                        }
                    }
                    .padding(.horizontal, FlowSpacing.screen)
                    .padding(.bottom, FlowSpacing.l)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            expandedSegmentID = FocusQueueModel(
                queue: queue,
                activeTask: activeTask,
                activeSegmentID: activeSegmentID
            ).initiallyExpandedSegmentID
        }
    }

    // The mock's queue also carries "✓ done" / "↷ moved" / "skipped" rows and
    // strikes finished ones through. Not built: `FocusEngine.queue(for:)`
    // returns only `.scheduled` and `.elapsed` segments, so those states can
    // never reach this view. Showing the day's history means widening that
    // query, which `currentSegment` also reads — a change to what Focus
    // considers "next", not a display tweak. See the handover.
    private func queueRow(_ segment: TaskSegment) -> some View {
        let task = segment.task
        let colour = task?.colour ?? .violet
        let isActive = segment.id == activeSegmentID
        let hasNote = !(task?.notes ?? []).isEmpty

        return HStack(spacing: FlowSpacing.m) {
            Circle()
                .fill(colour.onSoft)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            // Decision 15: the row's own tap unfolds the checklist, so
            // starting a task needs a control of its own.
            Button {
                withAnimation(FlowMotion.expand) {
                    expandedSegmentID = expandedSegmentID == segment.id ? nil : segment.id
                }
            } label: {
                HStack(spacing: FlowSpacing.xs) {
                    Text(rowTitle(task: task, segment: segment))
                        .font(FlowFont.body)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                        .lineLimit(1)

                    if hasNote {
                        Image(systemName: "note.text")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                            .accessibilityLabel("Has a note")
                    }

                    Spacer(minLength: FlowSpacing.s)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(rowTitle(task: task, segment: segment)), \(DurationFormatter.spoken(minutes: segment.durationMinutes))"
            )
            .accessibilityHint("Shows this task's subtasks")

            if segment.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .accessibilityLabel("Locked")
            }

            if isActive {
                // The row that is actually running reads its remaining
                // time, not the fixed slot it was scheduled into.
                Text(DurationFormatter.countdown(seconds: segment.remainingSeconds(at: now)))
                    .font(FlowFont.caption.weight(.heavy).monospacedDigit())
                    .foregroundStyle(FlowTheme.accentDeep)
            } else {
                // No per-row start control: the wheel is a commitment device —
                // picking an arbitrary queued task from Focus is exactly what
                // `wheel-philosophy.md` forbids, and the row reads calmer
                // without a CTA competing with the wheel's own (2026-08-08).
                Text("\(DurationFormatter.time(segment.startDate)) · \(DurationFormatter.compact(minutes: segment.durationMinutes))")
                    .font(.system(size: 12, design: .rounded).monospacedDigit())
                    // The row only takes a colour fill while it is the active
                    // one, so the ink has to follow it there and nowhere else.
                    .foregroundStyle(isActive ? colour.onSoft : FlowTheme.secondaryText(scheme))
            }
        }
        .padding(.horizontal, FlowSpacing.m)
        .flowHitTarget(44)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                .fill(isActive ? colour.soft : Color.clear)
        )
    }

    /// What a tapped queue row unfolds. Every row shows what "done" means for
    /// its task; only the ACTIVE task's checklist is interactive — ticking a
    /// subtask only makes sense for the task actually being worked (decision
    /// 15) — everything else stays the old read-only preview.
    @ViewBuilder
    private func queueRowDetail(_ segment: TaskSegment) -> some View {
        let task = segment.task
        let subtasks = task?.orderedSubtasks ?? []
        let isActive = segment.id == activeSegmentID

        if subtasks.isEmpty {
            Text("No subtasks.")
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
                .padding(.horizontal, FlowSpacing.xl)
                .padding(.bottom, FlowSpacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if isActive {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(subtasks.enumerated()), id: \.element.id) { index, subtask in
                    subtaskRow(subtask, isFirst: index == 0, isLast: index == subtasks.count - 1)
                }
            }
            .padding(.horizontal, FlowSpacing.l)
            .padding(.vertical, FlowSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                    .fill(FlowTheme.surfaceSunken(scheme))
            )
            .padding(.horizontal, FlowSpacing.m)
            .padding(.bottom, FlowSpacing.s)
        } else {
            VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                ForEach(subtasks) { subtask in
                    HStack(spacing: FlowSpacing.s) {
                        Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11))
                            .foregroundStyle(
                                subtask.isCompleted ? FlowTheme.accent : FlowTheme.separatorStrong(scheme)
                            )
                        Text(subtask.title)
                            .font(FlowFont.caption)
                            .strikethrough(subtask.isCompleted)
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, FlowSpacing.xl)
            .padding(.bottom, FlowSpacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A continuation says so, the way the mock does — the same task coming
    /// back around is not a second task.
    private func rowTitle(task: FlowTask?, segment: TaskSegment) -> String {
        let base = task?.title ?? "Task"
        return segment.isContinuation ? "\(base) · moved" : base
    }

    /// The width the checklist's circles are centred in, so the connector
    /// behind them lines up whichever symbol a row is showing.
    private static let subtaskDotColumn: CGFloat = 20

    /// Half a row's worth of timeline, drawn behind the circle column.
    private func connector(hidden: Bool) -> some View {
        Rectangle()
            .fill(hidden ? Color.clear : FlowTheme.separatorStrong(scheme))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private func subtaskRow(_ subtask: Subtask, isFirst: Bool, isLast: Bool) -> some View {
        Button {
            flow?.gamification.toggleSubtask(subtask)
        } label: {
            HStack(spacing: FlowSpacing.m) {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    // Hairline weight for the unticked state — the checklist
                    // is supporting detail, not a second row of controls.
                    .foregroundStyle(subtask.isCompleted ? FlowTheme.accent : FlowTheme.separatorStrong(scheme))
                    // A fixed column so the connector behind it lines up with
                    // every circle, whatever the symbol's own width.
                    .frame(width: Self.subtaskDotColumn)
                    .background(Circle().fill(FlowTheme.surface(scheme)).padding(-1))
                Text(subtask.title)
                    .font(FlowFont.body)
                    .strikethrough(subtask.isCompleted, color: FlowTheme.secondaryText(scheme))
                    .foregroundStyle(
                        subtask.isCompleted
                            ? FlowTheme.secondaryText(scheme)
                            : FlowTheme.primaryText(scheme)
                    )
                Spacer(minLength: 0)
            }
            .padding(.vertical, FlowSpacing.s)
            // The mock's timeline: a hairline joining one circle to the next,
            // stopping at the first and last rows so the run has two ends.
            .background(alignment: .leading) {
                VStack(spacing: 0) {
                    connector(hidden: isFirst)
                    connector(hidden: isLast)
                }
                .frame(width: Self.subtaskDotColumn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subtask.title)
        .accessibilityValue(subtask.isCompleted ? "Completed" : "Not completed")
        .accessibilityAddTraits(.isButton)
    }
}

/// The iPhone presentation of `FocusQueueListView`: a native resizable sheet
/// (founder ruling 2026-08-08, option B) replacing the old paged,
/// three-detent card. Self-configures its own presentation modifiers, the
/// pattern already used by `RolloverReviewView`.
struct FocusQueueSheet: View {
    @Environment(\.colorScheme) private var scheme

    let queue: [TaskSegment]
    let activeTask: FlowTask?
    let activeSegmentID: UUID?

    var body: some View {
        FocusQueuePager(
            queue: queue,
            activeTask: activeTask,
            activeSegmentID: activeSegmentID
        )
        .accessibilityIdentifier("focus-queue-sheet")
        .presentationDetents([.fraction(0.28)])
        .presentationDragIndicator(.visible)
        .presentationBackground(FlowTheme.surface(scheme))
    }
}

/// Two calm peer pages inside the existing bottom card. The active task's
/// steps come first; today's queue stays one horizontal swipe away instead of
/// competing in the same vertical list.
private struct FocusQueuePager: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.flow) private var flow

    let queue: [TaskSegment]
    let activeTask: FlowTask?
    let activeSegmentID: UUID?

    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                currentStepsPage.tag(0)
                todayQueuePage.tag(1)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .accessibilityIdentifier("focus-bottom-card-pager")

            Button {
                withAnimation(reduceMotion ? nil : FlowMotion.selection) {
                    page = page == 0 ? 1 : 0
                }
            } label: {
                VStack(spacing: FlowSpacing.xxs) {
                    HStack(spacing: FlowSpacing.xs) {
                        pageDot(isSelected: page == 0)
                        pageDot(isSelected: page == 1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Focus card page")
                    .accessibilityValue("\(page + 1) of 2")
                    .accessibilityIdentifier("focus-card-page-indicator")

                    Text(page == 0 ? "Swipe left for Today's queue" : "Swipe right for Current steps")
                        .font(FlowFont.caption)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(page == 0 ? "Shows today's queue" : "Shows the current task's steps")
        }
        .padding(.top, FlowSpacing.s)
    }

    private var currentStepsPage: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            pageTitle("Current steps", detail: activeTask?.title)

            if let activeTask {
                let steps = Array(activeTask.orderedSubtasks.prefix(3))
                if steps.isEmpty {
                    emptyMessage("No steps added")
                } else {
                    ForEach(steps) { subtask in
                        Button {
                            flow?.gamification.toggleSubtask(subtask)
                        } label: {
                            HStack(spacing: FlowSpacing.m) {
                                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 17))
                                    .foregroundStyle(
                                        subtask.isCompleted ? FlowTheme.accent : FlowTheme.separatorStrong(scheme)
                                    )
                                Text(subtask.title)
                                    .font(FlowFont.body)
                                    .strikethrough(subtask.isCompleted)
                                    .foregroundStyle(FlowTheme.primaryText(scheme))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .flowHitTarget(44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("focus-current-step")
                        .accessibilityValue(subtask.isCompleted ? "Completed" : "Not completed")
                    }
                }
            } else {
                emptyMessage("Choose a task to begin")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, FlowSpacing.screen)
        .accessibilityIdentifier("focus-current-steps-page")
    }

    private var todayQueuePage: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            pageTitle("Today's queue", detail: nil)

            if queue.isEmpty {
                emptyMessage("Nothing else planned today")
            } else {
                ForEach(Array(queue.prefix(3))) { segment in
                    HStack(spacing: FlowSpacing.m) {
                        Circle()
                            .fill((segment.task?.colour ?? .violet).onSoft)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(segment.task?.title ?? "Task")
                            .font(FlowFont.body)
                            .foregroundStyle(FlowTheme.primaryText(scheme))
                            .lineLimit(1)
                        Spacer(minLength: FlowSpacing.s)
                        Text("\(DurationFormatter.time(segment.startDate)) · \(DurationFormatter.compact(minutes: segment.durationMinutes))")
                            .font(FlowFont.caption.monospacedDigit())
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                    }
                    .flowHitTarget(44)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("focus-today-queue-item")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, FlowSpacing.screen)
        .accessibilityIdentifier("focus-today-queue-page")
    }

    private func pageTitle(_ title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FlowSpacing.s) {
            Text(title)
                .font(FlowFont.sectionTitle)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, FlowSpacing.s)
    }

    private func emptyMessage(_ message: String) -> some View {
        Text(message)
            .font(FlowFont.body)
            .foregroundStyle(FlowTheme.secondaryText(scheme))
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
    }

    private func pageDot(isSelected: Bool) -> some View {
        Capsule()
            .fill(isSelected ? FlowTheme.primaryText(scheme) : FlowTheme.separatorStrong(scheme))
            .frame(width: isSelected ? 16 : 6, height: 6)
    }
}
