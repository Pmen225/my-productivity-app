import SwiftData
import SwiftUI

/// Sheet reached from the ellipsis menu's `Create new list` row.
public struct CreateListSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let workspace: Workspace?
    @State private var name = ""
    @State private var iconName = FlowSymbols.listSymbols[0]
    @State private var colourToken: ColourToken = .blue

    public init(workspace: Workspace? = nil) {
        self.workspace = workspace
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("List name", text: $name)
                } header: {
                    FlowEyebrow("Name")
                }
                Section {
                    iconPicker
                } header: {
                    FlowEyebrow("Icon")
                }
                Section {
                    colourPicker
                } header: {
                    FlowEyebrow("Colour")
                }
            }
            .navigationTitle("New List")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createList() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationCornerRadius(FlowRadius.large)
    }

    private var iconPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FlowSpacing.s) {
                ForEach(FlowSymbols.listSymbols, id: \.self) { symbol in
                    Button {
                        iconName = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 40, height: 40)
                            .background(
                                Circle().fill(symbol == iconName ? colourToken.soft : Color.clear)
                            )
                            .foregroundStyle(symbol == iconName ? colourToken.onSoft : .primary)
                    }
                    .buttonStyle(FlowNavigationRowPressStyle())
                    .accessibilityLabel(symbol)
                }
            }
            .padding(.vertical, FlowSpacing.xs)
        }
    }

    private var colourPicker: some View {
        FlowColourPicker(selection: $colourToken, diameter: 28, scrollable: true)
    }

    private func createList() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let existingCount = (try? context.fetchCount(FetchDescriptor<TaskList>())) ?? 0
        let list = TaskList(
            name: trimmed,
            iconName: iconName,
            colourToken: colourToken.rawValue,
            sortOrder: existingCount,
            workspace: workspace
        )
        context.insert(list)
        try? context.save()
        dismiss()
    }
}
