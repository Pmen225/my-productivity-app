import SwiftData
import SwiftUI

/// The Map + Today map pane (Task 63): no map to create or edit, just a live
/// picture of what's actually planned. Builds `AutoMapBuilder`'s tree fresh
/// from the current scope's tasks and hosts it read-only in the existing
/// canvas (R1–R7).
///
/// Nothing here ever reaches the store (R4/R5): `AutoMapBuilder` is pure, and
/// the transient `MapDocument`/`MapViewModel` wrapping its output are plain,
/// never-inserted instances rebuilt whenever the planned window's data
/// actually changes.
struct AutoMapScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.flow) private var flow
    @Query private var tasks: [FlowTask]

    let scope: TodayScope
    let includesBacklog: Bool

    /// False when this is the Map pane of `MapTodayScreen`, which owns the
    /// nav bar's centre for its own `Map | Today` toggle.
    private let showsScreenTitle: Bool

    @State private var viewModel: MapViewModel?
    @State private var lastKey: RebuildKey?
    @AppStorage("autoMapLayoutOrientation") private var savedLayoutOrientationRaw =
        MapLayoutOrientation.leftToRight.rawValue

    init(scope: TodayScope, showsScreenTitle: Bool = true, includesBacklog: Bool = false) {
        self.scope = scope
        self.showsScreenTitle = showsScreenTitle
        self.includesBacklog = includesBacklog
    }

    private var now: Date { flow?.now ?? Date() }

    var body: some View {
        Group {
            if let viewModel {
                MapCanvasView(viewModel: viewModel, taskScope: nil)
            } else {
                emptyState
            }
        }
        .modifier(OptionalMapScreenTitle(title: scope.paneTitle, isEnabled: showsScreenTitle))
        .onAppear { rebuildIfNeeded() }
        .onChange(of: rebuildKey) { _, _ in rebuildIfNeeded() }
        .onChange(of: viewModel?.layoutOrientation) { _, orientation in
            guard let orientation else { return }
            savedLayoutOrientationRaw = orientation.rawValue
        }
    }

    // MARK: - Rebuild (R4: never store, rebuild on change via a cheap fingerprint)

    /// Cheap enough to compute every body evaluation without re-running
    /// `AutoMapBuilder` itself. `MapNode.init` always mints a fresh `UUID`,
    /// so the tree can't be compared directly — this key stands in for "did
    /// anything the tree depends on change" so an unrelated re-render
    /// doesn't reset the canvas's pan/zoom/collapse state.
    private struct RebuildKey: Equatable {
        let scope: TodayScope
        let signature: [String]
    }

    private var rebuildKey: RebuildKey {
        let signature = tasks.flatMap { task -> [String] in
            var parts = [
                task.id.uuidString,
                task.title,
                task.colourToken,
                task.project?.id.uuidString ?? "",
                task.parentTask?.id.uuidString ?? "",
                task.statusRaw,
            ]
            parts += task.liveSegments.map { "\($0.id)|\($0.startDate.timeIntervalSince1970)" }
            parts += task.orderedChildTasks.map { "child|\($0.id)|\($0.sortOrder)" }
            parts += task.orderedSubtasks.map { "\($0.id)|\($0.title)|\($0.isCompleted)" }
            return parts
        }
        return RebuildKey(scope: scope, signature: signature)
    }

    private func rebuildIfNeeded() {
        let key = rebuildKey
        guard key != lastKey else { return }
        lastKey = key

        // The automatic map is transient, but the person's chosen way of
        // reading it is not. Creating or editing a task rebuilds the tree;
        // carry the active orientation into the replacement document so an
        // org chart never snaps back to a horizontal map mid-authoring.
        let activeOrientation = viewModel?.layoutOrientation
            ?? MapLayoutOrientation(rawValue: savedLayoutOrientationRaw)
            ?? .leftToRight

        guard let root = AutoMapBuilder.build(
            scope: scope,
            reference: now,
            tasks: tasks,
            includesBacklog: includesBacklog
        ) else {
            viewModel = nil
            return
        }
        let document = MapDocument(title: scope.paneTitle)
        document.layoutOrientation = activeOrientation
        document.nodes = root.subtreeNodes
        viewModel = MapViewModel(map: document, context: context)
    }

    // MARK: - Empty state (R10)

    private var emptyState: some View {
        VStack(spacing: FlowSpacing.l) {
            FlowEmptyState(
                symbol: "point.topleft.down.to.point.bottomright.curvepath",
                title: includesBacklog ? "No tasks yet." : "Nothing planned yet.",
                message: includesBacklog
                    ? "Tap + to add a task, then grow it into a branch."
                    : "Tasks appear here once your day is planned."
            )
            if !includesBacklog {
                SecondaryActionButton("Plan your day", systemImage: "square.stack") {
                    NotificationCenter.default.post(
                        name: .flowmapOpenDeepLink,
                        object: DeepLinkRequest(destination: .inbox)
                    )
                }
            }
        }
        .padding(FlowSpacing.screen)
    }
}

/// Applies `.flowScreenTitle` only when the host isn't already using the nav
/// bar's centre for something of its own.
private struct OptionalMapScreenTitle: ViewModifier {
    let title: String
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .navigationTitle(title)
                .flowScreenTitle(title)
        } else {
            content
        }
    }
}
