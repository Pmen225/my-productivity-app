import SwiftData
import SwiftUI

/// One project with the week's work hanging off it — the mock's bold
/// branch-name eyebrow and the rows underneath it.
struct WeeklyPlanGroup: Identifiable {
    let id: String
    let title: String
    let items: [WeeklyPlanItem]
}

/// One leaf row: colour dot, title, and a duration chip.
struct WeeklyPlanItem: Identifiable {
    let id: UUID
    let title: String
    let colour: ColourToken
    let isCompleted: Bool
    let minutes: Int
}

/// The grouping the Weekly Plan page draws, kept apart from the view so the
/// week window can be tested without a `View`.
enum CalendarWeeklyPlan {
    /// Every task with time booked inside `week`, once each, under its branch.
    ///
    /// A task can hold several segments in one week; the row stands for the
    /// task, so the first segment it appears in decides its place and the rest
    /// are skipped. Branch order follows the first appearance in the week, so
    /// the list reads in the order the week runs.
    static func groups(segments: [TaskSegment], week: DateInterval) -> [WeeklyPlanGroup] {
        var order: [String] = []
        var titles: [String: String] = [:]
        var items: [String: [WeeklyPlanItem]] = [:]
        var seenTasks: Set<UUID> = []

        let live = segments
            .filter { $0.state.occupiesTimeline }
            .filter { $0.startDate < week.end && $0.endDate > week.start }
            .sorted { $0.startDate < $1.startDate }

        for segment in live {
            guard let task = segment.task, !seenTasks.contains(task.id) else { continue }
            seenTasks.insert(task.id)

            let (key, title) = bucket(for: task)
            if items[key] == nil {
                order.append(key)
                titles[key] = title
            }
            items[key, default: []].append(
                WeeklyPlanItem(
                    id: task.id,
                    title: task.title,
                    colour: task.colour,
                    isCompleted: task.status == .completed,
                    minutes: task.estimatedMinutes
                )
            )
        }

        return order.map {
            WeeklyPlanGroup(id: $0, title: titles[$0] ?? "", items: items[$0] ?? [])
        }
    }

    /// A task with no project falls back to a plain heading rather than
    /// vanishing from the plan.
    private static func bucket(for task: FlowTask) -> (key: String, title: String) {
        if let project = task.project, !project.title.isEmpty {
            return ("project-\(project.id.uuidString)", project.title)
        }
        return ("unfiled", "Unfiled")
    }
}

/// The Calendar panel's second page: the whole week's work grouped under the
/// project each task came from.
struct CalendarWeeklyPlanView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \TaskSegment.startDate) private var allSegments: [TaskSegment]

    let anchorDate: Date

    private var calendar: Calendar {
        CalendarDateMath.calendar(firstWeekday: flow?.settings.firstWeekday ?? 2)
    }

    private var groups: [WeeklyPlanGroup] {
        CalendarWeeklyPlan.groups(
            segments: allSegments,
            week: CalendarDateMath.weekInterval(containing: anchorDate, calendar: calendar)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowSpacing.m) {
                if groups.isEmpty {
                    Text("Nothing planned.")
                        .font(FlowFont.secondary)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                        .padding(.vertical, FlowSpacing.xs)
                } else {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                            FlowEyebrow(group.title)
                            ForEach(group.items) { item in
                                row(item)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FlowSpacing.screen)
            .padding(.bottom, FlowSpacing.m)
        }
        .contentMargins(.bottom, FlowSpacing.floatingControlsInset, for: .scrollContent)
    }

    private func row(_ item: WeeklyPlanItem) -> some View {
        HStack(spacing: FlowSpacing.s) {
            Circle()
                .fill(item.colour.base)
                .frame(width: 8, height: 8)

            Text(item.title)
                .font(FlowFont.body)
                .foregroundStyle(
                    item.isCompleted
                        ? FlowTheme.secondaryText(scheme)
                        : FlowTheme.primaryText(scheme)
                )
                .strikethrough(item.isCompleted)
                .lineLimit(1)

            Spacer(minLength: FlowSpacing.s)

            DurationChip(minutes: item.minutes)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            item.isCompleted
                ? "\(item.title), done, \(DurationFormatter.spoken(minutes: item.minutes))"
                : "\(item.title), \(DurationFormatter.spoken(minutes: item.minutes))"
        )
    }
}
