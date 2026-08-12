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
    private let filterPriority: TaskPriority?
    private let onSelectFilter: (TaskPriority?) -> Void

    public init(
        currentGrouping: GroupingMode,
        onSelectGrouping: @escaping (GroupingMode) -> Void,
        onCreateList: @escaping () -> Void,
        onEditLists: @escaping () -> Void,
        filterPriority: TaskPriority?,
        onSelectFilter: @escaping (TaskPriority?) -> Void
    ) {
        self.currentGrouping = currentGrouping
        self.onSelectGrouping = onSelectGrouping
        self.onCreateList = onCreateList
        self.onEditLists = onEditLists
        self.filterPriority = filterPriority
        self.onSelectFilter = onSelectFilter
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
            // Founder ruling 2026-08-10: the separate filter button next to
            // this menu read as clutter — one toolbar button, filter folded in.
            Menu {
                Button {
                    onSelectFilter(nil)
                } label: {
                    Label("All priorities", systemImage: filterPriority == nil ? "checkmark" : "line.3.horizontal.decrease")
                }
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    Button {
                        onSelectFilter(priority)
                    } label: {
                        Label(priority.displayName, systemImage: filterPriority == priority ? "checkmark" : priority.symbolName)
                    }
                }
            } label: {
                Label("Filter by priority", systemImage: "line.3.horizontal.decrease")
            }
            Menu {
                groupingChoice(.priority)
                groupingChoice(.manual)
            } label: {
                Label("Grouping options", systemImage: "arrow.up.arrow.down")
            }
        } label: {
            // The filled variant restates an active filter on screen — the
            // old standalone button's signal survives the merge.
            Image(systemName: filterPriority == nil ? "ellipsis.circle" : "ellipsis.circle.fill")
                .foregroundStyle(FlowTheme.primaryText(scheme))
        }
        .accessibilityLabel("List options")
        .accessibilityValue(filterPriority.map { "Filtered to \($0.displayName)" } ?? "")
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
