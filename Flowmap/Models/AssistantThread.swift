import Foundation
import SwiftData

/// One assistant conversation. History syncs so a thread started on the phone
/// continues on the Mac.
@Model
public final class AssistantThread {
    public var id: UUID = UUID()
    public var title: String = "New conversation"
    public var isArchived: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \AssistantMessage.thread)
    public var messages: [AssistantMessage]?

    public init(title: String = "New conversation") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func touch(_ date: Date = Date()) { updatedAt = date }

    public var orderedMessages: [AssistantMessage] {
        (messages ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    /// Messages shown in the transcript. Tool traffic is folded into audit rows.
    public var visibleMessages: [AssistantMessage] {
        orderedMessages.filter { $0.role != .system }
    }

    public var lastMessagePreview: String {
        orderedMessages.last(where: { $0.role == .user || $0.role == .assistant })?.text ?? ""
    }
}
