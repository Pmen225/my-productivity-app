import SwiftUI

/// The infinite-feeling, zoomable, pannable canvas.
///
/// Nodes and connectors are drawn as siblings inside one container that
/// carries a single `.scaleEffect` / `.offset` pair — never two separate
/// transforms — so panning, zooming or animating can never let a connector
/// drift away from the node it joins.
struct MapCanvasView: View {
    @Bindable var viewModel: MapViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewportSize: CGSize = .zero
    /// Guards the one-time fit so reappearing does not throw away the user's pan.
    @State private var hasFitted = false
    /// Once the user pans or zooms by hand, automatic re-fitting stops.
    @State private var userAdjustedCanvas = false
    @State private var draggingNodeID: UUID?
    @State private var dragTranslation: CGSize = .zero
    @State private var renamingNodeID: UUID?
    @State private var isSearchPresented = false
    @GestureState private var pinchDelta: CGFloat = 1
    @GestureState private var panDelta: CGSize = .zero

    private var metrics: MapLayout.Metrics { .shared }
    private let margin: CGFloat = 160

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                FlowTheme.background(scheme)
                    .contentShape(Rectangle())
                    .gesture(panGesture)

                canvasContent
                    .scaleEffect(viewModel.zoom * pinchDelta, anchor: .topLeading)
                    .offset(
                        x: viewModel.panOffset.width + panDelta.width,
                        y: viewModel.panOffset.height + panDelta.height
                    )
            }
            .simultaneousGesture(pinchGesture)
            .onAppear {
                viewportSize = proxy.size
                // A map that has never been positioned opens fitted, rather than
                // with the tree running off the edge of the canvas.
                //
                // Deferred by one turn of the runloop: at `onAppear` the child
                // relationships have not always been faulted in, so fitting
                // immediately would frame the root node alone.
                guard !hasFitted, viewModel.map.canvasOffsetX == 0, viewModel.map.canvasOffsetY == 0
                else { return }
                hasFitted = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    viewModel.fitToMap(viewportSize: proxy.size)
                    // Second pass after SwiftData has had time to fault in the
                    // whole tree — the first fit often sees root + branches only.
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !userAdjustedCanvas else { return }
                    viewModel.fitToMap(viewportSize: proxy.size)
                }
            }
            .onChange(of: proxy.size) { _, newValue in viewportSize = newValue }
            // SwiftData faults child relationships in lazily, so the node set
            // can keep growing for a few runloop turns after the deferred fit —
            // each growth re-fits until the user takes the canvas over.
            .onChange(of: viewModel.map.nodeCount) { _, _ in
                guard hasFitted, !userAdjustedCanvas else { return }
                viewModel.fitToMap(viewportSize: proxy.size)
            }
            .overlay(alignment: .center) {
                if viewModel.map.nodeCount == 0 { emptyState }
            }
            .overlay(alignment: .bottomTrailing) { canvasControls }
            .overlay(alignment: .top) { if isSearchPresented { searchBar } }
        }
        .clipped()
    }

    // MARK: - Merged positions

    /// Automatic layout, with each node's manual override (and, for the node
    /// being dragged right now, the live drag delta) applied on top. Both the
    /// node bubbles and the connector paths read this one dictionary, which is
    /// what keeps them from ever visually separating.
    private var positionMap: [UUID: CGPoint] {
        let auto = viewModel.layoutPositions
        var merged: [UUID: CGPoint] = [:]
        for node in viewModel.visibleNodes {
            var point = viewModel.position(of: node, in: auto)
            if node.id == draggingNodeID {
                point.x += dragTranslation.width / max(viewModel.zoom, 0.01)
                point.y += dragTranslation.height / max(viewModel.zoom, 0.01)
            }
            merged[node.id] = point
        }
        return merged
    }

    /// Every visible node's real pill size, keyed by id — read alongside
    /// `positionMap` so bounds, connectors and node bubbles never disagree
    /// about how much room a node actually takes up.
    private var sizeMap: [UUID: CGSize] { viewModel.layoutSizes }

    private var contentBounds: CGRect {
        MapLayout.bounds(of: positionMap, sizes: sizeMap, metrics: metrics)
    }

    /// Shifts every point so the whole tree — including anything dragged
    /// beyond its automatic bounds — renders at non-negative coordinates
    /// inside the shared content frame.
    private var originShift: CGPoint {
        let box = contentBounds
        return CGPoint(x: margin - box.minX, y: margin - box.minY)
    }

    private var contentSize: CGSize {
        let box = contentBounds
        return CGSize(width: box.width + margin * 2, height: box.height + margin * 2)
    }

    // MARK: - Content

    @ViewBuilder
    private var canvasContent: some View {
        let positions = positionMap
        let sizes = sizeMap
        let shift = originShift
        let size = contentSize
        let orientation = viewModel.layoutOrientation
        let fallbackSize = CGSize(width: metrics.minPillWidth, height: metrics.nodeHeight)

        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for node in viewModel.visibleNodes {
                    guard let parent = node.parent,
                          let parentPoint = positions[parent.id],
                          let childPoint = positions[node.id] else { continue }
                    drawConnector(
                        from: CGPoint(x: parentPoint.x + shift.x, y: parentPoint.y + shift.y),
                        to: CGPoint(x: childPoint.x + shift.x, y: childPoint.y + shift.y),
                        startSize: sizes[parent.id] ?? fallbackSize,
                        endSize: sizes[node.id] ?? fallbackSize,
                        orientation: orientation,
                        // The CHILD's own tint, not the parent's — each branch
                        // reads as one coloured thread from its pill back to
                        // its parent, matching the reference mock.
                        colour: node.colour.base,
                        dimmed: viewModel.isDimmed(node.id) || viewModel.isDimmed(parent.id),
                        in: context
                    )
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)

            ForEach(viewModel.visibleNodes, id: \.id) { node in
                let raw = positions[node.id] ?? .zero
                let nodeSize = sizes[node.id] ?? fallbackSize
                nodeBubble(for: node, at: CGPoint(x: raw.x + shift.x, y: raw.y + shift.y), size: nodeSize)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Draws the parent-tinted curved stroke joining a node to its parent —
    /// horizontal (right edge to left edge) in "Left to right", vertical
    /// (bottom edge to top edge) in "Top down (org chart)". Anchors from each
    /// node's own real size rather than a fixed width, so the stroke always
    /// starts and ends exactly at the pill's edge.
    private func drawConnector(
        from start: CGPoint,
        to end: CGPoint,
        startSize: CGSize,
        endSize: CGSize,
        orientation: MapLayoutOrientation,
        colour: Color,
        dimmed: Bool,
        in context: GraphicsContext
    ) {
        var path = Path()
        switch orientation {
        case .leftToRight:
            let origin = CGPoint(x: start.x + startSize.width / 2, y: start.y)
            let destination = CGPoint(x: end.x - endSize.width / 2, y: end.y)
            let controlOffset = max(40, (destination.x - origin.x) / 2)
            path.move(to: origin)
            path.addCurve(
                to: destination,
                control1: CGPoint(x: origin.x + controlOffset, y: origin.y),
                control2: CGPoint(x: destination.x - controlOffset, y: destination.y)
            )
        case .topDown:
            let origin = CGPoint(x: start.x, y: start.y + startSize.height / 2)
            let destination = CGPoint(x: end.x, y: end.y - endSize.height / 2)
            let controlOffset = max(30, (destination.y - origin.y) / 2)
            path.move(to: origin)
            path.addCurve(
                to: destination,
                control1: CGPoint(x: origin.x, y: origin.y + controlOffset),
                control2: CGPoint(x: destination.x, y: destination.y - controlOffset)
            )
        }
        context.stroke(path, with: .color(colour.opacity(dimmed ? 0.12 : 0.55)), lineWidth: 2)
    }

    @ViewBuilder
    private func nodeBubble(for node: MapNode, at point: CGPoint, size: CGSize) -> some View {
        MapNodeView(
            node: node,
            size: size,
            isSelected: viewModel.selectedNodeID == node.id,
            isDimmed: viewModel.isDimmed(node.id),
            isCompact: viewModel.isCompact,
            isSearchMatch: viewModel.searchMatchIDs.contains(node.id),
            isRenaming: Binding(
                get: { renamingNodeID == node.id },
                set: { renamingNodeID = $0 ? node.id : nil }
            ),
            onSelect: { viewModel.selectedNodeID = node.id },
            onCommitTitle: { viewModel.rename(node, to: $0) },
            onToggleCollapse: { viewModel.toggleCollapse(node) }
        )
        .position(point)
        .gesture(nodeDragGesture(for: node))
        .contextMenu { contextMenu(for: node) }
    }

    // MARK: - Gestures

    private func nodeDragGesture(for node: MapNode) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                draggingNodeID = node.id
                dragTranslation = value.translation
            }
            .onEnded { value in
                let base = viewModel.position(of: node, in: viewModel.layoutPositions)
                let delta = CGSize(
                    width: value.translation.width / max(viewModel.zoom, 0.01),
                    height: value.translation.height / max(viewModel.zoom, 0.01)
                )
                viewModel.setManualPosition(node, to: CGPoint(x: base.x + delta.width, y: base.y + delta.height))
                draggingNodeID = nil
                dragTranslation = .zero
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($panDelta) { value, state, _ in
                guard draggingNodeID == nil else { return }
                state = value.translation
            }
            .onEnded { value in
                guard draggingNodeID == nil else { return }
                userAdjustedCanvas = true
                viewModel.panOffset.width += value.translation.width
                viewModel.panOffset.height += value.translation.height
                viewModel.persistCanvasState()
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchDelta) { value, state, _ in state = value }
            .onEnded { value in
                userAdjustedCanvas = true
                viewModel.zoom = min(max(viewModel.zoom * value, 0.25), 3)
                viewModel.persistCanvasState()
            }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for node: MapNode) -> some View {
        Button("Add child", systemImage: "plus.circle") { _ = viewModel.addChild(to: node) }
        Button("Add sibling", systemImage: "plus.square.on.square") { _ = viewModel.addSibling(to: node) }
        Button("Rename", systemImage: "pencil") { renamingNodeID = node.id }
        if node.hasChildren {
            Button(
                node.isCollapsed ? "Expand branch" : "Collapse branch",
                systemImage: node.isCollapsed ? "chevron.down.circle" : "chevron.up.circle"
            ) {
                viewModel.toggleCollapse(node)
            }
        }
        Button(viewModel.focusBranchID == node.id ? "Exit Focus Branch" : "Focus Branch", systemImage: "eye") {
            viewModel.toggleFocusBranch(on: node)
        }
        if node.manualPosition != nil {
            Button("Reset position", systemImage: "arrow.uturn.backward") {
                viewModel.setManualPosition(node, to: nil)
            }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { viewModel.requestDelete(node) }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        FlowEmptyState(
            symbol: "point.topleft.down.to.point.bottomright.curvepath",
            title: "No ideas yet",
            message: "Start the map with its first topic.",
            actionTitle: "Add root topic"
        ) {
            _ = viewModel.addRootTopic()
        }
    }

    // MARK: - Floating controls

    private var canvasControls: some View {
        VStack(spacing: FlowSpacing.s) {
            Button(action: { isSearchPresented.toggle() }) {
                Image(systemName: "magnifyingglass")
                    .mapMinimumHitTarget()
            }
            .accessibilityLabel("Search ideas")

            Button(action: { viewModel.isCompact.toggle() }) {
                Image(systemName: viewModel.isCompact ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                    .mapMinimumHitTarget()
            }
            .accessibilityLabel(viewModel.isCompact ? "Turn off compact mode" : "Turn on compact mode")

            Divider().frame(width: 20)

            Button(action: {
                viewModel.zoom = min(viewModel.zoom + 0.15, 3)
                viewModel.persistCanvasState()
            }) {
                Image(systemName: "plus.magnifyingglass")
                    .mapMinimumHitTarget()
            }
            .accessibilityLabel("Zoom in")

            Button(action: {
                viewModel.zoom = max(viewModel.zoom - 0.15, 0.25)
                viewModel.persistCanvasState()
            }) {
                Image(systemName: "minus.magnifyingglass")
                    .mapMinimumHitTarget()
            }
            .accessibilityLabel("Zoom out")

            Button(action: { viewModel.fitToMap(viewportSize: viewportSize) }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .mapMinimumHitTarget()
            }
            .accessibilityLabel("Fit map")

            Button(action: { viewModel.centreOnSelection(viewportSize: viewportSize) }) {
                Image(systemName: "scope")
                    .mapMinimumHitTarget()
            }
            .disabled(viewModel.selectedNode == nil)
            .accessibilityLabel("Centre selection")
        }
        .buttonStyle(.plain)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(FlowTheme.primaryText(scheme))
        .padding(FlowSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .fill(FlowTheme.surface(scheme))
        )
        .shadow(color: FlowTheme.shadow(scheme), radius: 8, y: 2)
        .padding(FlowSpacing.l)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: FlowSpacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(FlowTheme.secondaryText(scheme))
            TextField("Search ideas", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .onSubmit { viewModel.jumpToNextSearchMatch() }
            if !viewModel.searchQuery.isEmpty {
                Text("\(viewModel.searchMatchIDs.count)")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                Button(action: { viewModel.searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, FlowSpacing.m)
        .padding(.vertical, FlowSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                .fill(FlowTheme.surface(scheme))
        )
        .shadow(color: FlowTheme.shadow(scheme), radius: 6, y: 2)
        .padding(.top, FlowSpacing.m)
        .frame(maxWidth: 320)
    }
}
