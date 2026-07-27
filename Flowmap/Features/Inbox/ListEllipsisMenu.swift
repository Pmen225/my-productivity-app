import SwiftUI

/// The dark floating popover behind the top `…` button on every to-do/list
/// screen. It must never route to Settings — `Create new list`, `Edit lists`
/// and `Grouping options` are the only destinations, and `Grouping options`
/// expands in place rather than pushing a new sheet.
public struct ListEllipsisMenu: View {
    @Binding private var isPresented: Bool
    private let currentGrouping: GroupingMode
    private let onSelectGrouping: (GroupingMode) -> Void
    private let onCreateList: () -> Void
    private let onEditLists: () -> Void

    @State private var groupingExpanded = false

    public init(
        isPresented: Binding<Bool>,
        currentGrouping: GroupingMode,
        onSelectGrouping: @escaping (GroupingMode) -> Void,
        onCreateList: @escaping () -> Void,
        onEditLists: @escaping () -> Void
    ) {
        self._isPresented = isPresented
        self.currentGrouping = currentGrouping
        self.onSelectGrouping = onSelectGrouping
        self.onCreateList = onCreateList
        self.onEditLists = onEditLists
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(title: "Create new list", systemImage: "plus") {
                isPresented = false
                onCreateList()
            }
            divider
            row(title: "Edit lists", systemImage: "pencil") {
                isPresented = false
                onEditLists()
            }
            divider
            groupingDisclosure
        }
        .padding(.vertical, FlowSpacing.xs)
        .frame(width: 240)
        .background(FlowTheme.popoverSurface)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Grouping options (expands in the same popover)

    private var groupingDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { groupingExpanded.toggle() }
            } label: {
                HStack(spacing: FlowSpacing.s) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 20)
                    Text("Grouping options")
                        .font(FlowFont.body)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(groupingExpanded ? 90 : 0))
                }
                .padding(.horizontal, FlowSpacing.m)
                .padding(.vertical, FlowSpacing.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel("Grouping options")
            .accessibilityHint(groupingExpanded ? "Collapse" : "Expand")

            if groupingExpanded {
                groupingChoice(.priority)
                groupingChoice(.manual)
            }
        }
    }

    private func groupingChoice(_ mode: GroupingMode) -> some View {
        Button {
            onSelectGrouping(mode)
            isPresented = false
        } label: {
            HStack(spacing: FlowSpacing.s) {
                Image(systemName: mode == currentGrouping ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(mode == currentGrouping ? FlowTheme.accent : .white.opacity(0.5))
                Text(mode.displayName)
                    .font(FlowFont.secondary)
                Spacer()
            }
            .padding(.leading, FlowSpacing.l)
            .padding(.trailing, FlowSpacing.m)
            .padding(.vertical, FlowSpacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(mode.displayName)
        .accessibilityAddTraits(mode == currentGrouping ? .isSelected : [])
    }

    private func row(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: FlowSpacing.s) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                Text(title)
                    .font(FlowFont.body)
                Spacer()
            }
            .padding(.horizontal, FlowSpacing.m)
            .padding(.vertical, FlowSpacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, FlowSpacing.s)
    }
}
