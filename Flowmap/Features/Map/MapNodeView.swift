import SwiftUI

/// One idea bubble: a rounded pill sized to its own text, filled with its
/// branch's flat MindNode colour (or, for the root, `MapPalette`'s neutral
/// root fill) — never a fixed-width card. Purely presentational — every
/// interaction it exposes is a closure so `MapCanvasView` stays the single
/// place that talks to `MapViewModel`.
struct MapNodeView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.flow) private var flow

    let node: MapNode
    /// The exact size `MapLayout.pillSize(for:)` computed for this node —
    /// the pill is drawn at this size, never recomputed here, so the visible
    /// bubble and the connector anchored to it can never disagree.
    let size: CGSize
    /// This node's position among the root's direct children — `node`'s own
    /// `sortOrder` if it IS a depth-1 branch, otherwise that ancestor's.
    /// Feeds `MapPalette.branchColour` so a whole branch reads as one flat
    /// colour. Meaningless (and unused) for the root.
    let rootChildIndex: Int
    let isSelected: Bool
    let isDimmed: Bool
    let isCompact: Bool
    let isSearchMatch: Bool
    let onSelect: () -> Void
    let onToggleCollapse: () -> Void

    private var metrics: MapLayout.Metrics { .shared }

    /// A task node with no children — the mock's outlined pill with an
    /// inline duration, as opposed to a branch (which groups children) or
    /// the root (which is always the dark anchor).
    private var isLeafTask: Bool { node.isTask && !node.hasChildren && !node.isRoot }

    var body: some View {
        pill
            .mapMinimumHitTarget()
            .opacity(isDimmed ? 0.25 : 1)
            .onTapGesture(count: 1) {
                // The pill is the expand control for a collapsed branch —
                // the "+N" text below is informational, too small to be a
                // 44pt target in the inter-pill gap.
                if node.isCollapsed, node.hasChildren { onToggleCollapse() }
                onSelect()
            }
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
            .overlay(alignment: .top) {
                // MindNode draws nothing beneath a pill except a collapsed
                // branch's count — no per-node progress captions (Task 63
                // pixel gate: literal match; level/XP live on Stats).
                if node.isCollapsed, node.hasChildren {
                    collapsedBadge
                        .offset(y: size.height + FlowSpacing.xs)
                }
            }
    }

    /// One solid-fill pill treatment for every node — root or not, task or
    /// not, leaf or branch. MindNode never gives a leaf its own outlined
    /// variant (Task 63 MindNode restyle, item 3): the whole subtree under a
    /// branch reads as that branch's flat colour.
    private var pillCore: some View {
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
        .padding(.horizontal, metrics.horizontalPadding(forRoot: node.isRoot))
        .padding(.vertical, metrics.verticalPadding(forRoot: node.isRoot))
        .frame(width: size.width, height: size.height)
        .background(pillShape.fill(fillColour))
        .overlay(pillShape.strokeBorder(borderColour, lineWidth: isSelected ? 2.5 : 1.5))
    }

    /// MindNode's continuous rounded-rect pill, scaled to this pill's own
    /// drawn height — never `Capsule()`, and never recomputed anywhere else,
    /// so the fill, the stroke and (were one ever added) a clip all agree on
    /// the exact same outline.
    private var pillShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MapLayout.nodeCornerRadius(forHeight: size.height), style: .continuous)
    }

    /// The "+N" count beside a collapsed pill's caption. Informational only:
    /// a 44pt button cannot fit the below-pill gap, so the pill itself is
    /// the expand control (tap expands via `onSelect` in the canvas).
    private var collapsedBadge: some View {
        Text("+\(node.orderedChildren.count)")
            .font(FlowFont.mapBadge)
            .foregroundStyle(FlowTheme.tertiaryText(scheme))
            .accessibilityHidden(true)
    }

    /// The 7pt clay dot marking a leaf task whose segment is the focus
    /// engine's active one right now.
    private var activeDot: some View {
        Circle()
            .fill(FlowTheme.accent)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }

    private var titleField: some View {
        Text(node.title.isEmpty ? "Untitled" : node.title)
            .font(titleFont)
            .foregroundStyle(textColour)
            .strikethrough(node.isCompleted)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Styling

    /// MindNode's own fixed palette (Task 63 MindNode restyle), not the
    /// app-wide `ColourToken` pastel: root is a flat neutral fill, every
    /// other node is its branch's colour SOLID — no wash, no per-depth
    /// variant.
    private var fillColour: Color {
        node.isRoot ? MapPalette.rootFill(scheme) : MapPalette.branchColour(rootChildIndex: rootChildIndex)
    }

    private var textColour: Color {
        node.isRoot ? MapPalette.rootText(scheme) : MapPalette.titleInk(on: fillColour)
    }

    /// Root is semibold, every other node is bold, at the clone's own
    /// `NodeTextSizeStyle` sizes — flat across branch, leaf task and plain
    /// idea alike, no per-kind variant. Matches `MapLayout.pillSize`'s own
    /// measurement exactly, or the pill and its title drift apart.
    private var titleFont: Font {
        .system(
            size: MapLayout.titleFontSize(isRoot: node.isRoot, isCompact: isCompact),
            weight: node.isRoot ? .semibold : .bold,
            design: .rounded
        )
    }

    private var borderColour: Color {
        if isSelected { return node.isRoot ? textColour : node.colour.base }
        if isSearchMatch { return FlowTheme.accent }
        return .clear
    }

    private var accessibilityValue: String {
        guard node.isCollapsed, node.hasChildren else { return "" }
        return "\(node.orderedChildren.count) hidden"
    }

    // MARK: - Task progress

    /// Whether this leaf's linked task is the one the focus engine is
    /// running right now.
    private var isActiveSegment: Bool {
        guard let displayTask = node.displayTask else { return false }
        return flow?.focusEngine.activeSession?.task?.id == displayTask.id
    }
}
