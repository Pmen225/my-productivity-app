import SwiftUI

/// One row on the Projects screen: icon, title, progress and a due date when set.
public struct ProjectRow: View {
    @Environment(\.colorScheme) private var scheme
    let project: Project

    public init(project: Project) {
        self.project = project
    }

    public var body: some View {
        HStack(spacing: FlowSpacing.m) {
            Image(systemName: project.iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(project.colour.onSoft)
                .frame(width: 36, height: 36)
                .background(Circle().fill(project.colour.soft))

            VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                Text(project.title)
                    .font(FlowFont.cardTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                HStack(spacing: FlowSpacing.s) {
                    StatusIndicator(
                        token: project.colour,
                        symbolName: statusSymbol,
                        label: project.status.displayName
                    )
                    if let due = project.dueDate {
                        Text(due, style: .date)
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                    }
                }
            }

            Spacer(minLength: FlowSpacing.s)

            VStack(alignment: .trailing, spacing: FlowSpacing.xxs) {
                ProgressView(value: project.progress)
                    .frame(width: 60)
                    .tint(project.colour.base)
                Text(project.progressPercentText)
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }
        }
        .padding(.vertical, FlowSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var statusSymbol: String {
        switch project.status {
        case .active: return "play.fill"
        case .paused: return "pause.fill"
        case .completed: return "checkmark"
        case .archived: return "archivebox.fill"
        }
    }
}
