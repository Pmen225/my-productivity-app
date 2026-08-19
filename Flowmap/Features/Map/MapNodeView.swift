import SwiftUI

/// One idea bubble: a rounded pill sized to its own text and tinted with the
/// same colour token as the task or project it represents. Purely
/// presentational — every
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
    let orientation: MapLayoutOrientation
    let isSelected: Bool
    let isDimmed: Bool
    let isCompact: Bool
    let isSearchMatch: Bool
    let onSelect: () -> Void
    let onToggleCollapse: () -> Void
    let onAddChild: (() -> Void)?

    private var metrics: MapLayout.Metrics { .shared }

    /// A task node with no children — the mock's outlined pill with an
    /// inline duration, as opposed to a branch (which groups children) or
    /// the root (which is always the dark anchor).
    private var isLeafTask: Bool { node.isTask && !node.hasChildren && !node.isRoot }

    var body: some View {
        pill
            .opacity(isDimmed ? 0.25 : 1)
            .animation(reduceMotion ? nil : FlowMotion.tap, value: isSelected)
            .accessibilityElement(children: .contain)
    }

    // MARK: - Pill

    private var pill: some View {
        pillCore
            .overlay(alignment: .topLeading) {
                if isLeafTask, isActiveSegment {
                    activeDot.offset(x: -3, y: -3)
                }
            }
            .overlay(alignment: branchAnchorAlignment) {
                if node.hasChildren {
                    branchControl
                        .offset(branchControlOffset)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    selectedNodeControl
                        .offset(x: FlowSpacing.m, y: -FlowSpacing.m)
                }
            }
    }

    private var pillCore: some View {
        Button(action: onSelect) {
            HStack(spacing: FlowSpacing.s) {
                if !isCompact, !node.iconName.isEmpty {
                    Circle()
                        .fill(node.isRoot ? Color.white.opacity(0.9) : node.colour.base)
                        .frame(width: FlowSpacing.s, height: FlowSpacing.s)
                        .accessibilityHidden(true)
                }

                titleField

                if node.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(textColour)
                        .accessibilityHidden(true)
                }

                if !isCompact, node.isTask {
                    Text(DurationFormatter.compact(minutes: node.estimatedMinutes))
                        .font(FlowFont.durationChip)
                        .foregroundStyle(textColour.opacity(0.72))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, metrics.horizontalPadding(forRoot: node.isRoot))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .buttonStyle(NodePressStyle())
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .background(pillShape.fill(fillColour))
        .overlay(pillShape.strokeBorder(borderColour, lineWidth: isSelected ? 1.5 : 1))
        .shadow(color: nodeShadowColour, radius: isSelected ? 9 : 3, y: isSelected ? 3 : 1)
        .accessibilityIdentifier("map-node-\(node.id.uuidString)")
        .accessibilityLabel(node.title.isEmpty ? "Untitled idea" : node.title)
        .accessibilityHint("Selects this node")
        .accessibilityValue(nodeAccessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The hierarchy control lives outside the label, matching MindNode's
    /// branch endpoint. Its visual circle is restrained while its hit target
    /// remains the full shared 58pt canvas control.
    private var branchControl: some View {
        Button(action: onToggleCollapse) {
            HStack(spacing: FlowSpacing.xxs) {
                Image(systemName: node.isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                if node.isCollapsed {
                    Text("\(node.orderedChildren.count)")
                        .font(FlowFont.mapBadge)
                }
            }
            .foregroundStyle(FlowTheme.primaryText(scheme))
            .frame(minWidth: 24, minHeight: 24)
            .padding(.horizontal, node.isCollapsed ? FlowSpacing.xs : 0)
            .background(FlowTheme.background(scheme), in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(FlowTheme.separatorStrong(scheme), lineWidth: 1))
            .frame(width: metrics.accessoryAllowance, height: metrics.accessoryAllowance)
            .contentShape(Circle())
        }
        .buttonStyle(NodePressStyle())
        .accessibilityIdentifier("map-node-toggle-\(node.id.uuidString)")
        .accessibilityLabel("\(node.isCollapsed ? "Expand" : "Collapse") \(node.title.isEmpty ? "untitled" : node.title) branch")
        .accessibilityValue(node.isCollapsed ? "\(node.orderedChildren.count) hidden" : "Expanded")
    }

    /// MindNode's continuous rounded-rect pill, scaled to this pill's own
    /// drawn height — never `Capsule()`, and never recomputed anywhere else,
    /// so the fill, the stroke and (were one ever added) a clip all agree on
    /// the exact same outline.
    private var pillShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MapLayout.nodeCornerRadius(forHeight: size.height), style: .continuous)
    }

    /// The 7pt clay dot marking a leaf task whose segment is the focus
    /// engine's active one right now.
    private var activeDot: some View {
        Circle()
            .fill(FlowTheme.info)
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

    /// Colour is a dot, never a flood. The root and the active selection are
    /// black anchors; every other node is a quiet white row floating in the
    /// same neutral workspace as the Plan and Today surfaces.
    private var fillColour: Color {
        node.isRoot || isSelected ? FlowTheme.accentFill : FlowTheme.surface(scheme)
    }

    private var textColour: Color {
        node.isRoot || isSelected ? .white : FlowTheme.primaryText(scheme)
    }

    /// The shared fixed map tokens keep a dense spatial hierarchy while the
    /// node itself provides the 44pt interaction target.
    private var titleFont: Font {
        if node.isRoot { return FlowFont.mapRootTitle }
        return isCompact ? FlowFont.mapNodeTitleCompact : FlowFont.mapNodeTitle
    }

    private var borderColour: Color {
        if node.isRoot || isSelected { return FlowTheme.accentFill }
        if isSearchMatch { return FlowTheme.info }
        return FlowTheme.separatorStrong(scheme)
    }

    private var nodeShadowColour: Color {
        node.isRoot || isSelected ? Color.black.opacity(0.12) : .clear
    }

    private var branchAnchorAlignment: Alignment {
        orientation == .topDown ? .bottom : .trailing
    }

    private var branchControlOffset: CGSize {
        orientation == .topDown
            ? CGSize(width: 0, height: metrics.accessoryAllowance / 2)
            : CGSize(width: metrics.accessoryAllowance / 2, height: 0)
    }

    @ViewBuilder
    private var selectedNodeControl: some View {
        if let onAddChild, let task = node.displayTask {
            Button(action: onAddChild) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                    .frame(width: 26, height: 26)
                    .background(FlowTheme.background(scheme), in: Circle())
                    .overlay(Circle().stroke(FlowTheme.separatorStrong(scheme), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.10), radius: 4, y: 1)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(NodePressStyle())
            .accessibilityIdentifier("map-add-child-\(task.id.uuidString)")
            .accessibilityLabel("Add child task to \(task.title)")
        } else {
            Circle()
                .fill(node.isRoot ? FlowTheme.info : node.colour.base)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                .accessibilityHidden(true)
        }
    }

    private var nodeAccessibilityValue: String {
        var values: [String] = []
        if node.isTask { values.append(DurationFormatter.spoken(minutes: node.estimatedMinutes)) }
        if node.isCompleted { values.append("Completed") }
        if node.isCollapsed, node.hasChildren { values.append("\(node.orderedChildren.count) hidden") }
        return values.joined(separator: ", ")
    }

    // MARK: - Task progress

    /// Whether this leaf's linked task is the one the focus engine is
    /// running right now.
    private var isActiveSegment: Bool {
        guard let displayTask = node.displayTask else { return false }
        return flow?.focusEngine.activeSession?.task?.id == displayTask.id
    }

    private struct NodePressStyle: ButtonStyle {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.74 : 1)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
                .animation(reduceMotion ? nil : FlowMotion.tap, value: configuration.isPressed)
        }
    }
}
