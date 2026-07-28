import SwiftData
import SwiftUI

/// The inline form revealed after pressing the compact `+` on the Projects
/// screen. Kept short: title, an optional due date and a colour — a project's
/// deeper detail belongs in `ProjectDetailView`, not in the creation step.
public struct NewProjectView: View {
    @Environment(\.modelContext) private var context

    private let onFinished: () -> Void

    @State private var title = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var colourToken: ColourToken = .teal

    @FocusState private var titleFocused: Bool

    public init(onFinished: @escaping () -> Void = {}) {
        self.onFinished = onFinished
    }

    public var body: some View {
        FlowCard(padding: FlowSpacing.m) {
            VStack(alignment: .leading, spacing: FlowSpacing.m) {
                TextField("New project title", text: $title)
                    .font(FlowFont.cardTitle)
                    .focused($titleFocused)
                    .onSubmit(createProject)

                HStack(spacing: FlowSpacing.m) {
                    dateControl
                    colourControl
                }

                HStack {
                    Button("Cancel") { onFinished() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Spacer()
                    PrimaryActionButton("Add project", systemImage: "plus", action: createProject)
                        .fixedSize()
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { titleFocused = true }
    }

    private var dateControl: some View {
        HStack(spacing: FlowSpacing.xs) {
            if hasDueDate {
                DatePicker("", selection: $dueDate, displayedComponents: .date)
                    .labelsHidden()
                Button {
                    hasDueDate = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear due date")
            } else {
                Button {
                    hasDueDate = true
                } label: {
                    Label("Due date", systemImage: "calendar")
                        .font(FlowFont.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var colourControl: some View {
        Menu {
            ForEach(ColourToken.taskTokens, id: \.self) { token in
                Button(token.displayName) { colourToken = token }
            }
        } label: {
            HStack(spacing: FlowSpacing.xs) {
                Circle().fill(colourToken.base).frame(width: 14, height: 14)
                Text(colourToken.displayName).font(FlowFont.caption)
            }
        }
        .accessibilityLabel("Colour: \(colourToken.displayName)")
    }

    private func createProject() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let existingCount = (try? context.fetchCount(FetchDescriptor<Project>())) ?? 0
        let project = Project(
            title: trimmed,
            colourToken: colourToken.rawValue,
            sortOrder: existingCount
        )
        project.dueDate = hasDueDate ? dueDate : nil
        context.insert(project)
        try? context.save()
        onFinished()
    }
}
