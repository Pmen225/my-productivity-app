import SwiftUI

/// Pure viewport maths shared by the live gesture and its regression tests.
/// Keeping this outside the view prevents the pinch anchor from drifting when
/// the gesture implementation changes.
enum MapViewportGeometry {
    static func clampedZoom(_ zoom: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(zoom, minimum), maximum)
    }

    /// Returns the pan offset that keeps the content point under `anchor`
    /// under that same finger while zoom changes.
    static func anchoredPanOffset(
        currentPan: CGSize,
        currentZoom: CGFloat,
        nextZoom: CGFloat,
        anchor: CGPoint
    ) -> CGSize {
        guard currentZoom > 0 else { return currentPan }
        let ratio = nextZoom / currentZoom
        return CGSize(
            width: anchor.x - (anchor.x - currentPan.width) * ratio,
            height: anchor.y - (anchor.y - currentPan.height) * ratio
        )
    }

    static func screenFrame(
        contentCentre: CGPoint,
        contentSize: CGSize,
        zoom: CGFloat,
        pan: CGSize,
        minimumHitSize: CGFloat = 44
    ) -> CGRect {
        let width = max(contentSize.width * zoom, minimumHitSize)
        let height = max(contentSize.height * zoom, minimumHitSize)
        let centre = CGPoint(
            x: contentCentre.x * zoom + pan.width,
            y: contentCentre.y * zoom + pan.height
        )
        return CGRect(x: centre.x - width / 2, y: centre.y - height / 2, width: width, height: height)
    }

    static func shouldBeginCanvasPan(at location: CGPoint, nodeFrames: [CGRect]) -> Bool {
        !nodeFrames.contains { $0.contains(location) }
    }
}

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
    private struct PinchAdjustment {
        var scale: CGFloat = 1
        var pan: CGSize = .zero
    }

    @GestureState private var pinchAdjustment = PinchAdjustment()
    @GestureState private var panDelta: CGSize = .zero
    @Namespace private var layoutSelection
    /// Founder: "I should be able to hold a task in Maps and edit it from
    /// there." Set from the context menu's "Edit task" item — the menu
    /// itself already opens on a long-press, so no separate gesture is
    /// needed. Hosted on this view's own body, not a nested one: a `.sheet`
    /// attached inside a `Section`-rooted view never presents (see
    /// `PlanInboxSection`'s prior bug), and this canvas's body root is a
    /// plain `GeometryReader`, so it is safe here.
    @State private var taskSheetRoute: TaskSheetRoute?

    private struct TaskSheetRoute: Identifiable {
        enum Mode: Equatable { case edit, createChild }
        let task: FlowTask
        let mode: Mode
        var id: String { "\(task.id.uuidString)-\(mode == .edit ? "edit" : "child")" }
    }

    private var metrics: MapLayout.Metrics { .shared }
    private let margin: CGFloat = 160

    init(viewModel: MapViewModel, taskScope: TodayScope? = nil) {
        self.viewModel = viewModel
        self.taskScope = taskScope
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                FlowTheme.background(scheme)
                    .contentShape(Rectangle())

                canvasContent
                    .scaleEffect(viewModel.zoom * pinchAdjustment.scale, anchor: .topLeading)
                    .offset(
                        x: viewModel.panOffset.width + panDelta.width + pinchAdjustment.pan.width,
                        y: viewModel.panOffset.height + panDelta.height + pinchAdjustment.pan.height
                    )
            }
            // The map content is intentionally wider/taller than the phone.
            // Keep chrome aligned to the viewport, not to that infinite-feeling
            // content frame, or the layout control lands hundreds of points
            // offscreen at the canvas's trailing edge.
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            // Host panning on the viewport itself. The content layer fills a
            // much larger frame than the phone, so a gesture attached only to
            // the background never receives drags over that layer's empty
            // space. Simultaneous recognition preserves node taps and menus;
            // the 10pt threshold below keeps ordinary taps out of the drag.
            .simultaneousGesture(panGesture)
            .simultaneousGesture(pinchGesture)
            // Ahead of the pan gesture in the chain, so a quick double tap is
            // read as a reset rather than two aborted drags.
            .simultaneousGesture(TapGesture(count: 2).onEnded { resetViewport() })
            .onAppear {
                viewModel.viewportSize = proxy.size
                scheduleAutomaticFit(viewportSize: proxy.size)
            }
            // AutoMapScreen replaces its transient MapViewModel whenever the
            // task hierarchy changes. Keep this view's sheet route alive, but
            // reset the fit state for the new tree; keying the whole canvas by
            // map id dismisses an in-flight child-task sheet as soon as its
            // blank draft enters SwiftData.
            .onChange(of: viewModel.map.id) { _, _ in
                hasFitted = false
                userAdjustedCanvas = false
                scheduleAutomaticFit(viewportSize: proxy.size)
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
            .overlay(alignment: .topTrailing) {
                HStack(spacing: FlowSpacing.xs) {
                    mapSearchControl
                    mapLayoutControl
                }
                .padding(.top, FlowSpacing.s)
                .padding(.trailing, FlowSpacing.screen)
            }
        }
        .clipped()
        .sheet(item: $taskSheetRoute) { route in
            switch route.mode {
            case .edit:
                NavigationStack { TaskDetailInspector(task: route.task) }
            case .createChild:
                QuickCaptureView(
                    initialProjectID: route.task.project?.id,
                    initialListID: route.task.list?.id,
                    initialParentTaskID: route.task.id
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(FlowRadius.large)
            }
        }
    }

    /// A map that has never been positioned opens fitted, rather than with
    /// the tree running off the edge of the canvas. Deferred twice because
    /// SwiftData can fault child relationships in after the first layout.
    private func scheduleAutomaticFit(viewportSize: CGSize) {
        guard !hasFitted,
              viewModel.map.canvasOffsetX == 0,
              viewModel.map.canvasOffsetY == 0 else { return }
        hasFitted = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            viewModel.fitToMap(viewportSize: viewportSize)
            try? await Task.sleep(for: .milliseconds(600))
            guard !userAdjustedCanvas else { return }
            viewModel.fitToMap(viewportSize: viewportSize)
        }
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
                        // The connector is the same semantic colour as its
                        // child task/project, so Plan, wheel and map never
                        // disagree about what colour a piece of work owns.
                        colour: node.colour.base.opacity(0.68),
                        dimmed: isDimmed(node) || isDimmed(parent),
                        in: context
                    )
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .allowsHitTesting(false)

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
            let origin = MapConnectorGeometry.horizontalStart(
                parentCenter: start,
                parentSize: startSize,
                branchPortOffset: metrics.accessoryAllowance / 2
            )
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
            // Butt caps stop the 4pt stroke extending beyond its measured
            // node ports; the rounded geometry still supplies soft elbows.
            style: StrokeStyle(lineWidth: MapConnectorGeometry.lineWidth, lineCap: .butt)
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
            orientation: viewModel.layoutOrientation,
            isSelected: viewModel.selectedNodeID == node.id,
            isDimmed: isDimmed(node),
            isCompact: viewModel.isCompact,
            isSearchMatch: viewModel.searchMatchIDs.contains(node.id),
            onSelect: { select(node) },
            onToggleCollapse: { toggleCollapse(node) },
            onAddChild: addChildAction(for: node)
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

    private var nodeHitFrames: [CGRect] {
        let positions = positionMap
        let sizes = sizeMap
        let shift = originShift
        return viewModel.visibleNodes.compactMap { node in
            guard let point = positions[node.id], let size = sizes[node.id] else { return nil }
            return MapViewportGeometry.screenFrame(
                contentCentre: CGPoint(x: point.x + shift.x, y: point.y + shift.y),
                contentSize: size,
                zoom: viewModel.zoom,
                pan: viewModel.panOffset
            )
        }
    }

    private func canBeginCanvasPan(at location: CGPoint) -> Bool {
        MapViewportGeometry.shouldBeginCanvasPan(at: location, nodeFrames: nodeHitFrames)
    }

    private var panGesture: some Gesture {
        // Four points tracks a deliberate background drag promptly. A drag
        // beginning on any node is rejected, so slightly moving while tapping
        // a label never pulls the entire map away.
        DragGesture(minimumDistance: 4)
            .updating($panDelta) { value, state, _ in
                guard canBeginCanvasPan(at: value.startLocation) else { return }
                state = value.translation
            }
            .onEnded { value in
                guard canBeginCanvasPan(at: value.startLocation) else { return }
                userAdjustedCanvas = true
                viewModel.panOffset.width += value.translation.width
                viewModel.panOffset.height += value.translation.height
                viewModel.persistCanvasState()
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .updating($pinchAdjustment) { value, state, _ in
                let nextZoom = MapViewportGeometry.clampedZoom(
                    viewModel.zoom * value.magnification,
                    minimum: Self.minimumZoom,
                    maximum: Self.maximumZoom
                )
                let anchor = CGPoint(
                    x: value.startAnchor.x * viewModel.viewportSize.width,
                    y: value.startAnchor.y * viewModel.viewportSize.height
                )
                let nextPan = MapViewportGeometry.anchoredPanOffset(
                    currentPan: viewModel.panOffset,
                    currentZoom: viewModel.zoom,
                    nextZoom: nextZoom,
                    anchor: anchor
                )
                state.scale = nextZoom / viewModel.zoom
                state.pan = CGSize(
                    width: nextPan.width - viewModel.panOffset.width,
                    height: nextPan.height - viewModel.panOffset.height
                )
            }
            .onEnded { value in
                userAdjustedCanvas = true
                let nextZoom = MapViewportGeometry.clampedZoom(
                    viewModel.zoom * value.magnification,
                    minimum: Self.minimumZoom,
                    maximum: Self.maximumZoom
                )
                let anchor = CGPoint(
                    x: value.startAnchor.x * viewModel.viewportSize.width,
                    y: value.startAnchor.y * viewModel.viewportSize.height
                )
                viewModel.panOffset = MapViewportGeometry.anchoredPanOffset(
                    currentPan: viewModel.panOffset,
                    currentZoom: viewModel.zoom,
                    nextZoom: nextZoom,
                    anchor: anchor
                )
                viewModel.zoom = nextZoom
                viewModel.persistCanvasState()
            }
    }

    /// Widened 2026-08-10 — founder: "allow freee zoom till certain extent in
    /// map". 0.5–3.5 (itself widened from the mock's `707-723` 0.25–3) still
    /// read as capped under a real pinch; 0.35–6.0 gives the gesture room
    /// while keeping both ends bounded — text stays legible at the top,
    /// pills stay hittable (44pt rule applies to rendered size) at the
    /// bottom. Read by both clamp sites below; do not add a third copy.
    static let minimumZoom: CGFloat = 0.35
    static let maximumZoom: CGFloat = 6.0

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

    private func select(_ node: MapNode) {
        guard viewModel.selectedNodeID != node.id else { return }
        viewModel.selectedNodeID = node.id
        if flow?.settings.focusHapticsEnabled ?? false { FlowHaptic.light.play() }
    }

    private func toggleCollapse(_ node: MapNode) {
        let update = {
            viewModel.toggleCollapse(node)
            viewModel.fitToMap(viewportSize: viewModel.viewportSize)
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(FlowMotion.expand) { update() }
        }
        if flow?.settings.focusHapticsEnabled ?? false { FlowHaptic.light.play() }
    }

    private func addChildAction(for node: MapNode) -> (() -> Void)? {
        guard let task = node.displayTask,
              task.hierarchyDepth < FlowTask.maximumHierarchyLevels - 1 else { return nil }
        return { taskSheetRoute = TaskSheetRoute(task: task, mode: .createChild) }
    }

    // MARK: - Context menu

    /// Collapse-toggle and Focus Branch were the only node actions while the
    /// auto map stayed read-only (R1–R7: no authoring). Reversed 2026-08-10 —
    /// founder: "I should be able to hold a task in Maps and edit it from
    /// there" — so a node backed by a real task also gets "Edit task",
    /// opening the same `TaskDetailInspector` every other screen uses
    /// (`editingTask` above). Still no node CREATION or deletion from here;
    /// only editing an existing linked task.
    @ViewBuilder
    private func contextMenu(for node: MapNode) -> some View {
        if let task = node.displayTask {
            Button("Edit task", systemImage: "pencil") {
                taskSheetRoute = TaskSheetRoute(task: task, mode: .edit)
            }
            if task.hierarchyDepth < FlowTask.maximumHierarchyLevels - 1 {
                Button("New child task", systemImage: "plus") {
                    taskSheetRoute = TaskSheetRoute(task: task, mode: .createChild)
                }
            }
        }
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

    private var mapSearchControl: some View {
        Button {
            viewModel.isSearchPresented.toggle()
            if !viewModel.isSearchPresented {
                viewModel.searchQuery = ""
            }
        } label: {
            Image(systemName: viewModel.isSearchPresented ? "xmark" : "magnifyingglass")
                .font(FlowFont.body.weight(.medium))
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(LayoutPressStyle())
        .padding(4)
        .flowGlass(radius: FlowRadius.small)
        .accessibilityIdentifier("map-search")
        .accessibilityLabel(viewModel.isSearchPresented ? "Hide map search" : "Search map")
        .accessibilityHint("Shows the map search field")
        .accessibilityValue(viewModel.isSearchPresented ? "Shown" : "Hidden")
        .accessibilityAddTraits(viewModel.isSearchPresented ? .isSelected : [])
    }

    private func zoom(by delta: CGFloat) {
        viewModel.zoom = min(max(viewModel.zoom + delta, Self.minimumZoom), Self.maximumZoom)
        viewModel.persistCanvasState()
    }

    @ViewBuilder
    private var mapLayoutControl: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            liquidGlassLayoutControl
        } else {
            fallbackLayoutControl
        }
        #else
        fallbackLayoutControl
        #endif
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var liquidGlassLayoutControl: some View {
        GlassEffectContainer(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(MapLayoutOrientation.allCases, id: \.rawValue) { orientation in
                    let isSelected = viewModel.layoutOrientation == orientation
                    Button { selectLayout(orientation) } label: {
                        Image(systemName: orientation.symbolName)
                            .font(.system(size: 18, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(isSelected ? FlowTheme.accent : FlowTheme.secondaryText(scheme))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(LayoutPressStyle())
                    .background {
                        if isSelected {
                            Circle()
                                .fill(FlowTheme.accent.opacity(scheme == .dark ? 0.12 : 0.06))
                                .glassEffect(
                                    .regular.tint(FlowTheme.accent.opacity(scheme == .dark ? 0.22 : 0.13)).interactive(),
                                    in: Circle()
                                )
                                .glassEffectID("map-layout-selection", in: layoutSelection)
                                .matchedGeometryEffect(id: "map-layout-selection-position", in: layoutSelection)
                        }
                    }
                    .accessibilityIdentifier(orientation.accessibilityIdentifier)
                    .accessibilityLabel(orientation.displayName)
                    .accessibilityHint("Changes the map layout")
                    .accessibilityValue(isSelected ? "Selected" : "")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(4)
            .glassEffect(.clear.interactive(), in: Capsule(style: .continuous))
        }
        .accessibilityElement(children: .contain)
    }

    private var fallbackLayoutControl: some View {
        HStack(spacing: 0) {
            ForEach(MapLayoutOrientation.allCases, id: \.rawValue) { orientation in
                let isSelected = viewModel.layoutOrientation == orientation
                Button { selectLayout(orientation) } label: {
                    Image(systemName: orientation.symbolName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isSelected ? FlowTheme.accent : FlowTheme.secondaryText(scheme))
                        .frame(width: 44, height: 44)
                        .background(isSelected ? FlowTheme.accent.opacity(0.10) : .clear, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(LayoutPressStyle())
                .accessibilityIdentifier(orientation.accessibilityIdentifier)
                .accessibilityLabel(orientation.displayName)
                .accessibilityHint("Changes the map layout")
                .accessibilityValue(isSelected ? "Selected" : "")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(FlowTheme.glassBorder(scheme), lineWidth: 1))
        .shadow(color: FlowTheme.shadow(scheme), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
    }

    private func selectLayout(_ orientation: MapLayoutOrientation) {
        guard viewModel.layoutOrientation != orientation else { return }
        userAdjustedCanvas = false
        let update = {
            viewModel.layoutOrientation = orientation
            viewModel.fitToMap(viewportSize: viewModel.viewportSize)
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(FlowMotion.travel) { update() }
        }
        if flow?.settings.focusHapticsEnabled ?? false { FlowHaptic.light.play() }
    }

    private struct LayoutPressStyle: ButtonStyle {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.70 : 1)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
                .animation(reduceMotion ? nil : FlowMotion.tap, value: configuration.isPressed)
        }
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
                .flowHitTarget()
                .accessibilityIdentifier("map-search-clear")
                .accessibilityLabel("Clear search")
                .accessibilityHint("Clears the map search text")
            }
        }
        .padding(.horizontal, FlowSpacing.m)
        .padding(.vertical, FlowSpacing.s)
        .flowGlass(radius: FlowRadius.small)
        // Keep the field below the top-right control capsule so its clear
        // button is visibly and physically tappable when the search is open.
        .padding(.top, FlowSpacing.xxxl)
        .frame(maxWidth: 320)
    }
}
