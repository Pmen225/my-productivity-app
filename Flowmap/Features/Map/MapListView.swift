import SwiftData
import SwiftUI

/// The Maps library screen. Default state is a compact `MAPS (0)` header and
/// a compact `+` — never a permanent full-width "Add a map" row.
public struct MapListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MapDocument.title) private var maps: [MapDocument]

    @State private var isAddingMap = false
    @State private var searchText = ""
    @State private var renamingMap: MapDocument?
    @State private var renameDraft = ""

    public init() {}

    public var body: some View {
        List {
            Section {
                CompactSectionHeader(
                    title: "Maps",
                    count: filteredMaps.count,
                    addLabel: "Add map",
                    onAdd: { withAnimation(.snappy) { isAddingMap.toggle() } }
                )
                .listRowSeparator(.hidden)

                if isAddingMap {
                    NewMapView(onFinished: { withAnimation(.snappy) { isAddingMap = false } })
                        .listRowSeparator(.hidden)
                }
            }

            if filteredMaps.isEmpty {
                FlowEmptyState(
                    symbol: "point.topleft.down.to.point.bottomright.curvepath",
                    title: "No maps yet",
                    message: "Start a mind map to turn a loose idea into a plan."
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(filteredMaps) { map in
                    NavigationLink(value: map) {
                        MapRow(map: map)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            renameDraft = map.title
                            renamingMap = map
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
                .onDelete(perform: deleteMaps)
            }
        }
        .navigationTitle("Maps")
        .searchable(text: $searchText, placement: .automatic, prompt: "Search maps")
        .navigationDestination(for: MapDocument.self) { map in
            MapDetailView(map: map)
        }
        .alert("Rename map", isPresented: renamingBinding) {
            TextField("Map title", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save", action: commitRename)
        }
    }

    private var filteredMaps: [MapDocument] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return maps }
        return maps.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renamingMap != nil }, set: { if !$0 { renamingMap = nil } })
    }

    private func commitRename() {
        guard let map = renamingMap else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        map.title = trimmed
        map.touch()
        try? context.save()
        renamingMap = nil
    }

    private func deleteMaps(at offsets: IndexSet) {
        for index in offsets { context.delete(filteredMaps[index]) }
        try? context.save()
    }
}

// MARK: - Row

/// One row on the Maps screen: theme colour, title and a node count.
private struct MapRow: View {
    @Environment(\.colorScheme) private var scheme
    let map: MapDocument

    var body: some View {
        HStack(spacing: FlowSpacing.m) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(map.theme.onSoft)
                .frame(width: 36, height: 36)
                .background(Circle().fill(map.theme.soft))

            VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                Text(map.title)
                    .font(FlowFont.cardTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                Text("\(map.nodeCount) idea\(map.nodeCount == 1 ? "" : "s")")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }

            Spacer(minLength: FlowSpacing.s)
        }
        .padding(.vertical, FlowSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Creation

/// The inline form revealed after pressing the compact `+` on the Maps
/// screen. Kept short: title and a colour — the map opens straight onto its
/// empty canvas for the first topic.
private struct NewMapView: View {
    @Environment(\.modelContext) private var context

    private let onFinished: () -> Void

    @State private var title = ""
    @State private var themeToken: ColourToken = .violet

    @FocusState private var titleFocused: Bool

    init(onFinished: @escaping () -> Void = {}) {
        self.onFinished = onFinished
    }

    var body: some View {
        FlowCard(padding: FlowSpacing.m) {
            VStack(alignment: .leading, spacing: FlowSpacing.m) {
                TextField("New map title", text: $title)
                    .font(FlowFont.cardTitle)
                    .focused($titleFocused)
                    .onSubmit(createMap)

                colourControl

                HStack {
                    Button("Cancel") { onFinished() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Spacer()
                    PrimaryActionButton("Add map", systemImage: "plus", action: createMap)
                        .fixedSize()
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { titleFocused = true }
    }

    private var colourControl: some View {
        Menu {
            ForEach(ColourToken.allCases, id: \.self) { token in
                Button(token.displayName) { themeToken = token }
            }
        } label: {
            HStack(spacing: FlowSpacing.xs) {
                Circle().fill(themeToken.base).frame(width: 14, height: 14)
                Text(themeToken.displayName).font(FlowFont.caption)
            }
        }
        .accessibilityLabel("Colour: \(themeToken.displayName)")
    }

    private func createMap() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let map = MapDocument(title: trimmed, themeToken: themeToken.rawValue)
        context.insert(map)
        try? context.save()
        onFinished()
    }
}
