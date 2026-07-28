import SwiftUI

// MARK: - Overview

/// Summary, status, priority, timeline and progress. Progress always reads
/// `project.progress` — there is no second, storable progress value to drift
/// out of sync with it.
public struct ProjectOverviewTab: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context
    @Environment(\.flow) private var flow
    @Bindable var project: Project

    public init(project: Project) {
        self._project = Bindable(project)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.l) {
            progressCard

            FlowCard {
                VStack(alignment: .leading, spacing: FlowSpacing.m) {
                    FlowEyebrow("Summary")
                    TextEditor(text: $project.summary)
                        .frame(minHeight: 80)
                }
            }

            FlowCard {
                VStack(alignment: .leading, spacing: FlowSpacing.m) {
                    Picker("Status", selection: $project.status) {
                        ForEach(ProjectStatus.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Priority", selection: $project.priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
            }

            FlowCard {
                VStack(alignment: .leading, spacing: FlowSpacing.m) {
                    FlowEyebrow("Timeline")
                    optionalDateRow(title: "Start date", date: startDateBinding)
                    optionalDateRow(title: "Due date", date: dueDateBinding)
                }
            }

            colourRow
        }
        .padding(FlowSpacing.screen)
        .onChange(of: project.status) { oldStatus, newStatus in
            // "Project closed" is this app's Project reaching .completed — the
            // one place the design's per-task bonus has an event to hang off.
            guard newStatus == .completed, oldStatus != .completed else { return }
            flow?.gamification.award(.projectClosed(taskCount: project.actionableTasks.count))
        }
    }

    private var progressCard: some View {
        FlowCard {
            HStack(spacing: FlowSpacing.l) {
                VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                    FlowEyebrow("Progress")
                    Text("\(project.completedTaskCount) of \(project.actionableTasks.count) tasks complete")
                        .font(FlowFont.secondary)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(project.colour.soft, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: project.progress)
                        .stroke(project.colour.base, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(project.progressPercentText)
                        .font(FlowFont.caption.weight(.semibold))
                }
                .frame(width: 52, height: 52)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Progress \(project.progressPercentText)")
            }
        }
    }

    private var colourRow: some View {
        FlowCard {
            HStack {
                FlowEyebrow("Colour")
                Spacer()
                ForEach(ColourToken.taskTokens, id: \.self) { token in
                    Button {
                        project.colourToken = token.rawValue
                        project.touch()
                    } label: {
                        Circle()
                            .fill(token.base)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().strokeBorder(.primary, lineWidth: project.colour == token ? 2 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(token.displayName)
                }
            }
        }
    }

    @ViewBuilder
    private func optionalDateRow(title: String, date: Binding<Date?>) -> some View {
        HStack {
            Text(title).font(FlowFont.secondary)
            Spacer()
            if let unwrapped = date.wrappedValue {
                DatePicker("", selection: Binding(get: { unwrapped }, set: { date.wrappedValue = $0 }), displayedComponents: .date)
                    .labelsHidden()
                Button {
                    date.wrappedValue = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear \(title.lowercased())")
            } else {
                Button("Set") { date.wrappedValue = Date() }
                    .buttonStyle(.plain)
                    .foregroundStyle(FlowTheme.accent)
            }
        }
    }

    private var startDateBinding: Binding<Date?> {
        Binding(get: { project.startDate }, set: { project.startDate = $0; project.touch() })
    }

    private var dueDateBinding: Binding<Date?> {
        Binding(get: { project.dueDate }, set: { project.dueDate = $0; project.touch() })
    }
}

// MARK: - Map

/// A read-only summary of the project's linked maps — the canvas editor
/// itself belongs to the Map feature.
public struct ProjectMapTab: View {
    @Environment(\.colorScheme) private var scheme
    let project: Project

    public init(project: Project) {
        self.project = project
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.m) {
            if (project.maps ?? []).isEmpty {
                FlowEmptyState(
                    symbol: "point.3.connected.trianglepath.dotted",
                    title: "No map yet",
                    message: "Create a map from the Map tab and link it to this project."
                )
            } else {
                ForEach(project.maps ?? []) { map in
                    FlowCard {
                        HStack(spacing: FlowSpacing.m) {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .foregroundStyle(map.theme.onSoft)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(map.theme.soft))
                            VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                                Text(map.title).font(FlowFont.cardTitle)
                                Text("\(map.nodeCount) nodes")
                                    .font(FlowFont.caption)
                                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(FlowSpacing.screen)
    }
}

// MARK: - Notes

/// A read-only summary of the project's linked notes — the block editor
/// itself belongs to the Notes feature.
public struct ProjectNotesTab: View {
    @Environment(\.colorScheme) private var scheme
    let project: Project

    public init(project: Project) {
        self.project = project
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.m) {
            if (project.notes ?? []).isEmpty {
                FlowEmptyState(
                    symbol: "doc.text",
                    title: "No notes yet",
                    message: "Create a note from the Notes tab and link it to this project."
                )
            } else {
                ForEach(project.notes ?? []) { note in
                    FlowCard {
                        HStack(spacing: FlowSpacing.m) {
                            Image(systemName: note.iconName)
                                .foregroundStyle(FlowTheme.accent)
                            VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                                Text(note.title.isEmpty ? "Untitled note" : note.title)
                                    .font(FlowFont.cardTitle)
                                if !note.preview.isEmpty {
                                    Text(note.preview)
                                        .font(FlowFont.caption)
                                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(FlowSpacing.screen)
    }
}
