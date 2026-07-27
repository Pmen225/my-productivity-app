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
    let map: MapDocument

    @State private var viewModel: MapViewModel?
    @State private var isInspectorPresented = false

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
        .alert(
            "Delete this idea?",
            isPresented: deleteConfirmationBinding(viewModel),
            presenting: viewModel.pendingDeletion
        ) { node in
            Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
            Button("Delete", role: .destructive) { viewModel.confirmDelete() }
        } message: { node in
            Text(
                node.hasChildren
                    ? "\"\(node.title)\" and everything under it will be removed."
                    : "\"\(node.title)\" will be removed."
            )
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(_ viewModel: MapViewModel) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker(
                "View",
                selection: Binding(get: { viewModel.viewMode }, set: { viewModel.viewMode = $0 })
            ) {
                ForEach(MapViewMode.allCases, id: \.self) { mode in
                    Label(mode.displayName, systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
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

            #if !os(macOS)
            Button(action: { isInspectorPresented = true }) {
                Image(systemName: "info.circle")
            }
            .disabled(viewModel.selectedNode == nil)
            .accessibilityLabel("Idea details")
            #endif
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
}
