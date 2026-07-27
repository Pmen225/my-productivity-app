import SwiftData
import SwiftUI

/// Progress informs, it never shames: four plain numbers, a trend chart and a
/// category breakdown, all recomputed live from persisted tasks, segments and
/// focus sessions. Nothing here is a stored aggregate.
struct ProgressScreen: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme

    @Query(sort: \FlowTask.updatedAt, order: .reverse) private var allTasks: [FlowTask]
    @Query(sort: \TaskSegment.startDate) private var allSegments: [TaskSegment]
    @Query(sort: \FocusSession.startedAt) private var allSessions: [FocusSession]

    @State private var period: ProgressPeriod = .today

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

    private var trendPoints: [ProgressTrendPoint] {
        ProgressMetrics.trendPoints(segments: allSegments, sessions: allSessions, range: range, calendar: calendar)
    }

    private var categorySlices: [ProgressCategorySlice] {
        ProgressMetrics.categoryBreakdown(tasks: allTasks, sessions: allSessions, range: range)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowSpacing.l) {
                header
                periodPicker
                ProgressMetricsGrid(summary: summary)
                ProgressTrendChart(points: trendPoints)
                ProgressCategoryBreakdownView(slices: categorySlices)
            }
            .padding(FlowSpacing.screen)
        }
        .background(FlowTheme.background(scheme).ignoresSafeArea())
    }

    private var header: some View {
        Text("Progress")
            .font(FlowFont.screenTitle)
            .foregroundStyle(FlowTheme.primaryText(scheme))
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
}
