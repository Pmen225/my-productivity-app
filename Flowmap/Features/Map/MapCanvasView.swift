import SwiftUI

/// The infinite-feeling, zoomable, pannable canvas.
///
/// Nodes and connectors are drawn as siblings inside one container that
/// carries a single `.scaleEffect` / `.offset` pair — never two separate
/// transforms — so panning, zooming or animating can never let a connector
/// drift away from the node it joins.
struct MapCanvasView: View {
    @Bindable var viewModel: MapViewModel
    let taskScope: TodayScope?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.flow) private var flow

    /// Guards the one-time fit so reappearing does not throw away the user's pan.
    @State private var hasFitted = false
    /// Once the user pans or zooms by hand, automatic re-fitting stops.
    @State private var userAdjustedCanvas = false
    @GestureState private var pinchDelta: CGFloat = 1
    @GestureState private var panDelta: CGSize = .zero

    private var metrics: MapLayout.Metrics { .shared }
    private let margin: CGFloat = 160

    init(viewModel: MapViewModel, taskScope: TodayScope? = nil) {
        self.viewModel = viewModel
        self.taskScope = taskScope
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                MapPalette.canvas(scheme)
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
            // Ahead of the pan gesture in the chain, so a quick double tap is
            // read as a reset rather than two aborted drags.
            .simultaneousGesture(TapGesture(count: 2).onEnded { resetViewport() })
            .onAppear {
                viewModel.viewportSize = proxy.size
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
            .onChange(of: proxy.size) { _, newValue in viewModel.viewportSize = newValue }
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
            .overlay(alignment: .top) { if viewModel.isSearchPresented { searchBar } }
        }
        .clipped()
    }

    // MARK: - Merged positions

    /// Automatic layout, with each node's manual override applied on top.
    /// Both the node bubbles and the connector paths read this one
    /// dictionary, which is what keeps them from ever visually separating.
    private var positionMap: [UUID: CGPoint] {
        let auto = viewModel.layoutPositions
        var merged: [UUID: CGPoint] = [:]
        for node in viewModel.visibleNodes {
            merged[node.id] = viewModel.position(of: node, in: auto)
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
                        parentDepth: parent.depth,
                        childDepth: node.depth,
                        orientation: orientation,
                        // The CHILD's own branch colour, not the parent's —
                        // each branch reads as one coloured thread from its
                        // pill back to its parent, matching MindNode.
                        colour: MapPalette.branchColour(rootChildIndex: node.rootChildIndex),
                        dimmed: isDimmed(node) || isDimmed(parent),
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

    /// Draws the child-tinted single-elbow stroke joining a node to its
    /// parent. In "Top down (org chart)" this rides MindNode's connector
    /// rails (`MapConnectorGeometry`): the parent exits through its own
    /// rail's bottom edge, and the child is entered either through its own
    /// rail's top edge (a depth-1 child, collinear with its own outgoing
    /// spine) or through whichever side faces the parent's rail (a stacked
    /// depth >= 2 child). "Left to right" keeps the plain pill-edge anchors
    /// — MindNode's rails are a vertical-tree concept the clone never
    /// applies to its horizontal orientation either.
    private func drawConnector(
        from start: CGPoint,
        to end: CGPoint,
        startSize: CGSize,
        endSize: CGSize,
        parentDepth: Int,
        childDepth: Int,
        orientation: MapLayoutOrientation,
        colour: Color,
        dimmed: Bool,
        in context: GraphicsContext
    ) {
        let path: Path
        switch orientation {
        case .leftToRight:
            let origin = CGPoint(x: start.x + startSize.width / 2, y: start.y)
            let destination = CGPoint(x: end.x - endSize.width / 2, y: end.y)
            path = Self.elbowPath(from: origin, to: destination, horizontal: true, endsHorizontally: false)
        case .topDown:
            let parentRailX = MapConnectorGeometry.railX(center: start, size: startSize, depth: parentDepth)
            let origin = MapConnectorGeometry.start(parentCenter: start, parentSize: startSize, parentDepth: parentDepth)
            let destination = MapConnectorGeometry.end(
                childCenter: end,
                childSize: endSize,
                childDepth: childDepth,
                parentRailX: parentRailX
            )
            let endsHorizontally = MapConnectorGeometry.endsHorizontally(childDepth: childDepth)
            path = Self.elbowPath(from: origin, to: destination, horizontal: false, endsHorizontally: endsHorizontally)
        }
        context.stroke(
            path,
            with: .color(colour.opacity(dimmed ? 0.12 : 1)),
            style: StrokeStyle(lineWidth: 6, lineCap: .round)
        )
    }

    /// MindNode's routed connector: a straight run out of the parent, one
    /// smooth rounded elbow, a straight run into the child — never a bezier
    /// curve. The elbow sits a short fixed distance from the parent (never a
    /// canvas-spanning midpoint, which would stretch flat for far-apart
    /// nodes) and its corner radius shrinks to fit tight gaps rather than
    /// overshooting them. `endsHorizontally` selects MindNode's second
    /// vertical-orientation shape: a stacked depth >= 2 child is entered from
    /// its SIDE, so the connector is a single L — one straight drop along the
    /// parent's own rail, one rounded corner, one straight run into the
    /// child's edge — rather than the three-segment bus every depth-1 child
    /// uses. Ported verbatim from `roundedElbowPath`
    /// (MindNodeClone/Sources/MindNodeClone/CanvasView.swift :1752-1827).
    private static func elbowPath(from origin: CGPoint, to destination: CGPoint, horizontal: Bool, endsHorizontally: Bool) -> Path {
        let dx = destination.x - origin.x
        let dy = destination.y - origin.y
        let sx: CGFloat = dx >= 0 ? 1 : -1
        let sy: CGFloat = dy >= 0 ? 1 : -1

        guard abs(dx) > 1, abs(dy) > 1 else {
            var straight = Path()
            straight.move(to: origin)
            straight.addLine(to: destination)
            return straight
        }

        var path = Path()
        if horizontal {
            let busOffset = min(44, max(18, abs(dx) * 0.5))
            let radius = min(16, busOffset, abs(dy) * 0.5)
            let elbowX = origin.x + sx * busOffset
            path.move(to: origin)
            path.addLine(to: CGPoint(x: elbowX - sx * radius, y: origin.y))
            path.addQuadCurve(
                to: CGPoint(x: elbowX, y: origin.y + sy * radius),
                control: CGPoint(x: elbowX, y: origin.y)
            )
            path.addLine(to: CGPoint(x: elbowX, y: destination.y - sy * radius))
            path.addQuadCurve(
                to: CGPoint(x: elbowX + sx * radius, y: destination.y),
                control: CGPoint(x: elbowX, y: destination.y)
            )
            path.addLine(to: destination)
        } else if endsHorizontally {
            // MindNode sub-branch: single L — straight drop along the
            // parent's spine, one rounded corner, straight run into the
            // child's side.
            let radius = MapConnectorGeometry.singleLRadius(dx: dx, dy: dy)
            path.move(to: origin)
            path.addLine(to: CGPoint(x: origin.x, y: destination.y - sy * radius))
            path.addQuadCurve(
                to: CGPoint(x: origin.x + sx * radius, y: destination.y),
                control: CGPoint(x: origin.x, y: destination.y)
            )
            path.addLine(to: destination)
        } else {
            let busOffset = min(44, max(18, abs(dy) * 0.5))
            let radius = min(16, busOffset, abs(dx) * 0.5)
            let elbowY = origin.y + sy * busOffset
            path.move(to: origin)
            path.addLine(to: CGPoint(x: origin.x, y: elbowY - sy * radius))
            path.addQuadCurve(
                to: CGPoint(x: origin.x + sx * radius, y: elbowY),
                control: CGPoint(x: origin.x, y: elbowY)
            )
            path.addLine(to: CGPoint(x: destination.x - sx * radius, y: elbowY))
            path.addQuadCurve(
                to: CGPoint(x: destination.x, y: elbowY + sy * radius),
                control: CGPoint(x: destination.x, y: elbowY)
            )
            path.addLine(to: destination)
        }
        return path
    }

    @ViewBuilder
    private func nodeBubble(for node: MapNode, at point: CGPoint, size: CGSize) -> some View {
        MapNodeView(
            node: node,
            size: size,
            rootChildIndex: node.rootChildIndex,
            isSelected: viewModel.selectedNodeID == node.id,
            isDimmed: isDimmed(node),
            isCompact: viewModel.isCompact,
            isSearchMatch: viewModel.searchMatchIDs.contains(node.id),
            onSelect: { viewModel.selectedNodeID = node.id },
            onToggleCollapse: { viewModel.toggleCollapse(node) }
        )
        .position(point)
        .contextMenu { contextMenu(for: node) }
    }

    /// Scope emphasis is deliberately additive to branch-focus dimming. A
    /// node outside the selected plan window remains rendered and tappable;
    /// it simply does not compete with work that belongs to that window.
    private func isDimmed(_ node: MapNode) -> Bool {
        guard !viewModel.isDimmed(node.id) else { return true }
        let starts = node.displayTask?.liveSegments.map(\.startDate) ?? []
        return !MapTaskScopeFilter.shouldEmphasise(
            segmentStarts: starts,
            scope: taskScope,
            at: flow?.now ?? Date()
        )
    }

    // MARK: - Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($panDelta) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
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
                viewModel.zoom = min(max(viewModel.zoom * value, Self.minimumZoom), Self.maximumZoom)
                viewModel.persistCanvasState()
            }
    }

    /// The mock's clamp (`707-723`). The app had 0.25–3, which let the tree
    /// shrink past legibility at the bottom and stopped short of the mock's
    /// close-in reading at the top.
    static let minimumZoom: CGFloat = 0.5
    static let maximumZoom: CGFloat = 3.5

    /// Double-tap anywhere on the canvas puts pan and zoom back where they
    /// started — the way out of being lost that the mock gives, and the
    /// reason no "reset view" button is needed.
    private func resetViewport() {
        userAdjustedCanvas = false
        viewModel.zoom = 1
        viewModel.panOffset = .zero
        viewModel.persistCanvasState()
        viewModel.fitToMap(viewportSize: viewModel.viewportSize)
    }

    // MARK: - Context menu

    /// Collapse-toggle and Focus Branch are the only node actions the
    /// read-only auto map offers (R1–R7: no authoring).
    @ViewBuilder
    private func contextMenu(for node: MapNode) -> some View {
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
    }

    // MARK: - Empty state

    private var emptyState: some View {
        FlowEmptyState(
            symbol: "point.topleft.down.to.point.bottomright.curvepath",
            title: "Nothing planned yet.",
            message: "Tasks appear here once your day is planned."
        )
    }

    // MARK: - Floating controls

    private func zoom(by delta: CGFloat) {
        viewModel.zoom = min(max(viewModel.zoom + delta, Self.minimumZoom), Self.maximumZoom)
        viewModel.persistCanvasState()
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
