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
                Section("Name") {
                    TextField("List name", text: $name)
                }
                Section("Icon") {
                    iconPicker
                }
                Section("Colour") {
                    colourPicker
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
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol)
                }
            }
            .padding(.vertical, FlowSpacing.xs)
        }
    }

    private var colourPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FlowSpacing.s) {
                ForEach(ColourToken.allCases, id: \.self) { token in
                    Button {
                        colourToken = token
                    } label: {
                        Circle()
                            .fill(token.base)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle().strokeBorder(.primary, lineWidth: token == colourToken ? 2 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(token.displayName)
                }
            }
            .padding(.vertical, FlowSpacing.xs)
        }
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
