import SwiftData
import SwiftUI

/// The container for one open map: wires the Map/Outline switch, undo/redo,
/// node creation and the inspector into a single screen.
///
/// macOS gets the canvas (or outline) centred with the inspector as a fixed
/// right sidebar; iPhone gets a full-screen canvas with the inspector
/// presented as a sheet.
public struct MapDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    let map: MapDocument

    @State private var viewModel: MapViewModel?
    @State private var isInspectorPresented = false
    @State private var isLayoutMenuPresented = false

    public init(map: MapDocument) {
        self.map = map
    }

    public var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if viewModel == nil { viewModel = MapViewModel(map: map, context: context) }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: MapViewModel) -> some View {
        #if os(macOS)
        HStack(spacing: 0) {
            mainArea(viewModel)
            if let selected = viewModel.selectedNode {
                Divider()
                NodeInspectorView(node: selected)
                    .frame(width: 320)
            }
        }
        #else
        mainArea(viewModel)
            .sheet(isPresented: isInspectorBinding(viewModel)) {
                if let selected = viewModel.selectedNode {
                    NavigationStack {
                        NodeInspectorView(node: selected)
                            .navigationTitle(selected.title.isEmpty ? "Idea" : selected.title)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { isInspectorPresented = false }
                                }
                            }
                    }
                }
            }
        #endif
    }

    @ViewBuilder
    private func mainArea(_ viewModel: MapViewModel) -> some View {
        Group {
            switch viewModel.viewMode {
            case .map:
                MapCanvasView(viewModel: viewModel)
            case .outline:
                MapOutlineView(viewModel: viewModel)
            }
        }
        .navigationTitle(map.title)
        .toolbar { toolbarContent(viewModel) }
        .flowDeleteConfirmation(
            isPresented: deleteConfirmationBinding(viewModel),
            itemTitle: viewModel.pendingDeletion?.title ?? "",
            hasChildren: viewModel.pendingDeletion?.hasChildren ?? false,
            onDelete: { viewModel.confirmDelete() }
        )
    }

    @ToolbarContentBuilder
    private func toolbarContent(_ viewModel: MapViewModel) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            mapControlChip(viewModel)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: { viewModel.undo() }) {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!viewModel.canUndo)
            .accessibilityLabel("Undo")

            Button(action: { viewModel.redo() }) {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!viewModel.canRedo)
            .accessibilityLabel("Redo")

            Menu {
                Button("Add root topic") { viewModel.addRootTopic() }
                if let selected = viewModel.selectedNode {
                    Button("Add child") { viewModel.addChild(to: selected) }
                    Button("Add sibling") { viewModel.addSibling(to: selected) }
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add idea")

            // The canvas used to float this cluster over its own bottom-left
            // corner. It drew under the tab bar and lost its lower buttons the
            // moment that bar became visible, and no amount of re-anchoring
            // fixed it — a toolbar item cannot be occluded by anything.
            // Zoom in/out are gone rather than moved: pinch zooms, and a
            // double tap on the canvas resets.
            Menu {
                Button {
                    viewModel.isSearchPresented.toggle()
                } label: {
                    Label("Search ideas", systemImage: "magnifyingglass")
                }

                Button {
                    viewModel.isCompact.toggle()
                } label: {
                    Label(
                        viewModel.isCompact ? "Turn off compact mode" : "Turn on compact mode",
                        systemImage: viewModel.isCompact
                            ? "rectangle.expand.vertical"
                            : "rectangle.compress.vertical"
                    )
                }

                Section {
                    Button {
                        viewModel.fitToMap(viewportSize: viewModel.viewportSize)
                    } label: {
                        Label("Fit map", systemImage: "arrow.up.left.and.arrow.down.right")
                    }

                    Button {
                        viewModel.centreOnSelection(viewportSize: viewModel.viewportSize)
                    } label: {
                        Label("Centre selection", systemImage: "scope")
                    }
                    .disabled(viewModel.selectedNode == nil)

                    // In here rather than beside the toolbar's other buttons:
                    // a fifth trailing item squeezes the `Map | Outline | ⋯`
                    // chip out of the nav bar's centre entirely. Like Centre
                    // selection, this one needs a selected node anyway.
                    #if !os(macOS)
                    Button {
                        isInspectorPresented = true
                    } label: {
                        Label("Idea details", systemImage: "info.circle")
                    }
                    .disabled(viewModel.selectedNode == nil)
                    #endif
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Canvas controls")
        }
    }

    private func isInspectorBinding(_ viewModel: MapViewModel) -> Binding<Bool> {
        Binding(
            get: { isInspectorPresented && viewModel.selectedNode != nil },
            set: { isInspectorPresented = $0 }
        )
    }

    private func deleteConfirmationBinding(_ viewModel: MapViewModel) -> Binding<Bool> {
        Binding(
            get: { viewModel.pendingDeletion != nil },
            set: { if !$0 { viewModel.cancelDelete() } }
        )
    }

    // MARK: - Control chip

    /// The mock's centre chip: Map/Outline segments in a glass pill, with the
    /// layout menu behind a trailing ellipsis — the dark popover from the
    /// canvas reference, so it reuses `FlowPopoverMenu(.dark)`.
    private func mapControlChip(_ viewModel: MapViewModel) -> some View {
        HStack(spacing: 2) {
            controlSegment("Map", isActive: viewModel.viewMode == .map) {
                viewModel.viewMode = .map
            }
            controlSegment("Outline", isActive: viewModel.viewMode == .outline) {
                viewModel.viewMode = .outline
            }
            Button {
                isLayoutMenuPresented = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .frame(width: 26, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Layout options")
            .popover(isPresented: $isLayoutMenuPresented, arrowEdge: .top) {
                FlowPopoverMenu(
                    style: .dark,
                    options: MapLayoutOrientation.allCases.map {
                        FlowPopoverOption(id: $0, title: $0.displayName)
                    },
                    selection: viewModel.layoutOrientation
                ) { choice in
                    viewModel.layoutOrientation = choice
                    isLayoutMenuPresented = false
                }
                .presentationCompactAdaptation(.popover)
            }
        }
        .padding(3)
        .fixedSize()
        .flowGlass(radius: FlowRadius.chrome)
    }

    private func controlSegment(
        _ title: String, isActive: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(FlowFont.caption.weight(isActive ? .bold : .semibold))
                .foregroundStyle(
                    isActive ? FlowTheme.primaryText(scheme) : FlowTheme.secondaryText(scheme)
                )
                .padding(.horizontal, FlowSpacing.s)
                .frame(minHeight: 28)
                .background(
                    Capsule().fill(isActive ? FlowTheme.surface(scheme) : .clear)
                        .shadow(
                            color: isActive ? FlowTheme.shadow(scheme) : .clear,
                            radius: 3, y: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}
