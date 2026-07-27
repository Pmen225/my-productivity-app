import SwiftData
import SwiftUI

/// Global search across tasks, projects, map nodes, notes and conversations.
///
/// Opened with ⌘K on the Mac and from the Library on iPhone. Selecting a result
/// navigates straight to it.
struct GlobalSearchView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFieldFocused: Bool

    let onSelect: (SearchResult) -> Void

    var body: some View {
        VStack(spacing: 0) {
            field
            Divider().overlay(FlowTheme.separator(scheme))
            resultList
        }
        .frame(minWidth: 420, minHeight: 360)
        .background(FlowTheme.background(scheme))
        .onAppear { isFieldFocused = true }
        .onDisappear { searchTask?.cancel() }
    }

    private var field: some View {
        HStack(spacing: FlowSpacing.m) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FlowTheme.secondaryText(scheme))
            TextField("Search tasks, projects, ideas, notes", text: $query)
                .textFieldStyle(.plain)
                .font(FlowFont.body)
                .focused($isFieldFocused)
                .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(FlowSpacing.l)
    }

    @ViewBuilder
    private var resultList: some View {
        if query.trimmingCharacters(in: .whitespaces).count < 2 {
            FlowEmptyState(
                symbol: "magnifyingglass",
                title: "Search everything",
                message: "Type at least two letters to search across your tasks, projects, ideas, notes and conversations."
            )
            .frame(maxHeight: .infinity)
        } else if results.isEmpty {
            FlowEmptyState(
                symbol: "questionmark.circle",
                title: "No matches",
                message: "Nothing matched “\(query)”."
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { result in
                        Button {
                            onSelect(result)
                            dismiss()
                        } label: {
                            row(result)
                        }
                        .buttonStyle(.plain)
                        Divider()
                            .overlay(FlowTheme.separator(scheme))
                            .padding(.leading, 52)
                    }
                }
            }
        }
    }

    private func row(_ result: SearchResult) -> some View {
        HStack(spacing: FlowSpacing.m) {
            Image(systemName: result.kind.symbolName)
                .font(.system(size: 13))
                .foregroundStyle(FlowTheme.accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(FlowTheme.accent.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(FlowFont.body)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                    .lineLimit(1)
                Text("\(result.kind.displayName) · \(result.context)")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .lineLimit(1)
                if result.matchedText != result.title {
                    Text(result.matchedText)
                        .font(FlowFont.caption)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, FlowSpacing.l)
        .padding(.vertical, FlowSpacing.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.kind.displayName): \(result.title), in \(result.context)")
    }

    /// Debounced so a long query does not re-run the search on every keystroke.
    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        guard let service = flow?.searchService else { return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let found = service.search(text)
            guard !Task.isCancelled else { return }
            results = found
        }
    }
}
