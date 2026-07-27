import Foundation
import SwiftData

/// A checklist item inside a task.
@Model
public final class Subtask {
    public var id: UUID = UUID()
    public var title: String = ""
    public var isCompleted: Bool = false
    public var sortOrder: Int = 0
    public var estimatedMinutes: Int?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var task: FlowTask?

    public init(
        title: String,
        isCompleted: Bool = false,
        sortOrder: Int = 0,
        estimatedMinutes: Int? = nil,
        task: FlowTask? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.estimatedMinutes = estimatedMinutes
        self.task = task
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func touch(_ date: Date = Date()) { updatedAt = date }

    public func toggle() {
        isCompleted.toggle()
        touch()
    }
}
