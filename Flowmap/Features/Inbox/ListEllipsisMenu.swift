import SwiftUI

/// Native list actions attached directly to the toolbar ellipsis.
///
/// A compact iPhone cannot present a useful anchored popover: SwiftUI adapts
/// it to a sheet, which leaves the custom dark panel detached from the list
/// that opened it. `Menu` keeps the same actions anchored to the control on
/// iPhone and remains a natural menu on macOS.
public struct ListEllipsisMenu: View {
    @Environment(\.colorScheme) private var scheme

    private let currentGrouping: GroupingMode
    private let onSelectGrouping: (GroupingMode) -> Void
    private let onCreateList: () -> Void
    private let onEditLists: () -> Void

    public init(
        currentGrouping: GroupingMode,
        onSelectGrouping: @escaping (GroupingMode) -> Void,
        onCreateList: @escaping () -> Void,
        onEditLists: @escaping () -> Void
    ) {
        self.currentGrouping = currentGrouping
        self.onSelectGrouping = onSelectGrouping
        self.onCreateList = onCreateList
        self.onEditLists = onEditLists
    }

    public var body: some View {
        Menu {
            Button(action: onCreateList) {
                Label("Create new list", systemImage: "plus")
            }
            Button(action: onEditLists) {
                Label("Edit lists", systemImage: "pencil")
            }
            Divider()
            Menu {
                groupingChoice(.priority)
                groupingChoice(.manual)
            } label: {
                Label("Grouping options", systemImage: "arrow.up.arrow.down")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(FlowTheme.primaryText(scheme))
        }
        .accessibilityLabel("List options")
    }

    @ViewBuilder
    private func groupingChoice(_ mode: GroupingMode) -> some View {
        Button {
            onSelectGrouping(mode)
        } label: {
            if mode == currentGrouping {
                Label(mode.displayName, systemImage: "checkmark")
            } else {
                Text(mode.displayName)
            }
        }
    }
}
