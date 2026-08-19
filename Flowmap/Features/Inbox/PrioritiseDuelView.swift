import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The prioritise duel: pairwise "which comes first?" picks over today's
/// tasks, then a medal-ranked reveal with two exits. See `state/specs/
/// design-inventory.md` §"Prioritise duel mini-game" for the design source.
/// Deliberately optional — feedback tasks 18/19 (state/specs/
/// product-planning guidance: planning must not require the
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
        return VStack(alignment: .leading, spacing: FlowSpacing.xl) {
            VStack(alignment: .leading, spacing: FlowSpacing.s) {
                Text("Pick the next thing")
                    .font(FlowFont.screenTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                Text("Choose by instinct. Flowmap will do the ordering.")
                    .font(FlowFont.secondary)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
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

    /// Two flat, equal rows share one stage. There is no decorative "or"
    /// badge or pastel card flood: the relationship is already explicit in
    /// the prompt, and the selected row turns black for one clear beat.
    private func duelArena(first: FlowTask, second: FlowTask) -> some View {
        VStack(spacing: FlowSpacing.m) {
            choiceButton(for: first, against: second)
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
                    .fill(task.colour.base)
                    .frame(width: FlowSpacing.s, height: FlowSpacing.s)

                VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                    Text(task.title)
                        .font(FlowFont.cardTitle)
                        .foregroundStyle(isWinner ? Color.white : FlowTheme.primaryText(scheme))
                        .lineLimit(2)
                    Text(DurationFormatter.spoken(minutes: task.estimatedMinutes))
                        .font(FlowFont.caption)
                        .foregroundStyle(isWinner ? Color.white.opacity(0.64) : FlowTheme.secondaryText(scheme))
                }
                .opacity(isLoser ? 0.48 : 1)
                Spacer(minLength: FlowSpacing.s)
                Image(systemName: isWinner ? "checkmark" : "arrow.right")
                    .font(FlowFont.caption.weight(.semibold))
                    .foregroundStyle(isWinner ? Color.white : FlowTheme.tertiaryText(scheme))
            }
            .padding(FlowSpacing.l)
            .frame(maxWidth: .infinity, minHeight: FlowControlSize.hero)
            .background(
                RoundedRectangle(cornerRadius: FlowRadius.large, style: .continuous)
                    .fill(isWinner ? FlowTheme.accentFill : FlowTheme.surface(scheme))
            )
            .overlay {
                RoundedRectangle(cornerRadius: FlowRadius.large, style: .continuous)
                    .strokeBorder(isWinner ? FlowTheme.accentFill : FlowTheme.separatorStrong(scheme), lineWidth: 1)
            }
        }
        .buttonStyle(DuelOpenAIPressStyle())
        .flowHitTarget()
        .allowsHitTesting(!isResolving)
        .offset(
            x: isExitingPair ? (isWinner ? -FlowSpacing.xxxl : FlowSpacing.xxxl) : 0,
            y: 0
        )
        .opacity(isExitingPair ? 0 : 1)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(FlowMotion.insert) {
                isExitingPair = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
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
            pairEntranceX = reduceMotion || currentPairIndex >= pairs.count ? 0 : FlowSpacing.xxxl
            isResolving = false
        }
        guard !reduceMotion, currentPairIndex < pairs.count else { return }
        DispatchQueue.main.async {
            withAnimation(FlowMotion.insert) {
                pairEntranceX = 0
            }
        }
    }

    // MARK: - Reveal stage

    private var revealStage: some View {
        VStack(spacing: FlowSpacing.l) {
            VStack(alignment: .leading, spacing: FlowSpacing.s) {
                Text("Your order")
                    .font(FlowFont.screenTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                completionTitle
                    .font(FlowFont.secondary)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FlowSpacing.screen)
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
        HStack(spacing: FlowSpacing.s) {
            Image(systemName: "checkmark.circle.fill")
                .symbolEffect(.bounce, options: .nonRepeating, value: feedbackEvent)
                .symbolEffectsRemoved(reduceMotion)
            Text("Decision made. Review it, then plan or keep it.")
        }
    }

    /// Both exits are one coherent choice set, so they keep the same physical
    /// size. Native style — not a larger footprint — marks the planning action
    /// as primary. Accessibility sizes stack the same controls without changing
    /// their hierarchy or shortening their labels.
    @ViewBuilder
    private var resultActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: FlowSpacing.s) {
                planTodayButton
                keepOrderButton
            }
        } else {
            HStack(spacing: FlowSpacing.s) {
                planTodayButton
                keepOrderButton
            }
        }
    }

    private var planTodayButton: some View {
        Button {
            applyOrder(andPlan: true)
        } label: {
            resultActionLabel("Plan today", systemImage: "calendar.badge.checkmark")
                .foregroundStyle(.white)
                .frame(minHeight: FlowControlSize.secondary)
                .background(Capsule().fill(FlowTheme.accentFill))
        }
        .buttonStyle(DuelOpenAIPressStyle())
        .accessibilityHint("Reorders these tasks and plans today, moving anything already scheduled")
    }

    private var keepOrderButton: some View {
        Button {
            applyOrder(andPlan: false)
        } label: {
            resultActionLabel("Keep order", systemImage: "list.number")
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .frame(minHeight: FlowControlSize.secondary)
                .background(Capsule().fill(FlowTheme.surface(scheme)))
                .overlay(Capsule().stroke(FlowTheme.separatorStrong(scheme), lineWidth: 1))
        }
        .buttonStyle(DuelOpenAIPressStyle())
        .accessibilityHint("Reorders these tasks without scheduling anything")
    }

    private func resultActionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(FlowFont.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
    }

    private func rankedRow(_ task: FlowTask, rank: Int) -> some View {
        return HStack(spacing: FlowSpacing.m) {
            Text("\(rank + 1)")
                .font(FlowFont.cardTitle)
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .frame(width: 28)
            Circle()
                .fill(task.colour.base)
                .frame(width: FlowSpacing.s, height: FlowSpacing.s)
            Text(task.title)
                .font(FlowFont.body)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .lineLimit(2)
            Spacer(minLength: FlowSpacing.s)
            Text(DurationFormatter.compact(minutes: task.estimatedMinutes))
                .font(FlowFont.durationChip)
                .foregroundStyle(FlowTheme.secondaryText(scheme))
            Image(systemName: "line.3.horizontal")
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
        }
        .padding(FlowSpacing.m)
        .overlay(alignment: .bottom) {
            Divider().overlay(FlowTheme.separator(scheme))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank + 1): \(task.title)")
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

private struct DuelOpenAIPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.74 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : FlowMotion.tap, value: configuration.isPressed)
    }
}
