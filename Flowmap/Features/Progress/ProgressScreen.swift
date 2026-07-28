import SwiftData
import SwiftUI

/// Progress informs, it never shames: a small centred title, an initiative
/// card, the project list and a 3-up stat-tile row — all recomputed live from
/// persisted tasks, segments, maps and focus sessions. XP and level come from
/// `GamificationService`, the same source `MapNodeView`'s root pill reads, so
/// the two screens cannot disagree about what level the user is.
struct ProgressScreen: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \FlowTask.updatedAt, order: .reverse) private var allTasks: [FlowTask]
    @Query(sort: \TaskSegment.startDate) private var allSegments: [TaskSegment]
    @Query(sort: \FocusSession.startedAt) private var allSessions: [FocusSession]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \MapDocument.updatedAt, order: .reverse) private var maps: [MapDocument]

    @State private var period: ProgressPeriod = .today
    @State private var showsXPExplainer = false
    /// The XP-into-level figure actually on screen. Separate from
    /// `currentLevel.xpIntoLevel` so a level-up can roll the old value into
    /// the new one over the design's timing instead of jumping instantly.
    @State private var displayedXPIntoLevel: Int?

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = flow?.settings.firstWeekday ?? 2
        return calendar
    }

    private var range: Range<Date> {
        period.range(containing: flow?.now ?? Date(), calendar: calendar)
    }

    private var summary: ProgressSummary {
        ProgressMetrics.summary(tasks: allTasks, segments: allSegments, sessions: allSessions, range: range)
    }

    /// The most recently touched map stands in for "the current initiative" —
    /// there is no separate notion of an active map anywhere else in the app.
    private var initiative: MapDocument? { maps.first }

    /// The account's level, derived fresh from persisted total XP every read
    /// — the same `GamificationService` `MapNodeView`'s root pill reads, so
    /// the two screens cannot disagree about what level this is.
    private var currentLevel: GamificationLevel {
        flow?.gamification.level ?? GamificationCurve.level(forTotalXP: 0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowSpacing.l) {
                title
                periodPicker
                if let initiative {
                    initiativeCard(initiative)
                    xpDisclosure
                }
                projectsSection
                statTilesSection
            }
            .padding(FlowSpacing.screen)
        }
        .background(FlowTheme.background(scheme).ignoresSafeArea())
        .onAppear {
            if displayedXPIntoLevel == nil { displayedXPIntoLevel = currentLevel.xpIntoLevel }
        }
        .onChange(of: currentLevel.level) { oldLevel, newLevel in
            // A level-up gets the design's roll. Anything else that changes
            // the figure (an XP gain that stays within the same level) just
            // updates it straight away — only the level-up is a "moment".
            if newLevel > oldLevel {
                rollDisplayedXP(to: currentLevel.xpIntoLevel)
            } else {
                displayedXPIntoLevel = currentLevel.xpIntoLevel
            }
        }
        .onChange(of: currentLevel.xpIntoLevel) { _, newValue in
            guard !isRolling else { return }
            displayedXPIntoLevel = newValue
        }
    }

    @State private var isRolling = false

    /// Rolls the XP-into-level figure from its old value to `newValue` on the
    /// design's own timing: a 480ms pre-roll delay, then an 1100ms roll.
    /// Reduce Motion replaces the roll with an instant, discrete update —
    /// the same convention `FlowChrome`'s `animated(_:)` helper uses for the
    /// create sheet's selections, rather than inventing a second one.
    private func rollDisplayedXP(to newValue: Int) {
        guard !reduceMotion else {
            displayedXPIntoLevel = newValue
            return
        }
        isRolling = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
            withAnimation(.linear(duration: 1.1)) {
                displayedXPIntoLevel = newValue
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                isRolling = false
            }
        }
    }

    private var title: some View {
        Text("Stats")
            .font(FlowFont.screenTitleCompact)
            .foregroundStyle(FlowTheme.primaryText(scheme))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(ProgressPeriod.allCases) { period in
                Text(period.displayName).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Progress period")
    }

    // MARK: - Initiative card

    private func taskCounts(in map: MapDocument) -> (completed: Int, total: Int) {
        let tasks = map.orderedNodes.compactMap(\.linkedTask)
        return (tasks.count { $0.status == .completed }, tasks.count)
    }

    private func initiativeCard(_ map: MapDocument) -> some View {
        let counts = taskCounts(in: map)
        let level = currentLevel
        let xpIntoLevel = displayedXPIntoLevel ?? level.xpIntoLevel
        let fraction = counts.total > 0 ? Double(counts.completed) / Double(counts.total) : 0

        return FlowCard {
            VStack(alignment: .leading, spacing: FlowSpacing.s) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                        FlowEyebrow("Initiative")
                        Text(map.title)
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(FlowTheme.primaryText(scheme))
                            .lineLimit(1)
                    }
                    Spacer(minLength: FlowSpacing.s)
                    VStack(alignment: .trailing, spacing: FlowSpacing.xxs) {
                        Text("LV \(level.level)")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(FlowTheme.accent)
                        Text("\(xpIntoLevel) / \(level.xpForLevel) XP · next LV \(level.level + 1)")
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                            .contentTransition(.numericText())
                    }
                }

                HStack(spacing: FlowSpacing.s) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(FlowTheme.separator(scheme))
                            Capsule().fill(FlowTheme.accent)
                                .frame(width: proxy.size.width * fraction)
                            if counts.completed > 0 {
                                Circle().fill(FlowTheme.accent)
                                    .frame(width: 10, height: 10)
                                    .offset(x: max(0, proxy.size.width * fraction - 5))
                            }
                        }
                    }
                    .frame(height: 6)

                    Text("\(counts.completed)/\(counts.total)")
                        .font(FlowFont.caption.monospacedDigit())
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                }

                Text("Finishing tasks, planning them and clearing your day all earn XP.")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(map.title), level \(level.level)")
        .accessibilityValue("\(xpIntoLevel) of \(level.xpForLevel) XP, \(counts.completed) of \(counts.total) tasks complete")
    }

    private var xpDisclosure: some View {
        FlowCard {
            DisclosureGroup("How XP works", isExpanded: $showsXPExplainer) {
                // The design's own copy (design-inventory.md §"XP / levelling"):
                // finishing beats starting, and each level costs more than the last.
                Text("+1 XP per minute of a finished task, +5 per subtask, +10 for planning, +25 per task when a project closes, +50 for clearing your day. Each level costs 100 × level^1.5 — level 2 takes one good day, level 5 a strong week.")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .padding(.top, FlowSpacing.xs)
            }
            .font(FlowFont.secondary)
            .foregroundStyle(FlowTheme.primaryText(scheme))
            .tint(FlowTheme.accent)
        }
    }

    // MARK: - Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            FlowEyebrow("Projects")
            if projects.isEmpty {
                FlowEmptyState(
                    symbol: "folder",
                    title: "No projects yet",
                    message: "Group related tasks into a project to see progress here."
                )
            } else {
                VStack(spacing: FlowSpacing.s) {
                    ForEach(projects) { project in
                        ProgressProjectRow(project: project)
                    }
                }
            }
        }
    }

    private var statTilesSection: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            FlowEyebrow(period.displayName)
            ProgressStatTilesRow(summary: summary)
        }
    }
}
