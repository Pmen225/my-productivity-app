import SwiftUI

/// One idea bubble. Purely presentational — every interaction it exposes is a
/// closure or binding so `MapCanvasView` stays the single place that talks to
/// `MapViewModel`.
struct MapNodeView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let node: MapNode
    let isSelected: Bool
    let isDimmed: Bool
    let isCompact: Bool
    let isSearchMatch: Bool
    @Binding var isRenaming: Bool
    let onSelect: () -> Void
    let onCommitTitle: (String) -> Void
    let onToggleCollapse: () -> Void

    @State private var draftTitle: String = ""
    @FocusState private var isFieldFocused: Bool

    private var metrics: MapLayout.Metrics { .shared }

    var body: some View {
        HStack(spacing: FlowSpacing.xs) {
            if node.hasChildren {
                Button(action: onToggleCollapse) {
                    Image(systemName: node.isCollapsed ? "chevron.right.circle.fill" : "chevron.left.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(node.colour.onSoft)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(node.isCollapsed ? "Expand branch" : "Collapse branch")
            }

            if !isCompact, !node.iconName.isEmpty {
                Image(systemName: node.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(node.colour.onSoft)
            }

            titleField

            if node.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(node.colour.onSoft)
                    .accessibilityLabel("Completed")
            }

            if !isCompact, node.isTask {
                DurationChip(minutes: node.estimatedMinutes, tint: node.colour)
            }
        }
        .padding(.horizontal, FlowSpacing.m)
        .frame(width: metrics.nodeWidth, height: isCompact ? metrics.compactNodeHeight : metrics.nodeHeight)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .fill(node.colour.soft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .strokeBorder(borderColour, lineWidth: isSelected ? 2.5 : 1.5)
        )
        .opacity(isDimmed ? 0.25 : 1)
        .shadow(color: FlowTheme.shadow(scheme), radius: isSelected ? 6 : 3, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous))
        .onTapGesture(count: 2) { beginRenaming() }
        .onTapGesture(count: 1) { onSelect() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(node.title.isEmpty ? "Untitled idea" : node.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var titleField: some View {
        if isRenaming {
            TextField("Idea", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(FlowFont.cardTitle)
                .focused($isFieldFocused)
                .onSubmit(commit)
                .onAppear {
                    draftTitle = node.title
                    isFieldFocused = true
                }
                .onChange(of: isFieldFocused) { _, focused in
                    if !focused { commit() }
                }
        } else {
            Text(node.title.isEmpty ? "Untitled" : node.title)
                .font(isCompact ? FlowFont.secondary : FlowFont.cardTitle)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .strikethrough(node.isCompleted)
                .lineLimit(1)
        }
    }

    private var borderColour: Color {
        if isSelected { return node.colour.base }
        if isSearchMatch { return FlowTheme.accent }
        return .clear
    }

    private func beginRenaming() {
        onSelect()
        isRenaming = true
    }

    private func commit() {
        guard isRenaming else { return }
        onCommitTitle(draftTitle)
        isRenaming = false
    }
}
