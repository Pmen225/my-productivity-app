import SwiftData
import SwiftUI

/// Progress informs, it never shames: a small centred title, an initiative
/// card, the project list and a 3-up stat-tile row — all recomputed live from
/// persisted tasks, segments, maps and focus sessions. Nothing here is a
/// stored aggregate — XP and level are read straight off completed task
/// counts, the same rule the map root pill uses (see `xpPerTask` below).
struct ProgressScreen: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme

    @Query(sort: \FlowTask.updatedAt, order: .reverse) private var allTasks: [FlowTask]
    @Query(sort: \TaskSegment.startDate) private var allSegments: [TaskSegment]
    @Query(sort: \FocusSession.startedAt) private var allSessions: [FocusSession]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \MapDocument.updatedAt, order: .reverse) private var maps: [MapDocument]

    @State private var period: ProgressPeriod = .today
    @State private var showsXPExplainer = false

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

    /// XP awarded per completed linked task, and the XP span per level — the
    /// same two-line rule `MapNodeView`'s root pill uses. That helper is
    /// private to the map canvas, so the rule is replicated here rather than
    /// factored into a new gamification service.
    private static let xpPerTask = 5
    private static let xpLevelSpan = 100
    private func level(forXP xp: Int) -> Int { xp / Self.xpLevelSpan + 1 }

    private func taskCounts(in map: MapDocument) -> (completed: Int, total: Int) {
        let tasks = map.orderedNodes.compactMap(\.linkedTask)
        return (tasks.count { $0.status == .completed }, tasks.count)
    }

    private func initiativeCard(_ map: MapDocument) -> some View {
        let counts = taskCounts(in: map)
        let xp = counts.completed * Self.xpPerTask
        let currentLevel = level(forXP: xp)
        let xpIntoLevel = xp % Self.xpLevelSpan
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
                        Text("LV \(currentLevel)")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(FlowTheme.accent)
                        Text("\(xpIntoLevel) / \(Self.xpLevelSpan) XP · next LV \(currentLevel + 1)")
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
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

                Text("Every completed task in this map earns \(Self.xpPerTask) XP.")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(map.title), level \(currentLevel)")
        .accessibilityValue("\(xpIntoLevel) of \(Self.xpLevelSpan) XP, \(counts.completed) of \(counts.total) tasks complete")
    }

    private var xpDisclosure: some View {
        FlowCard {
            DisclosureGroup("How XP works", isExpanded: $showsXPExplainer) {
                Text("Every completed task linked to this map earns \(Self.xpPerTask) XP. Every \(Self.xpLevelSpan) XP reaches the next level.")
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
