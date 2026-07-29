import SwiftData
import SwiftUI

/// The two pages of the lower focus card.
enum FocusCardPage: Int, CaseIterable, Identifiable {
    case today
    case subtasks

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .subtasks: "Subtasks"
        }
    }

    /// The eyebrow shown above the page on iPhone — the mock's "Today's
    /// queue" / "Subtasks" wording, distinct from the terser Mac tab title.
    var eyebrowTitle: String {
        switch self {
        case .today: "Today's queue"
        case .subtasks: "Subtasks"
        }
    }
}

/// The card beneath the wheel: today's queue on one page, the active task's
/// subtasks on the other.
///
/// On iPhone it is draggable and expands to at least three fifths of the screen.
/// At rest it keeps a measurable gap from the wheel — the two never touch.
struct FocusTaskCard: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.flow) private var flow

    let queue: [TaskSegment]
    let activeTask: FlowTask?
    let activeSegmentID: UUID?
    let onSelect: (TaskSegment) -> Void

    @Binding var page: FocusCardPage
    /// 0 = resting, 1 = fully expanded.
    @Binding var expansion: Double

    @State private var dragOffset: CGFloat = 0
    /// Which queue row has been unfolded to show its checklist. One at a
    /// time — the card is short, and two open rows leave nothing readable.
    @State private var expandedSegmentID: UUID?

    /// Ticks with the same clock `FocusScreen` uses, so the active row's
    /// remaining time counts down without a timer of its own.
    private var now: Date { flow?.now ?? Date() }

    /// Rest height leaves the wheel its own space; expanded covers three fifths.
    static func restingHeight(for total: CGFloat) -> CGFloat { max(180, total * 0.28) }
    /// Comfortably past the three fifths of the screen the spec asks for, once
    /// the status bar and tab bar are taken out of `total`.
    static func expandedHeight(for total: CGFloat) -> CGFloat { max(340, total * 0.72) }

    var body: some View {
        GeometryReader { proxy in
            let resting = Self.restingHeight(for: proxy.size.height)
            let expanded = Self.expandedHeight(for: proxy.size.height)
            let height = resting + (expanded - resting) * expansion

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                card(height: max(resting, height + dragOffset), canExpand: expanded > resting)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    // MARK: - Card

    private func card(height: CGFloat, canExpand: Bool) -> some View {
        VStack(spacing: FlowSpacing.m) {
            #if !os(macOS)
            grabber
            #endif
            header
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, FlowSpacing.screen)
        .padding(.top, FlowSpacing.m)
        .padding(.bottom, FlowSpacing.l)
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background(
            // The mock's hand-held shape: tighter top corners, a deep flare at
            // the bottom rather than a plain rectangle.
            UnevenRoundedRectangle(
                topLeadingRadius: FlowRadius.large,
                bottomLeadingRadius: FlowRadius.deep,
                bottomTrailingRadius: FlowRadius.deep,
                topTrailingRadius: FlowRadius.large,
                style: .continuous
            )
            .fill(FlowTheme.surface(scheme))
            .shadow(color: FlowTheme.shadow(scheme), radius: 18, y: -4)
        )
        #if !os(macOS)
        .gesture(dragGesture(canExpand: canExpand))
        #endif
    }

    private var grabber: some View {
        Capsule()
            .fill(FlowTheme.separatorStrong(scheme))
            .frame(width: 42, height: 5)
            .accessibilityLabel("Drag to expand the task card")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expansion = expansion > 0.5 ? 0 : 1
                }
            }
    }

    private var header: some View {
        HStack(spacing: FlowSpacing.m) {
            #if os(macOS)
            // A segmented switch reads better than a swipe on a pointer-driven Mac.
            Picker("Page", selection: $page) {
                ForEach(FocusCardPage.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 240)
            #else
            FlowEyebrow(page.eyebrowTitle)
            Spacer()
            pageDots
            #endif
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(FocusCardPage.allCases) { candidate in
                Button {
                    withAnimation(.snappy(duration: 0.24)) { page = candidate }
                } label: {
                    Circle()
                        .fill(
                            candidate == page
                                ? FlowTheme.accent
                                : FlowTheme.separator(scheme)
                        )
                        .frame(width: 6, height: 6)
                        // HIG override: full 44pt of height, but 24pt of width
                        // — a 44pt-wide target throws the pair of dots to
                        // opposite ends of the header and they stop reading as
                        // a pager. Swipe remains the primary way to change page.
                        .frame(width: 24, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.eyebrowTitle)
                .accessibilityAddTraits(candidate == page ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        pageContent(page)
        #else
        TabView(selection: $page) {
            ForEach(FocusCardPage.allCases) { candidate in
                pageContent(candidate).tag(candidate)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
    }

    @ViewBuilder
    private func pageContent(_ candidate: FocusCardPage) -> some View {
        switch candidate {
        case .today: todayQueue
        case .subtasks: subtaskList
        }
    }

    // MARK: - Pages

    private var todayQueue: some View {
        Group {
            if queue.isEmpty {
                FlowEmptyState(
                    symbol: "checkmark.circle",
                    title: "Nothing scheduled",
                    message: "Plan your day on the Today screen and it will appear here."
                )
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
                    .padding(.bottom, FlowSpacing.m)
                }
            }
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
                withAnimation(.snappy(duration: 0.24)) {
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
                Text("\(DurationFormatter.time(segment.startDate)) · \(DurationFormatter.compact(minutes: segment.durationMinutes))")
                    .font(.system(size: 12, design: .rounded).monospacedDigit())
                    .foregroundStyle(FlowTheme.secondaryText(scheme))

                Button {
                    onSelect(segment)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(FlowTheme.accent)
                        .flowHitTarget(44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start \(task?.title ?? "task")")
            }
        }
        .padding(.horizontal, FlowSpacing.m)
        .flowHitTarget(44)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                .fill(isActive ? colour.soft : Color.clear)
        )
    }

    /// What a tapped queue row unfolds: what "done" means for this task, and
    /// its checklist — read-only here. Ticking happens on the Subtasks page,
    /// which owns that interaction already.
    private func queueRowDetail(_ segment: TaskSegment) -> some View {
        let task = segment.task
        let subtasks = task?.orderedSubtasks ?? []
        return VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            if let dod = task?.definitionOfDone, !dod.isEmpty {
                Text(dod)
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if subtasks.isEmpty {
                Text("No subtasks.")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
            } else {
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
        }
        .padding(.horizontal, FlowSpacing.xl)
        .padding(.bottom, FlowSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A continuation says so, the way the mock does — the same task coming
    /// back around is not a second task.
    private func rowTitle(task: FlowTask?, segment: TaskSegment) -> String {
        let base = task?.title ?? "Task"
        return segment.isContinuation ? "\(base) · moved" : base
    }

    private var subtaskList: some View {
        Group {
            if let task = activeTask, !task.orderedSubtasks.isEmpty {
                VStack(alignment: .leading, spacing: FlowSpacing.s) {
                    if let progress = task.subtaskProgressLabel {
                        Text(progress)
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                    }
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(task.orderedSubtasks) { subtask in
                                subtaskRow(subtask)
                            }
                        }
                    }
                }
            } else {
                FlowEmptyState(
                    symbol: "checklist",
                    title: activeTask == nil ? "No task running" : "No subtasks",
                    message: activeTask == nil
                        ? "Start a task to see its checklist here."
                        : "Break this task down from its detail view when it helps."
                )
            }
        }
    }

    private func subtaskRow(_ subtask: Subtask) -> some View {
        Button {
            flow?.gamification.toggleSubtask(subtask)
        } label: {
            HStack(spacing: FlowSpacing.m) {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(subtask.isCompleted ? FlowTheme.accent : FlowTheme.secondaryText(scheme))
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subtask.title)
        .accessibilityValue(subtask.isCompleted ? "Completed" : "Not completed")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Drag

    #if !os(macOS)
    private func dragGesture(canExpand: Bool) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard canExpand else { return }
                dragOffset = -value.translation.height
            }
            .onEnded { value in
                guard canExpand else { return }
                let shouldExpand = -value.translation.height > 60
                    || (-value.predictedEndTranslation.height > 140)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    expansion = shouldExpand ? 1 : (value.translation.height > 60 ? 0 : expansion)
                    dragOffset = 0
                }
            }
    }
    #endif
}
