import SwiftUI

/// One idea bubble: a rounded pill sized to its own text, filled with the
/// node's pastel tint (or, for the root, the inverse-of-scheme "anchor"
/// fill) — never a fixed-width card. Purely presentational — every
/// interaction it exposes is a closure or binding so `MapCanvasView` stays
/// the single place that talks to `MapViewModel`.
struct MapNodeView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.flow) private var flow

    let node: MapNode
    /// The exact size `MapLayout.pillSize(for:)` computed for this node —
    /// the pill is drawn at this size, never recomputed here, so the visible
    /// bubble and the connector anchored to it can never disagree.
    let size: CGSize
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

    /// A task node with no children — the mock's outlined pill with an
    /// inline duration, as opposed to a branch (which groups children) or
    /// the root (which is always the dark anchor).
    private var isLeafTask: Bool { node.isTask && !node.hasChildren && !node.isRoot }

    var body: some View {
        pill
            .mapMinimumHitTarget()
            .opacity(isDimmed ? 0.25 : 1)
            .onTapGesture(count: 2) { beginRenaming() }
            .onTapGesture(count: 1) { onSelect() }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isSelected)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(node.title.isEmpty ? "Untitled idea" : node.title)
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Pill

    private var pill: some View {
        pillCore
            .overlay(alignment: .topLeading) {
                if isLeafTask, isActiveSegment {
                    activeDot.offset(x: -3, y: -3)
                }
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: FlowSpacing.xs) {
                    if node.isCollapsed, node.hasChildren {
                        collapsedBadge
                    }
                    belowPillContent
                }
                .offset(y: size.height / 2 + FlowSpacing.xs)
            }
    }

    @ViewBuilder
    private var pillCore: some View {
        if isLeafTask {
            leafTaskPillCore
        } else {
            defaultPillCore
        }
    }

    /// Root and branch pills, plus a plain (non-task, childless) idea —
    /// unchanged from the map's original single pill treatment.
    private var defaultPillCore: some View {
        HStack(spacing: FlowSpacing.xs) {
            if !isCompact, node.hasChildren, !node.isCollapsed {
                Image(systemName: "circle.fill")
                    .font(.system(size: 4))
                    .foregroundStyle(textColour.opacity(0.5))
                    .accessibilityHidden(true)
            }

            if !isCompact, !node.iconName.isEmpty {
                Image(systemName: node.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(node.isRoot ? textColour : node.colour.onSoft)
            }

            titleField

            if node.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(node.isRoot ? textColour : node.colour.onSoft)
                    .accessibilityLabel("Completed")
            }

            if !isCompact, node.isTask {
                DurationChip(minutes: node.estimatedMinutes, tint: node.isRoot ? nil : node.colour)
            }
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(width: size.width, height: size.height)
        .background(Capsule(style: .continuous).fill(fillColour))
        .overlay(Capsule(style: .continuous).strokeBorder(borderColour, lineWidth: isSelected ? 2.5 : 1.5))
        .shadow(color: FlowTheme.shadow(scheme), radius: isSelected ? 6 : 3, y: 1)
    }

    /// A leaf task: white capsule, coloured outline, title then the linked
    /// task's duration inline — the mock's outlined pill, distinct from a
    /// branch's filled tint.
    private var leafTaskPillCore: some View {
        HStack(spacing: FlowSpacing.xs) {
            titleField
            if let linkedTask = node.linkedTask {
                Text(DurationFormatter.compact(minutes: linkedTask.estimatedMinutes))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
            }
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(width: size.width, height: size.height)
        .background(Capsule(style: .continuous).fill(FlowTheme.surface(scheme)))
        .overlay(Capsule(style: .continuous).strokeBorder(leafBorderColour, lineWidth: isSelected ? 2.5 : 1.5))
        .shadow(color: FlowTheme.shadow(scheme), radius: 3, y: 1)
    }

    /// The "+N" badge beneath a pill with children hidden behind it — tapping
    /// it re-expands the branch, the same action the outline's chevron and
    /// the canvas context menu's "Expand branch" trigger.
    private var collapsedBadge: some View {
        Button(action: onToggleCollapse) {
            Text("+\(node.orderedChildren.count)")
                .font(FlowFont.mapBadge)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
                .padding(.horizontal, FlowSpacing.xs)
                .mapMinimumHitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Expand branch, \(node.orderedChildren.count) hidden")
    }

    /// The 7pt clay dot marking a leaf task whose segment is the focus
    /// engine's active one right now.
    private var activeDot: some View {
        Circle()
            .fill(FlowTheme.accent)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }

    // MARK: - Below-pill content

    /// Everything drawn beneath the pill itself: the root's level/XP stack,
    /// a branch's completion caption, or a leaf task's subtask count —
    /// mutually exclusive, so at most one renders per node.
    @ViewBuilder
    private var belowPillContent: some View {
        if node.isRoot {
            rootStack
        } else if node.hasChildren {
            branchCaption
        } else if isLeafTask, let linkedTask = node.linkedTask, !linkedTask.orderedSubtasks.isEmpty {
            subtaskCaption(count: linkedTask.orderedSubtasks.count)
        }
    }

    /// `D/T` beneath a branch pill — completion across its whole subtree,
    /// regardless of collapse state, so the count never flickers as branches
    /// fold and unfold.
    @ViewBuilder
    private var branchCaption: some View {
        let counts = taskCounts(in: node)
        if counts.total > 0 {
            captionText("\(counts.completed)/\(counts.total)")
        }
    }

    private func subtaskCaption(count: Int) -> some View {
        Text("+\(count) SUBTASKS")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(FlowTheme.tertiaryText(scheme))
            .kerning(1.2)
    }

    /// The root's level/XP line, progress bar and task count — stacked
    /// beneath the dark anchor pill, map-wide rather than per-branch.
    private var rootStack: some View {
        let counts = taskCounts(in: node)
        let xp = counts.completed * MapNodeView.xpPerTask
        return VStack(spacing: FlowSpacing.xxs) {
            Text("LV \(level(forXP: xp)) · \(xp) XP")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(FlowTheme.accent)
                .kerning(0.8)
            progressBar(completed: counts.completed, total: counts.total)
            if counts.total > 0 {
                captionText("\(counts.completed)/\(counts.total) TASKS")
            }
        }
    }

    private func captionText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(FlowTheme.tertiaryText(scheme))
            .kerning(0.6)
    }

    private static let progressBarWidth: CGFloat = 120

    private func progressBar(completed: Int, total: Int) -> some View {
        let fraction = total > 0 ? CGFloat(completed) / CGFloat(total) : 0
        let fillWidth = Self.progressBarWidth * fraction
        return ZStack(alignment: .leading) {
            Capsule().fill(FlowTheme.separator(scheme))
                .frame(width: Self.progressBarWidth, height: 4)
            Capsule().fill(FlowTheme.accent)
                .frame(width: fillWidth, height: 4)
            if completed > 0 {
                Circle().fill(FlowTheme.accent)
                    .frame(width: 6, height: 6)
                    .offset(x: fillWidth - 3)
            }
        }
        .frame(width: Self.progressBarWidth, height: 6)
    }

    @ViewBuilder
    private var titleField: some View {
        if isRenaming {
            TextField("Idea", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(titleFont)
                .foregroundStyle(textColour)
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
                .font(titleFont)
                .foregroundStyle(textColour)
                .strikethrough(node.isCompleted)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: - Styling

    /// The root reads as the tree's fixed anchor — a dark fill with light
    /// text, the inverse of every pastel branch or leaf beneath it. Every
    /// other pill is its own tint at low opacity.
    private var fillColour: Color {
        node.isRoot ? FlowTheme.mapRootFill(scheme) : node.colour.soft
    }

    private var textColour: Color {
        node.isRoot ? FlowTheme.mapRootText(scheme) : FlowTheme.primaryText(scheme)
    }

    /// Root keeps its own bold title. A leaf task and a branch share the
    /// mock's bold caption size; a plain (non-task, childless) idea keeps
    /// the original fixed-size title.
    private var titleFont: Font {
        if node.isRoot { return FlowFont.mapRootTitle }
        if isLeafTask || node.hasChildren { return FlowFont.caption.weight(.bold) }
        return isCompact ? FlowFont.mapNodeTitleCompact : FlowFont.mapNodeTitle
    }

    private var borderColour: Color {
        if isSelected { return node.isRoot ? textColour : node.colour.base }
        if isSearchMatch { return FlowTheme.accent }
        return .clear
    }

    private var leafBorderColour: Color {
        if isSelected { return node.colour.base }
        if isSearchMatch { return FlowTheme.accent }
        return node.colour.base.opacity(0.7)
    }

    private var accessibilityValue: String {
        guard node.isCollapsed, node.hasChildren else { return "" }
        return "\(node.orderedChildren.count) hidden"
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

    // MARK: - Task progress

    /// XP awarded per completed linked task — a round, documented assumption
    /// rather than a sourced design number, kept in one place so it can be
    /// revisited without touching the layout code around it.
    private static let xpPerTask = 5

    /// `L = XP / 100 + 1` — the level shown on the root pill.
    private func level(forXP xp: Int) -> Int { xp / MapNodeView.xpLevelSpan + 1 }
    private static let xpLevelSpan = 100

    /// Completed vs. total linked tasks across `node`'s whole subtree —
    /// ignoring collapse state, so a folded branch's caption never lies
    /// about what is actually done underneath it.
    private func taskCounts(in node: MapNode) -> (completed: Int, total: Int) {
        let tasks = node.subtreeNodes.compactMap(\.linkedTask)
        return (tasks.count { $0.status == .completed }, tasks.count)
    }

    /// Whether this leaf's linked task is the one the focus engine is
    /// running right now.
    private var isActiveSegment: Bool {
        guard let linkedTask = node.linkedTask else { return false }
        return flow?.focusEngine.activeSession?.task?.id == linkedTask.id
    }
}
