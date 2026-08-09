import Foundation
import SwiftData

/// One hit from global search.
public struct SearchResult: Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case task
        case project
        case note
        case assistantThread

        public var displayName: String {
            switch self {
            case .task: "Task"
            case .project: "Project"
            case .note: "Note"
            case .assistantThread: "Conversation"
            }
        }

        public var symbolName: String {
            switch self {
            case .task: "checkmark.circle"
            case .project: "folder"
            case .note: "doc.text"
            case .assistantThread: "sparkles"
            }
        }
    }

    public let id: UUID
    public let kind: Kind
    public let title: String
    /// Where this lives — list name, project title.
    public let context: String
    /// The line the query actually matched.
    public let matchedText: String

    public init(id: UUID, kind: Kind, title: String, context: String, matchedText: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.context = context
        self.matchedText = matchedText
    }
}

/// Global search across tasks, projects, notes and conversations.
@MainActor
public struct SearchService {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Case- and diacritic-insensitive substring search.
    ///
    /// Fetches are done per type and filtered in memory: the data set is personal
    /// scale, and this keeps ranking logic in one readable place.
    public func search(_ rawQuery: String, limit: Int = 40) -> [SearchResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }

        var results: [SearchResult] = []

        for task in fetch(FlowTask.self) {
            if let matched = firstMatch(query, in: [task.title, task.details]) {
                results.append(
                    SearchResult(
                        id: task.id,
                        kind: .task,
                        title: task.title,
                        context: task.project?.title ?? task.list?.name ?? task.status.displayName,
                        matchedText: matched
                    )
                )
            }
        }

        for project in fetch(Project.self) {
            if let matched = firstMatch(query, in: [project.title, project.summary]) {
                results.append(
                    SearchResult(
                        id: project.id,
                        kind: .project,
                        title: project.title,
                        context: project.workspace?.name ?? project.status.displayName,
                        matchedText: matched
                    )
                )
            }
        }

        for note in fetch(Note.self) where !note.isTrashed {
            if let matched = firstMatch(query, in: [note.title] + note.orderedBlocks.map(\.text)) {
                results.append(
                    SearchResult(
                        id: note.id,
                        kind: .note,
                        title: note.title,
                        context: note.project?.title ?? note.workspace?.name ?? "Notes",
                        matchedText: matched
                    )
                )
            }
        }

        for thread in fetch(AssistantThread.self) where !thread.isArchived {
            if let matched = firstMatch(query, in: [thread.title] + thread.orderedMessages.map(\.text)) {
                results.append(
                    SearchResult(
                        id: thread.id,
                        kind: .assistantThread,
                        title: thread.title,
                        context: "Assistant",
                        matchedText: matched
                    )
                )
            }
        }

        // A title hit beats a body hit; a prefix hit beats a mid-string hit.
        return results
            .sorted { lhs, rhs in
                let lhsScore = score(lhs, query: query)
                let rhsScore = score(rhs, query: query)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    private func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    private func firstMatch(_ query: String, in candidates: [String]) -> String? {
        candidates.first { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    private func score(_ result: SearchResult, query: String) -> Int {
        var score = 0
        if result.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            score += 10
            if result.title.lowercased().hasPrefix(query.lowercased()) { score += 5 }
        }
        if result.kind == .task { score += 2 }
        return score
    }
}
