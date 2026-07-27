import Foundation
import SwiftData

/// One turn in an assistant thread. Tool calls and their results are persisted
/// alongside the prose so the audit trail survives relaunch and sync.
@Model
public final class AssistantMessage {
    public var id: UUID = UUID()
    public var roleRaw: String = AssistantRole.user.rawValue
    public var text: String = ""
    /// JSON describing a proposed tool call, when this message is a proposal.
    public var toolProposalJSON: String?
    /// JSON describing the executed result, written only after the tool ran.
    public var toolResultJSON: String?
    public var toolName: String?
    /// Set once the user has approved a proposal that needed confirmation.
    public var isApplied: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var thread: AssistantThread?

    public var role: AssistantRole {
        get { AssistantRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue; touch() }
    }

    public init(
        role: AssistantRole,
        text: String,
        thread: AssistantThread? = nil,
        toolName: String? = nil,
        toolProposalJSON: String? = nil,
        toolResultJSON: String? = nil
    ) {
        self.id = UUID()
        self.roleRaw = role.rawValue
        self.text = text
        self.thread = thread
        self.toolName = toolName
        self.toolProposalJSON = toolProposalJSON
        self.toolResultJSON = toolResultJSON
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func touch(_ date: Date = Date()) { updatedAt = date }

    /// A proposal awaiting the user's confirmation.
    public var isPendingProposal: Bool {
        toolProposalJSON != nil && toolResultJSON == nil && !isApplied
    }
}
