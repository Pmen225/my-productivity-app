import Foundation
import SwiftData

/// One block inside a note.
@Model
public final class NoteBlock {
    public var id: UUID = UUID()
    public var typeRaw: String = NoteBlockType.paragraph.rawValue
    public var text: String = ""
    public var isChecked: Bool = false
    public var sortOrder: Int = 0
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var note: Note?

    public var type: NoteBlockType {
        get { NoteBlockType(rawValue: typeRaw) ?? .paragraph }
        set { typeRaw = newValue.rawValue; touch() }
    }

    public init(
        type: NoteBlockType = .paragraph,
        text: String = "",
        isChecked: Bool = false,
        sortOrder: Int = 0,
        note: Note? = nil
    ) {
        self.id = UUID()
        self.typeRaw = type.rawValue
        self.text = text
        self.isChecked = isChecked
        self.sortOrder = sortOrder
        self.note = note
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func touch(_ date: Date = Date()) { updatedAt = date }
}
