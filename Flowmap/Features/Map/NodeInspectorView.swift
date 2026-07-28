import SwiftData
import SwiftUI

/// The full editor for one idea: title, notes, icon, colour, priority,
/// estimated duration, its task conversion, linked project and linked note.
/// Every field writes straight back to the model — there is no separate
/// draft state to lose.
public struct NodeInspectorView: View {
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme

    @Bindable private var node: MapNode

    public init(node: MapNode) {
        self._node = Bindable(node)
    }

    public var body: some View {
        Form {
            Section("Title") {
                TextField("Idea", text: $node.title)
                    .font(FlowFont.cardTitle)
                    .onChange(of: node.title) { _, _ in node.touch() }
            }

            Section("Notes") {
                TextEditor(text: $node.body)
                    .frame(minHeight: 80)
                    .onChange(of: node.body) { _, _ in node.touch() }
            }

            iconSection
            colourSection

            Section("Priority") {
                Picker("Priority", selection: $node.priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Label(priority.displayName, systemImage: priority.symbolName).tag(priority)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Duration") {
                Stepper(
                    DurationFormatter.compact(minutes: node.estimatedMinutes),
                    value: $node.estimatedMinutes,
                    in: 5...480,
                    step: 5
                )
                .onChange(of: node.estimatedMinutes) { _, _ in node.touch() }
                .accessibilityLabel("Estimated duration, \(DurationFormatter.spoken(minutes: node.estimatedMinutes))")
            }

            taskSection
            linkedProjectSection
            linkedNoteSection
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Icon

    private var iconSection: some View {
        Section("Icon") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FlowSpacing.s) {
                    ForEach(FlowSymbols.taskSymbols, id: \.self) { symbol in
                        Button(action: {
                            node.iconName = symbol
                            node.touch()
                            try? context.save()
                        }) {
                            Image(systemName: symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .foregroundStyle(node.iconName == symbol ? node.colour.onSoft : FlowTheme.secondaryText(scheme))
                                .background(
                                    Circle().fill(node.iconName == symbol ? node.colour.soft : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                        .accessibilityAddTraits(node.iconName == symbol ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, FlowSpacing.xxs)
            }
        }
    }

    // MARK: - Colour

    private var colourSection: some View {
        Section("Colour") {
            HStack(spacing: FlowSpacing.s) {
                ForEach(ColourToken.taskTokens, id: \.self) { token in
                    Button(action: {
                        node.colourToken = token.rawValue
                        node.touch()
                        try? context.save()
                    }) {
                        Circle()
                            .fill(token.base)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle().strokeBorder(Color.white, lineWidth: node.colour == token ? 2 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(token.displayName)
                    .accessibilityAddTraits(node.colour == token ? [.isSelected] : [])
                }
            }
        }
    }

    // MARK: - Task conversion

    private var taskSection: some View {
        Section("Task") {
            Toggle("Make this idea a task", isOn: taskToggleBinding)

            if let task = node.linkedTask {
                HStack {
                    StatusIndicator(
                        token: task.colour,
                        symbolName: task.status == .completed ? "checkmark" : "circle",
                        label: task.status.displayName
                    )
                    Text(task.status.displayName)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                    Spacer()
                    Button("Schedule now") { scheduleNow(task) }
                        .buttonStyle(.plain)
                        .foregroundStyle(FlowTheme.accent)
                    Button("Send to Inbox") { MapNodeConversion.sendToInbox(task) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var taskToggleBinding: Binding<Bool> {
        Binding(
            get: { node.isTask },
            set: { newValue in
                if newValue {
                    _ = MapNodeConversion.convertToTask(node, in: context)
                } else {
                    node.isTask = false
                    node.touch()
                    try? context.save()
                }
            }
        )
    }

    private func scheduleNow(_ task: FlowTask) {
        guard let flow else { return }
        MapNodeConversion.scheduleNow(task, using: flow.scheduling(), now: flow.now)
        try? context.save()
    }

    // MARK: - Linked project

    /// A node has no project of its own — it follows the map's. Shown
    /// read-only rather than as an editable field, since re-parenting a node
    /// to a different project would mean re-parenting its whole map.
    private var linkedProjectSection: some View {
        Section("Linked project") {
            if let project = node.map?.project {
                HStack {
                    Image(systemName: project.iconName).foregroundStyle(project.colour.base)
                    Text(project.title)
                }
            } else {
                Text("Not linked to a project.")
                    .foregroundStyle(.secondary)
            }
            Text("Inherited from the map — set it from the map's own settings.")
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.secondaryText(scheme))
        }
    }

    // MARK: - Linked note

    private var linkedNoteSection: some View {
        Section("Linked note") {
            if let note = node.linkedNote {
                HStack {
                    Image(systemName: note.iconName).foregroundStyle(FlowTheme.accent)
                    Text(note.title.isEmpty ? "Untitled note" : note.title)
                    Spacer()
                    Button("Unlink", role: .destructive) {
                        node.linkedNote = nil
                        node.touch()
                        try? context.save()
                    }
                }
            } else {
                Button {
                    createNote()
                } label: {
                    Label("New note", systemImage: "doc.badge.plus")
                }
            }
        }
    }

    private func createNote() {
        let note = Note(
            title: node.title,
            workspace: node.map?.workspace,
            project: node.map?.project
        )
        context.insert(note)
        node.linkedNote = note
        node.touch()
        try? context.save()
    }
}
