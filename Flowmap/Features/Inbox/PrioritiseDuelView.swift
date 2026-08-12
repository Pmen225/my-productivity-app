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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let initialTodayTasks: [FlowTask]

    private enum FeedbackEvent: Equatable {
        case idle
        case choice(Int)
        case completed
    }

    @State private var currentPairIndex = 0
    @State private var picks: [UUID] = []
    /// The current pair gets a new identity after every pick, so SwiftUI can
    /// give the decision a brief, directional hand-off without adding a
    /// second interaction or delaying the next choice.
    /// Rows already shown in the reveal — grows one at a time on a timer to
    /// produce the staggered reveal, or all at once under Reduce Motion.
    @State private var revealedIDs: Set<UUID> = []
    /// Visible resolution state. A chosen card stays vivid and leaves left;
    /// the unchosen card drops away. The next pair enters from the right.
    @State private var selectedWinnerID: UUID?
    @State private var isExitingPair = false
    @State private var pairEntranceX: CGFloat = 0
    @State private var isResolving = false
    @State private var feedbackEvent = FeedbackEvent.idle

    init(tasks: [FlowTask]) {
        self.initialTodayTasks = tasks
    }

    private var scopedTasks: [FlowTask] {
        // One round stays intentionally small. Four tasks produce six quick
        // comparisons; sending an entire busy day through nC2 duels turned a
        // useful game into dozens of taps.
        Array(initialTodayTasks.prefix(4))
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
                .sensoryFeedback(trigger: feedbackEvent) { _, event in
                    guard flow?.settings.focusHapticsEnabled ?? false else { return nil }
                    switch event {
                    case .choice:
                        return .impact(weight: .light, intensity: 0.8)
                    case .completed:
                        return .success
                    case .idle:
                        return nil
                    }
                }
        }
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
                    .contentTransition(.numericText())
                    .accessibilityLabel("Duel \(currentPairIndex + 1) of \(pairs.count)")
            }

            if let first = tasksByID[pair.first], let second = tasksByID[pair.second] {
                duelArena(first: first, second: second)
                    .id(currentPairIndex)
                    .offset(x: pairEntranceX)
            }

            Spacer()
        }
        .padding(FlowSpacing.screen)
    }

    /// Two task cards share one stage, with a quiet VS marker in the space
    /// between them. The marker makes the comparison relationship visible
    /// without adding explanatory copy to either card.
    private func duelArena(first: FlowTask, second: FlowTask) -> some View {
        VStack(spacing: FlowSpacing.m) {
            choiceButton(for: first, against: second)

            Text("or")
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
                .accessibilityHidden(true)

            choiceButton(for: second, against: first)
        }
    }

    private func choiceButton(for task: FlowTask, against other: FlowTask) -> some View {
        let isWinner = selectedWinnerID == task.id
        let isLoser = selectedWinnerID != nil && !isWinner
        return Button {
            pick(task)
        } label: {
            HStack(spacing: FlowSpacing.m) {
                Circle()
                    .strokeBorder(isLoser ? task.colour.base : task.colour.onSoft, lineWidth: 2)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                    Image(systemName: task.iconName)
                        .symbolEffect(.wiggle.byLayer, options: .nonRepeating, value: isWinner)
                        .symbolEffectsRemoved(reduceMotion)
                    Text(task.title)
                        .font(FlowFont.cardTitle)
                        .foregroundStyle(isLoser ? task.colour.base : task.colour.onSoft)
                        .lineLimit(2)
                }
                Spacer(minLength: FlowSpacing.s)
                DurationChip(minutes: task.estimatedMinutes, tint: task.colour)
            }
            .padding(FlowSpacing.l)
            .frame(maxWidth: .infinity, minHeight: 112)
            .background(
                RoundedRectangle(cornerRadius: FlowRadius.large, style: .continuous)
                    .fill(isLoser ? FlowTheme.surfaceWell(scheme) : task.colour.soft)
            )
            .overlay {
                RoundedRectangle(cornerRadius: FlowRadius.large, style: .continuous)
                    .strokeBorder(isLoser ? task.colour.base : FlowTheme.raisedHighlight(scheme), lineWidth: isLoser ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .flowHitTarget()
        .disabled(isResolving)
        .offset(
            x: isExitingPair && isWinner ? -520 : 0,
            y: isExitingPair && isLoser ? 620 : 0
        )
        .rotationEffect(.degrees(isExitingPair && isLoser ? 8 : 0))
        .opacity(isLoser ? 0.48 : 1)
        .accessibilityLabel("Put \(task.title) ahead of \(other.title)")
    }

    private func pick(_ winner: FlowTask) {
        guard !isResolving else { return }
        isResolving = true
        picks.append(winner.id)
        feedbackEvent = .choice(picks.count)
        selectedWinnerID = winner.id
        resolveCurrentPair()
    }

    private func resolveCurrentPair() {
        guard !reduceMotion else {
            advancePair()
            return
        }
        // Hold the selected state for one beat before the cards leave. This
        // gives the symbol and colour response time to register, then keeps
        // the directional exit short enough that the next decision is ready.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            withAnimation(.easeIn(duration: 0.34)) {
                isExitingPair = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.66) {
            advancePair()
        }
    }

    private func advancePair() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            currentPairIndex += 1
            selectedWinnerID = nil
            isExitingPair = false
            pairEntranceX = reduceMotion || currentPairIndex >= pairs.count ? 0 : 520
            isResolving = false
        }
        guard !reduceMotion, currentPairIndex < pairs.count else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.34)) {
                pairEntranceX = 0
            }
        }
    }

    // MARK: - Reveal stage

    private var revealStage: some View {
        VStack(spacing: FlowSpacing.l) {
            VStack(spacing: FlowSpacing.s) {
                FlowEyebrow("Your order", tint: FlowTheme.accent)
                completionTitle
                    .font(FlowFont.sectionTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
            }
            .padding(.top, FlowSpacing.xxxl)

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

            resultActions
            .padding(.horizontal, FlowSpacing.screen)
            .padding(.bottom, FlowSpacing.l)
        }
        .onAppear(perform: startReveal)
    }

    @ViewBuilder
    private var completionTitle: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            HStack(spacing: FlowSpacing.s) {
                Image(systemName: "checkmark.seal.fill")
                    .symbolEffect(.bounce, options: .nonRepeating, value: feedbackEvent)
                    .symbolEffectsRemoved(reduceMotion)
                Text("Decision made.")
            }
        } else {
            Label("Decision made.", systemImage: "checkmark.seal.fill")
        }
    }

    /// Both exits are one coherent choice set, so they keep the same physical
    /// size. Native style — not a larger footprint — marks the planning action
    /// as primary. Accessibility sizes stack the same controls without changing
    /// their hierarchy or shortening their labels.
    @ViewBuilder
    private var resultActions: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: FlowSpacing.s) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: FlowSpacing.s) {
                        planTodayButton.buttonStyle(.glassProminent)
                        keepOrderButton.buttonStyle(.glass)
                    }
                } else {
                    HStack(spacing: FlowSpacing.s) {
                        planTodayButton.buttonStyle(.glassProminent)
                        keepOrderButton.buttonStyle(.glass)
                    }
                }
            }
            .tint(FlowTheme.accentFill)
        } else {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: FlowSpacing.s) {
                        planTodayButton.buttonStyle(.borderedProminent)
                        keepOrderButton.buttonStyle(.bordered)
                    }
                } else {
                    HStack(spacing: FlowSpacing.s) {
                        planTodayButton.buttonStyle(.borderedProminent)
                        keepOrderButton.buttonStyle(.bordered)
                    }
                }
            }
            .buttonBorderShape(.capsule)
            .tint(FlowTheme.accentFill)
        }
    }

    private var planTodayButton: some View {
        Button {
            applyOrder(andPlan: true)
        } label: {
            resultActionLabel("Plan today", systemImage: "calendar.badge.checkmark")
        }
        .accessibilityHint("Reorders these tasks and plans today, moving anything already scheduled")
    }

    private var keepOrderButton: some View {
        Button {
            applyOrder(andPlan: false)
        } label: {
            resultActionLabel("Keep order", systemImage: "list.number")
        }
        .accessibilityHint("Reorders these tasks without scheduling anything")
    }

    private func resultActionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(FlowFont.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
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
            feedbackEvent = .completed
            return
        }
        for (index, task) in ranked.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.13) {
                withAnimation(FlowMotion.fade) {
                    _ = revealedIDs.insert(task.id)
                }
                if index == ranked.count - 1 {
                    feedbackEvent = .completed
                }
            }
        }
    }

    private func resetDuel() {
        currentPairIndex = 0
        picks = []
        revealedIDs = []
        selectedWinnerID = nil
        isExitingPair = false
        pairEntranceX = 0
        isResolving = false
        feedbackEvent = .idle
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
