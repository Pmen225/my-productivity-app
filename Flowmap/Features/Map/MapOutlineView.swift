import SwiftUI

/// The same node graph as `MapCanvasView`, as an editable hierarchical list.
///
/// A custom recursive row (not `List`/`OutlineGroup`) so drag-to-reorder can
/// reach any depth via `.draggable`/`.dropDestination`. Map and Outline read
/// and write through the same `MapViewModel` — nothing here keeps its own
/// copy of the graph, so an edit made here shows on the canvas immediately.
struct MapOutlineView: View {
    @Bindable var viewModel: MapViewModel
    @Environment(\.colorScheme) private var scheme
    @State private var renamingNodeID: UUID?
    @State private var dropTargetID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let root = viewModel.map.rootNode {
                    OutlineRow(
                        node: root,
                        depth: 0,
                        viewModel: viewModel,
                        renamingNodeID: $renamingNodeID,
                        dropTargetID: $dropTargetID
                    )
                } else {
                    emptyState
                }
            }
            .padding(FlowSpacing.m)
        }
    }

    private var emptyState: some View {
        FlowEmptyState(
            symbol: "list.bullet.indent",
            title: "No ideas yet",
            message: "Start the map with its first topic.",
            actionTitle: "Add root topic"
        ) {
            _ = viewModel.addRootTopic()
        }
    }
}

/// One row plus its children, recursing until a node has none. Kept as a free
/// function-shaped view (not a method on `MapOutlineView`) so `ForEach` can
/// give every depth of the recursion its own identity.
private struct OutlineRow: View {
    let node: MapNode
    let depth: Int
    @Bindable var viewModel: MapViewModel
    @Binding var renamingNodeID: UUID?
    @Binding var dropTargetID: UUID?

    @Environment(\.colorScheme) private var scheme
    @State private var draftTitle: String = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowContent
                .padding(.leading, CGFloat(depth) * FlowSpacing.xl)
                .background(
                    RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                        .fill(dropTargetID == node.id ? FlowTheme.accent.opacity(0.12) : Color.clear)
                )
                .draggable(node.id.uuidString) {
                    Text(node.title.isEmpty ? "Untitled" : node.title)
                        .font(FlowFont.secondary)
                        .padding(FlowSpacing.s)
                        .background(FlowTheme.surface(scheme))
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first, let draggedID = UUID(uuidString: raw),
                          let dragged = viewModel.map.allNodes.first(where: { $0.id == draggedID }) else {
                        return false
                    }
                    viewModel.moveNode(dragged, beforeSibling: node)
                    return true
                } isTargeted: { isTargeted in
                    dropTargetID = isTargeted ? node.id : (dropTargetID == node.id ? nil : dropTargetID)
                }

            if !node.isCollapsed {
                ForEach(node.orderedChildren, id: \.id) { child in
                    OutlineRow(
                        node: child,
                        depth: depth + 1,
                        viewModel: viewModel,
                        renamingNodeID: $renamingNodeID,
                        dropTargetID: $dropTargetID
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(spacing: FlowSpacing.s) {
            if node.hasChildren {
                Button(action: { viewModel.toggleCollapse(node) }) {
                    Image(systemName: node.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(node.isCollapsed ? "Expand branch" : "Collapse branch")
            } else {
                Color.clear.frame(width: 16)
            }

            Circle().fill(node.colour.base).frame(width: 8, height: 8)

            titleField

            Spacer(minLength: FlowSpacing.s)

            if node.isTask {
                DurationChip(minutes: node.estimatedMinutes, tint: node.colour)
            }
        }
        .padding(.vertical, FlowSpacing.s)
        .padding(.horizontal, FlowSpacing.s)
        .contentShape(Rectangle())
        .background(
            viewModel.selectedNodeID == node.id
                ? RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous).fill(node.colour.soft)
                : nil
        )
        .onTapGesture { viewModel.selectedNodeID = node.id }
        .contextMenu {
            Button("Add child", systemImage: "plus.circle") { _ = viewModel.addChild(to: node) }
            Button("Add sibling", systemImage: "plus.square.on.square") { _ = viewModel.addSibling(to: node) }
            Button("Rename", systemImage: "pencil") { beginRenaming() }
            Button(viewModel.focusBranchID == node.id ? "Exit Focus Branch" : "Focus Branch", systemImage: "eye") {
                viewModel.toggleFocusBranch(on: node)
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { viewModel.requestDelete(node) }
        }
    }

    @ViewBuilder
    private var titleField: some View {
        if renamingNodeID == node.id {
            TextField("Idea", text: $draftTitle)
                .textFieldStyle(.plain)
                .font(FlowFont.secondary)
                .focused($isFieldFocused)
                .onSubmit(commitRename)
                .onAppear {
                    draftTitle = node.title
                    isFieldFocused = true
                }
                .onChange(of: isFieldFocused) { _, focused in
                    if !focused { commitRename() }
                }
        } else {
            Text(node.title.isEmpty ? "Untitled" : node.title)
                .font(FlowFont.secondary)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .strikethrough(node.isCompleted)
                .lineLimit(1)
                .onTapGesture(count: 2) { beginRenaming() }
        }
    }

    private func beginRenaming() {
        viewModel.selectedNodeID = node.id
        renamingNodeID = node.id
    }

    private func commitRename() {
        guard renamingNodeID == node.id else { return }
        viewModel.rename(node, to: draftTitle)
        renamingNodeID = nil
    }
}
