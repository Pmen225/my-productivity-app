import Foundation
import SwiftData

/// A block-based note.
@Model
public final class Note {
    public var id: UUID = UUID()
    public var title: String = ""
    public var iconName: String = "doc.text"
    public var colourToken: String = ColourToken.blue.rawValue
    public var isFavourite: Bool = false
    public var isArchived: Bool = false
    public var isTrashed: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var workspace: Workspace?
    public var project: Project?
    public var task: FlowTask?
    public var mapNode: MapNode?

    @Relationship(deleteRule: .cascade, inverse: \NoteBlock.note)
    public var blocks: [NoteBlock]?

    public init(
        title: String,
        iconName: String = "doc.text",
        workspace: Workspace? = nil,
        project: Project? = nil,
        task: FlowTask? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.iconName = iconName
        self.workspace = workspace
        self.project = project
        self.task = task
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func touch(_ date: Date = Date()) { updatedAt = date }

    public var colour: ColourToken { ColourToken.token(colourToken) }

    public var orderedBlocks: [NoteBlock] {
        (blocks ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// First non-empty line of body text, for list rows.
    public var preview: String {
        orderedBlocks
            .first { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .text ?? ""
    }

    /// Everything searchable in one string.
    public var searchableText: String {
        ([title] + orderedBlocks.map(\.text)).joined(separator: "\n")
    }

    public func markdown() -> String {
        var lines: [String] = ["# \(title)", ""]
        var numberedIndex = 1
        for block in orderedBlocks {
            switch block.type {
            case .divider:
                lines.append("---")
            case .numbered:
                lines.append("\(numberedIndex). \(block.text)")
                numberedIndex += 1
                continue
            case .checklist:
                lines.append("- [\(block.isChecked ? "x" : " ")] \(block.text)")
            default:
                lines.append(block.type.markdownPrefix + block.text)
            }
            numberedIndex = 1
        }
        return lines.joined(separator: "\n")
    }
}
