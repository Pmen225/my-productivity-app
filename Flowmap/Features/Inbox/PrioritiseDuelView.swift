import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The prioritise duel: pairwise "which comes first?" picks over today's
/// tasks, then a medal-ranked reveal with two exits. See `state/specs/
/// design-inventory.md` §"Prioritise duel mini-game" for the design source.
/// Deliberately optional — feedback tasks 18/19 (state/specs/
/// cognitive-profile.md, "product thesis"): planning must not require the
/// game, so it is offered as a way to order today, never a gate in front
/// of it.
///
/// Hosted as a sheet off `TaskListScreen`'s Today listing and
/// `PlanInboxSection`'s own actions, rather than a dedicated "Plan" screen —
/// this app has no Plan destination, and building one is not this task. See
/// those files' header comments for the reasoning, so a future Plan screen
/// can be built around this view without moving it.
///
/// All pairing, tallying and ranking comes from `PrioritiseDuel` — this view
/// only presents it and writes the result back to the store.
struct PrioritiseDuelView: View {
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme

    /// The mockup counts the duels in words beside the bar, so the progress
    /// is readable without interpreting a bar's fill.
    static func duelCounter(index: Int, total: Int) -> String {
        "\(min(index + 1, total)) of \(total)"
    }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: [SortDescriptor(\FlowTask.sortOrder), SortDescriptor(\FlowTask.createdAt)])
    private var allTasks: [FlowTask]

    private let initialTodayTasks: [FlowTask]

    @State private var currentPairIndex = 0
    @State private var picks: [UUID] = []
    @State private var scope: DuelScope = .today
    @State private var selectedDate = Date()
    @State private var draftDate = Date()
    @State private var showingDatePicker = false
    /// The current pair gets a new identity after every pick, so SwiftUI can
    /// give the decision a brief, directional hand-off without adding a
    /// second interaction or delaying the next choice.
    /// Rows already shown in the reveal — grows one at a time on a timer to
    /// produce the staggered reveal, or all at once under Reduce Motion.
    @State private var revealedIDs: Set<UUID> = []

    init(tasks: [FlowTask]) {
        self.initialTodayTasks = tasks
    }

    private enum DuelScope: String, CaseIterable, Identifiable {
        case today
        case allTasks
        case chosenDay

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: "Today"
            case .allTasks: "All tasks"
            case .chosenDay: "Chosen day"
            }
        }
    }

    private var scopedTasks: [FlowTask] {
        switch scope {
        case .today:
            return initialTodayTasks
        case .allTasks:
            return allTasks.filter { $0.status != .cancelled }
        case .chosenDay:
            return Self.tasks(for: allTasks, on: selectedDate)
        }
    }

    /// A chosen day matches open work due or scheduled on that day. The
    /// today-only flag is intentionally not carried to another date.
    static func tasks(for tasks: [FlowTask], on day: Date, calendar: Calendar = .current) -> [FlowTask] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let isToday = calendar.isDateInToday(day)
        return tasks.filter { task in
            guard task.status.isOpen else { return false }
            if isToday, task.isFlaggedForToday { return true }
            if let due = task.dueDate, due < end { return true }
            return task.liveSegments.contains { $0.startDate < end && $0.endDate > start }
        }
    }

    private var identities: [UUID] { scopedTasks.map(\.id) }
    private var pairs: [DuelPair] { PrioritiseDuel.pairs(for: identities) }

    private var tasksByID: [UUID: FlowTask] {
        Dictionary(uniqueKeysWithValues: scopedTasks.map { ($0.id, $0) })
    }

    /// The ranked result, re-derived from `identities` and `picks` on every
    /// read — never stored separately from those two, so it cannot drift
    /// from what `PrioritiseDuel.rank` would compute fresh.
    private var ranked: [FlowTask] {
        PrioritiseDuel.rank(identities: identities, picks: picks).compactMap { tasksByID[$0] }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Prioritise duel")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
                .background(FlowTheme.background(scheme).ignoresSafeArea())
        }
        .presentationCornerRadius(FlowRadius.large)
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker("Choose duel day", selection: $draftDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(FlowSpacing.screen)
                    .navigationTitle("Duel day")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingDatePicker = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                selectedDate = draftDate
                                scope = .chosenDay
                                resetDuel()
                                showingDatePicker = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .onChange(of: scope) { _, _ in resetDuel() }
    }

    @ViewBuilder
    private var content: some View {
        if pairs.isEmpty {
            // The entry point in `TaskListScreen` already hides itself below
            // two tasks, so this guard should be unreachable in practice.
            FlowEmptyState(
                symbol: "trophy",
                title: "Nothing to duel",
                message: "Add another inbox task first."
            )
        } else if currentPairIndex < pairs.count {
            duelStage
        } else {
            revealStage
        }
    }

    // MARK: - Duel stage

    private var duelStage: some View {
        let pair = pairs[currentPairIndex]
        return VStack(spacing: FlowSpacing.xl) {
            VStack(spacing: FlowSpacing.s) {
                FlowEyebrow("Prioritise", tint: FlowTheme.accent)
                Text("Which comes first?")
                    .font(FlowFont.sectionTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                ProgressView(
                    value: Double(min(currentPairIndex + 1, pairs.count)),
                    total: Double(pairs.count)
                )
                    .tint(FlowTheme.accentFill)
                    .accessibilityHidden(true)
                Text(Self.duelCounter(index: currentPairIndex, total: pairs.count))
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
                    .accessibilityLabel("Duel \(currentPairIndex + 1) of \(pairs.count)")
                scopeMenu
            }

            if let first = tasksByID[pair.first], let second = tasksByID[pair.second] {
                duelArena(first: first, second: second)
                    .id(currentPairIndex)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .scale(scale: 0.96).combined(with: .opacity)
                        )
                    )
            }

            Spacer()
        }
        .padding(FlowSpacing.screen)
    }

    /// Two task cards share one stage, with a quiet VS marker in the space
    /// between them. The marker makes the comparison relationship visible
    /// without adding explanatory copy to either card.
    private func duelArena(first: FlowTask, second: FlowTask) -> some View {
        ZStack {
            VStack(spacing: FlowSpacing.xl) {
                choiceButton(for: first, against: second)
                choiceButton(for: second, against: first)
            }

            Text("VS")
                .font(FlowFont.durationChip)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .padding(FlowSpacing.s)
                .background(FlowTheme.background(scheme), in: Circle())
                .overlay {
                    Circle().strokeBorder(FlowTheme.separatorStrong(scheme), lineWidth: 1)
                }
                .accessibilityHidden(true)
        }
    }

    private func choiceButton(for task: FlowTask, against other: FlowTask) -> some View {
        Button {
            pick(task)
        } label: {
            FlowCard(padding: FlowSpacing.l) {
                HStack(spacing: FlowSpacing.m) {
                    Image(systemName: task.iconName)
                        .font(FlowFont.sectionTitle)
                        .foregroundStyle(task.colour.onSoft)
                        .frame(width: FlowControlSize.secondary, height: FlowControlSize.secondary)
                        .background(Circle().fill(task.colour.soft))
                    Text(task.title)
                        .font(FlowFont.cardTitle)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                        .lineLimit(2)
                    Spacer(minLength: FlowSpacing.s)
                    DurationChip(minutes: task.estimatedMinutes, tint: task.colour)
                }
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(task.colour.base)
                        .frame(width: FlowSpacing.xs)
                        .padding(.vertical, FlowSpacing.s)
                }
            }
        }
        .buttonStyle(.plain)
        .flowHitTarget()
        .accessibilityLabel("Put \(task.title) ahead of \(other.title)")
    }

    private func pick(_ winner: FlowTask) {
        pickHaptic()
        picks.append(winner.id)
        if reduceMotion {
            currentPairIndex += 1
        } else {
            withAnimation(.snappy(duration: 0.28, extraBounce: 0.04)) {
                currentPairIndex += 1
            }
        }
    }

    /// A pick is a discrete positive decision, so it gets one short optional
    /// impact. The visual hand-off remains the primary feedback and still
    /// works when haptics are disabled or unavailable.
    private func pickHaptic() {
        #if os(iOS)
        guard flow?.settings.focusHapticsEnabled ?? false else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    // MARK: - Reveal stage

    private var revealStage: some View {
        VStack(spacing: FlowSpacing.l) {
            VStack(spacing: FlowSpacing.s) {
                FlowEyebrow("Your order", tint: FlowTheme.accent)
                Text("Decision made.")
                    .font(FlowFont.sectionTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                scopeMenu
            }
            .padding(.top, FlowSpacing.m)

            ScrollView {
                VStack(spacing: FlowSpacing.s) {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { index, task in
                        rankedRow(task, rank: index)
                            .opacity(revealedIDs.contains(task.id) ? 1 : 0)
                            .offset(y: revealedIDs.contains(task.id) ? 0 : 8)
                    }
                }
                .padding(.horizontal, FlowSpacing.screen)
            }

            VStack(spacing: FlowSpacing.s) {
                if scope == .today {
                    PrimaryActionButton("Plan today in this order", systemImage: "checkmark.circle") {
                        applyOrder(andPlan: true)
                    }
                    .accessibilityLabel("Plan today in this order")
                    .accessibilityHint("Reorders today's tasks to this ranking and re-plans today, moving anything already scheduled")
                }
                SecondaryActionButton("Keep order, plan later") {
                    applyOrder(andPlan: false)
                }
                .accessibilityHint("Reorders today's tasks to this ranking without scheduling anything")
            }
            .padding(.horizontal, FlowSpacing.screen)
            .padding(.bottom, FlowSpacing.l)
        }
        .onAppear(perform: startReveal)
    }

    private func rankedRow(_ task: FlowTask, rank: Int) -> some View {
        let medal = medalColour(for: rank)
        return HStack(spacing: FlowSpacing.m) {
            Text("\(rank + 1)")
                .font(FlowFont.cardTitle)
                .foregroundStyle(medal ?? FlowTheme.secondaryText(scheme))
                .frame(width: 28)
            Text(task.title)
                .font(FlowFont.body)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .lineLimit(2)
            Spacer(minLength: FlowSpacing.s)
            DurationChip(minutes: task.estimatedMinutes, tint: task.colour)
        }
        .padding(FlowSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .fill(FlowTheme.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .strokeBorder(medal ?? FlowTheme.separator(scheme), lineWidth: medal != nil ? 2 : 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank + 1): \(task.title)")
    }

    private func medalColour(for rank: Int) -> Color? {
        switch rank {
        case 0: FlowTheme.medalGold
        case 1: FlowTheme.medalSilver
        case 2: FlowTheme.medalBronze
        default: nil
        }
    }

    /// Reveals ranked rows one at a time, 0.13s apart, per the design's own
    /// timing. Reduce Motion collapses this into one discrete update — the
    /// same convention `ProgressScreen.rollDisplayedXP` uses for its XP roll,
    /// rather than inventing a second one.
    private func startReveal() {
        guard revealedIDs.isEmpty else { return }
        guard !reduceMotion else {
            revealedIDs = Set(ranked.map(\.id))
            return
        }
        for (index, task) in ranked.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.13) {
                withAnimation(.easeOut(duration: 0.25)) {
                    _ = revealedIDs.insert(task.id)
                }
            }
        }
    }

    private var scopeMenu: some View {
        Menu {
            Button {
                scope = .today
            } label: {
                Label("Today", systemImage: scope == .today ? "checkmark" : "circle")
            }
            Button {
                scope = .allTasks
            } label: {
                Label("All tasks", systemImage: scope == .allTasks ? "checkmark" : "circle")
            }
            Button {
                draftDate = selectedDate
                showingDatePicker = true
            } label: {
                Label(
                    scope == .chosenDay
                        ? selectedDate.formatted(date: .abbreviated, time: .omitted)
                        : "Choose a day…",
                    systemImage: scope == .chosenDay ? "checkmark" : "calendar"
                )
            }
        } label: {
            Label("Scope: \(scope.title)", systemImage: "slider.horizontal.3")
                .font(FlowFont.caption)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Duel scope: \(scope.title)")
    }

    private func resetDuel() {
        currentPairIndex = 0
        picks = []
        revealedIDs = []
    }

    // MARK: - Exits

    /// Writes the ranked order back to `sortOrder`, exactly the field
    /// `TaskListScreen.move(_:from:to:)` already uses for manual reordering —
    /// no second notion of task order. "Plan today in this order" then hands
    /// off to `AppEnvironment.planToday`/`applyPlan` with `replanExisting:
    /// true`, so the new order takes effect even on tasks today's auto-plan
    /// already scheduled — the same propose/apply pair the Today screen's own
    /// auto-plan button uses, so this never runs a second planner.
    private func applyOrder(andPlan shouldPlan: Bool) {
        for (index, task) in ranked.enumerated() {
            task.sortOrder = index
        }
        try? context.save()
        if shouldPlan, let flow {
            flow.applyPlan(flow.planToday(replanExisting: true))
        }
        dismiss()
    }
}
