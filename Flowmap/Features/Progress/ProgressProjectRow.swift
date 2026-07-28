import SwiftUI

/// One row on the Stats screen's Projects list: token dot, name, a thin
/// completion capsule and the raw D/T fraction — deliberately simpler than
/// `Features/Projects/ProjectRow`, which carries status and due-date chrome
/// this screen doesn't need.
struct ProgressProjectRow: View {
    @Environment(\.colorScheme) private var scheme
    let project: Project

    private var counts: (completed: Int, total: Int) {
        (project.completedTaskCount, project.actionableTasks.count)
    }

    var body: some View {
        let counts = counts
        let fraction = counts.total > 0 ? Double(counts.completed) / Double(counts.total) : 0

        HStack(spacing: FlowSpacing.m) {
            Circle()
                .fill(project.colour.onSoft)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Text(project.title)
                .font(FlowFont.body)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .lineLimit(1)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(FlowTheme.separator(scheme))
                    Capsule().fill(project.colour.base)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)

            Text("\(counts.completed)/\(counts.total)")
                .font(FlowFont.caption.monospacedDigit())
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .frame(minWidth: 32, alignment: .trailing)
        }
        .padding(FlowSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .fill(FlowTheme.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .strokeBorder(FlowTheme.separator(scheme), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.title), \(counts.completed) of \(counts.total) tasks complete")
    }
}
