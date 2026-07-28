import Foundation
import SwiftData

/// JSON backup and restore.
///
/// Restore is a *merge*, keyed on each record's stable UUID: importing the same
/// file twice changes nothing the second time, and importing an older file never
/// overwrites newer local edits.
public enum BackupService {
    public static let formatVersion = 1

    // MARK: - Transfer types

    public struct Archive: Codable, Sendable {
        public var formatVersion: Int
        public var exportedAt: Date
        public var workspaces: [WorkspaceDTO]
        public var lists: [TaskListDTO]
        public var projects: [ProjectDTO]
        public var tasks: [TaskDTO]
        public var segments: [SegmentDTO]
        public var subtasks: [SubtaskDTO]
        public var notes: [NoteDTO]
        public var noteBlocks: [NoteBlockDTO]
        public var maps: [MapDTO]
        public var mapNodes: [MapNodeDTO]
    }

    public struct WorkspaceDTO: Codable, Sendable {
        public var id: UUID, name: String, iconName: String, colourToken: String
        public var sortOrder: Int, isArchived: Bool, updatedAt: Date
    }

    public struct TaskListDTO: Codable, Sendable {
        public var id: UUID, name: String, iconName: String, colourToken: String
        public var sortOrder: Int, groupingModeRaw: String, isArchived: Bool
        public var workspaceID: UUID?, updatedAt: Date
    }

    public struct ProjectDTO: Codable, Sendable {
        public var id: UUID, title: String, summary: String, statusRaw: String
        public var priorityRaw: String, startDate: Date?, dueDate: Date?
        public var colourToken: String, iconName: String, sortOrder: Int
        public var workspaceID: UUID?, updatedAt: Date
    }

    public struct TaskDTO: Codable, Sendable {
        public var id: UUID, title: String, details: String, statusRaw: String
        public var priorityRaw: String, estimatedMinutes: Int, actualMinutes: Int
        public var dueDate: Date?, earliestStart: Date?, latestFinish: Date?
        public var preferredPeriodRaw: String, isLockedInSchedule: Bool
        public var isSplittable: Bool, minimumChunkMinutes: Int, sortOrder: Int
        public var colourToken: String, iconName: String, recurrenceFrequencyRaw: String
        public var isFlaggedForToday: Bool, completedAt: Date?
        public var carryoverCount: Int, lastCarriedAt: Date?
        public var listID: UUID?, projectID: UUID?, workspaceID: UUID?
        public var createdAt: Date, updatedAt: Date
    }

    public struct SegmentDTO: Codable, Sendable {
        public var id: UUID, taskID: UUID?, startDate: Date, endDate: Date
        public var stateRaw: String, isLocked: Bool, sequenceIndex: Int
        public var sourceRaw: String, continuationOfSegmentID: UUID?, updatedAt: Date
    }

    public struct SubtaskDTO: Codable, Sendable {
        public var id: UUID, taskID: UUID?, title: String, isCompleted: Bool
        public var sortOrder: Int, estimatedMinutes: Int?, updatedAt: Date
    }

    public struct NoteDTO: Codable, Sendable {
        public var id: UUID, title: String, iconName: String, isFavourite: Bool
        public var isArchived: Bool, isTrashed: Bool
        public var workspaceID: UUID?, projectID: UUID?, taskID: UUID?, updatedAt: Date
    }

    public struct NoteBlockDTO: Codable, Sendable {
        public var id: UUID, noteID: UUID?, typeRaw: String, text: String
        public var isChecked: Bool, sortOrder: Int, updatedAt: Date
    }

    public struct MapDTO: Codable, Sendable {
        public var id: UUID, title: String, summary: String, themeToken: String
        public var canvasOffsetX: Double, canvasOffsetY: Double, canvasZoom: Double
        public var workspaceID: UUID?, projectID: UUID?, updatedAt: Date
    }

    public struct MapNodeDTO: Codable, Sendable {
        public var id: UUID, mapID: UUID?, parentID: UUID?, title: String, body: String
        public var iconName: String, colourToken: String, sortOrder: Int
        public var isCollapsed: Bool, isTask: Bool, priorityRaw: String
        public var estimatedMinutes: Int, linkedTaskID: UUID?, updatedAt: Date
    }

    // MARK: - Errors

    public enum ImportError: Error, LocalizedError {
        case notJSON
        case unsupportedVersion(Int)
        case corrupt(String)

        public var errorDescription: String? {
            switch self {
            case .notJSON:
                "That file isn't a Flowmap backup."
            case .unsupportedVersion(let version):
                "That backup was made by a newer version of Flowmap (format \(version))."
            case .corrupt(let detail):
                "That backup could not be read: \(detail)"
            }
        }
    }

    /// What a restore actually did, so the UI can report it truthfully.
    public struct ImportSummary: Sendable {
        public var created: Int = 0
        public var updated: Int = 0
        public var skipped: Int = 0

        public var description: String {
            "\(created) added, \(updated) updated, \(skipped) already up to date"
        }
    }

    // MARK: - Export

    @MainActor
    public static func export(from context: ModelContext) throws -> Data {
        func all<T: PersistentModel>(_ type: T.Type) -> [T] {
            (try? context.fetch(FetchDescriptor<T>())) ?? []
        }

        let archive = Archive(
            formatVersion: formatVersion,
            exportedAt: Date(),
            workspaces: all(Workspace.self).map {
                WorkspaceDTO(
                    id: $0.id, name: $0.name, iconName: $0.iconName,
                    colourToken: $0.colourToken, sortOrder: $0.sortOrder,
                    isArchived: $0.isArchived, updatedAt: $0.updatedAt
                )
            },
            lists: all(TaskList.self).map {
                TaskListDTO(
                    id: $0.id, name: $0.name, iconName: $0.iconName,
                    colourToken: $0.colourToken, sortOrder: $0.sortOrder,
                    groupingModeRaw: $0.groupingModeRaw, isArchived: $0.isArchived,
                    workspaceID: $0.workspace?.id, updatedAt: $0.updatedAt
                )
            },
            projects: all(Project.self).map {
                ProjectDTO(
                    id: $0.id, title: $0.title, summary: $0.summary,
                    statusRaw: $0.statusRaw, priorityRaw: $0.priorityRaw,
                    startDate: $0.startDate, dueDate: $0.dueDate,
                    colourToken: $0.colourToken, iconName: $0.iconName,
                    sortOrder: $0.sortOrder, workspaceID: $0.workspace?.id,
                    updatedAt: $0.updatedAt
                )
            },
            tasks: all(FlowTask.self).map {
                TaskDTO(
                    id: $0.id, title: $0.title, details: $0.details,
                    statusRaw: $0.statusRaw, priorityRaw: $0.priorityRaw,
                    estimatedMinutes: $0.estimatedMinutes, actualMinutes: $0.actualMinutes,
                    dueDate: $0.dueDate, earliestStart: $0.earliestStart,
                    latestFinish: $0.latestFinish, preferredPeriodRaw: $0.preferredPeriodRaw,
                    isLockedInSchedule: $0.isLockedInSchedule, isSplittable: $0.isSplittable,
                    minimumChunkMinutes: $0.minimumChunkMinutes, sortOrder: $0.sortOrder,
                    colourToken: $0.colourToken, iconName: $0.iconName,
                    recurrenceFrequencyRaw: $0.recurrenceFrequencyRaw,
                    isFlaggedForToday: $0.isFlaggedForToday, completedAt: $0.completedAt,
                    carryoverCount: $0.carryoverCount, lastCarriedAt: $0.lastCarriedAt,
                    listID: $0.list?.id, projectID: $0.project?.id,
                    workspaceID: $0.workspace?.id, createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            },
            segments: all(TaskSegment.self).map {
                SegmentDTO(
                    id: $0.id, taskID: $0.task?.id, startDate: $0.startDate,
                    endDate: $0.endDate, stateRaw: $0.stateRaw, isLocked: $0.isLocked,
                    sequenceIndex: $0.sequenceIndex, sourceRaw: $0.sourceRaw,
                    continuationOfSegmentID: $0.continuationOfSegmentID, updatedAt: $0.updatedAt
                )
            },
            subtasks: all(Subtask.self).map {
                SubtaskDTO(
                    id: $0.id, taskID: $0.task?.id, title: $0.title,
                    isCompleted: $0.isCompleted, sortOrder: $0.sortOrder,
                    estimatedMinutes: $0.estimatedMinutes, updatedAt: $0.updatedAt
                )
            },
            notes: all(Note.self).map {
                NoteDTO(
                    id: $0.id, title: $0.title, iconName: $0.iconName,
                    isFavourite: $0.isFavourite, isArchived: $0.isArchived,
                    isTrashed: $0.isTrashed, workspaceID: $0.workspace?.id,
                    projectID: $0.project?.id, taskID: $0.task?.id, updatedAt: $0.updatedAt
                )
            },
            noteBlocks: all(NoteBlock.self).map {
                NoteBlockDTO(
                    id: $0.id, noteID: $0.note?.id, typeRaw: $0.typeRaw, text: $0.text,
                    isChecked: $0.isChecked, sortOrder: $0.sortOrder, updatedAt: $0.updatedAt
                )
            },
            maps: all(MapDocument.self).map {
                MapDTO(
                    id: $0.id, title: $0.title, summary: $0.summary,
                    themeToken: $0.themeToken, canvasOffsetX: $0.canvasOffsetX,
                    canvasOffsetY: $0.canvasOffsetY, canvasZoom: $0.canvasZoom,
                    workspaceID: $0.workspace?.id, projectID: $0.project?.id,
                    updatedAt: $0.updatedAt
                )
            },
            mapNodes: all(MapNode.self).map {
                MapNodeDTO(
                    id: $0.id, mapID: $0.map?.id, parentID: $0.parent?.id,
                    title: $0.title, body: $0.body, iconName: $0.iconName,
                    colourToken: $0.colourToken, sortOrder: $0.sortOrder,
                    isCollapsed: $0.isCollapsed, isTask: $0.isTask,
                    priorityRaw: $0.priorityRaw, estimatedMinutes: $0.estimatedMinutes,
                    linkedTaskID: $0.linkedTask?.id, updatedAt: $0.updatedAt
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    /// Every note in the store as Markdown files, keyed by suggested filename.
    @MainActor
    public static func exportNotesAsMarkdown(from context: ModelContext) -> [String: String] {
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        var files: [String: String] = [:]
        for note in notes where !note.isTrashed {
            let safeTitle = note.title
                .replacingOccurrences(of: "/", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let base = safeTitle.isEmpty ? "Untitled" : safeTitle
            // Filenames can collide even when note titles are unique-looking.
            var filename = "\(base).md"
            var counter = 2
            while files[filename] != nil {
                filename = "\(base) \(counter).md"
                counter += 1
            }
            files[filename] = note.markdown()
        }
        return files
    }

    /// True when making `parent` the parent of `child` would close a loop.
    @MainActor
    private static func wouldCreateCycle(child: MapNode, parent: MapNode) -> Bool {
        if parent.id == child.id { return true }
        var cursor: MapNode? = parent
        var hops = 0
        while let node = cursor {
            if node.id == child.id { return true }
            cursor = node.parent
            hops += 1
            if hops > 256 { return true } // already cyclic
        }
        return false
    }

    // MARK: - Validate and import

    public static func validate(_ data: Data) throws -> Archive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive: Archive
        do {
            archive = try decoder.decode(Archive.self, from: data)
        } catch let error as DecodingError {
            throw ImportError.corrupt(Self.describe(error))
        } catch {
            throw ImportError.notJSON
        }
        guard archive.formatVersion <= formatVersion else {
            throw ImportError.unsupportedVersion(archive.formatVersion)
        }
        return archive
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _): "a required field (\(key.stringValue)) is missing"
        case .typeMismatch(_, let ctx): "a field has the wrong type at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(_, let ctx): "a value is missing at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let ctx): ctx.debugDescription
        @unknown default: "the file is not in the expected shape"
        }
    }

    /// Merges an archive into the store.
    ///
    /// Duplicate-safe: records are matched by UUID, and an incoming record is
    /// only written when it is newer than what is already here.
    @MainActor
    @discardableResult
    public static func importArchive(_ archive: Archive, into context: ModelContext) throws -> ImportSummary {
        var summary = ImportSummary()

        func index<T: PersistentModel>(_ type: T.Type, id: (T) -> UUID) -> [UUID: T] {
            let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
            return Dictionary(all.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })
        }

        var workspaces = index(Workspace.self) { $0.id }
        var lists = index(TaskList.self) { $0.id }
        var projects = index(Project.self) { $0.id }
        var tasks = index(FlowTask.self) { $0.id }
        var notes = index(Note.self) { $0.id }
        var maps = index(MapDocument.self) { $0.id }
        var mapNodes = index(MapNode.self) { $0.id }
        let segments = index(TaskSegment.self) { $0.id }
        let subtasks = index(Subtask.self) { $0.id }
        let noteBlocks = index(NoteBlock.self) { $0.id }

        /// Writes `apply` only when the incoming record is newer.
        func merge<T: PersistentModel>(
            existing: T?,
            incomingDate: Date,
            currentDate: (T) -> Date,
            apply: (T) -> Void,
            create: () -> T
        ) -> Bool {
            if let existing {
                guard incomingDate > currentDate(existing) else {
                    summary.skipped += 1
                    return false
                }
                apply(existing)
                summary.updated += 1
                return true
            }
            let created = create()
            context.insert(created)
            apply(created)
            summary.created += 1
            return true
        }

        for dto in archive.workspaces {
            _ = merge(
                existing: workspaces[dto.id], incomingDate: dto.updatedAt,
                currentDate: { $0.updatedAt },
                apply: { model in
                    model.id = dto.id; model.name = dto.name; model.iconName = dto.iconName
                    model.colourToken = dto.colourToken; model.sortOrder = dto.sortOrder
                    model.isArchived = dto.isArchived; model.updatedAt = dto.updatedAt
                    workspaces[dto.id] = model
                },
                create: { Workspace(name: dto.name) }
            )
        }

        for dto in archive.lists {
            _ = merge(
                existing: lists[dto.id], incomingDate: dto.updatedAt,
                currentDate: { $0.updatedAt },
                apply: { model in
                    model.id = dto.id; model.name = dto.name; model.iconName = dto.iconName
                    model.colourToken = dto.colourToken; model.sortOrder = dto.sortOrder
                    model.groupingModeRaw = dto.groupingModeRaw; model.isArchived = dto.isArchived
                    model.workspace = dto.workspaceID.flatMap { workspaces[$0] }
                    model.updatedAt = dto.updatedAt
                    lists[dto.id] = model
                },
                create: { TaskList(name: dto.name) }
            )
        }

        for dto in archive.projects {
            _ = merge(
                existing: projects[dto.id], incomingDate: dto.updatedAt,
                currentDate: { $0.updatedAt },
                apply: { model in
                    model.id = dto.id; model.title = dto.title; model.summary = dto.summary
                    model.statusRaw = dto.statusRaw; model.priorityRaw = dto.priorityRaw
                    model.startDate = dto.startDate; model.dueDate = dto.dueDate
                    model.colourToken = dto.colourToken; model.iconName = dto.iconName
                    model.sortOrder = dto.sortOrder
                    model.workspace = dto.workspaceID.flatMap { workspaces[$0] }
                    model.updatedAt = dto.updatedAt
                    projects[dto.id] = model
                },
                create: { Project(title: dto.title) }
            )
        }

        for dto in archive.tasks {
            _ = merge(
                existing: tasks[dto.id], incomingDate: dto.updatedAt,
                currentDate: { $0.updatedAt },
                apply: { model in
                    model.id = dto.id; model.title = dto.title; model.details = dto.details
                    model.statusRaw = dto.statusRaw; model.priorityRaw = dto.priorityRaw
                    model.estimatedMinutes = dto.estimatedMinutes
                    model.actualMinutes = dto.actualMinutes
                    model.dueDate = dto.dueDate; model.earliestStart = dto.earliestStart
                    model.latestFinish = dto.latestFinish
                    model.preferredPeriodRaw = dto.preferredPeriodRaw
                    model.isLockedInSchedule = dto.isLockedInSchedule
                    model.isSplittable = dto.isSplittable
                    model.minimumChunkMinutes = dto.minimumChunkMinutes
                    model.sortOrder = dto.sortOrder; model.colourToken = dto.colourToken
                    model.iconName = dto.iconName
                    model.recurrenceFrequencyRaw = dto.recurrenceFrequencyRaw
                    model.isFlaggedForToday = dto.isFlaggedForToday
                    model.completedAt = dto.completedAt
                    model.carryoverCount = dto.carryoverCount
                    model.lastCarriedAt = dto.lastCarriedAt
                    model.list = dto.listID.flatMap { lists[$0] }
                    model.project = dto.projectID.flatMap { projects[$0] }
                    model.workspace = dto.workspaceID.flatMap { workspaces[$0] }
                    model.createdAt = dto.createdAt; model.updatedAt = dto.updatedAt
                    tasks[dto.id] = model
                },
                create: { FlowTask(title: dto.title) }
            )
        }

        for dto in archive.segments {
            _ = merge(
                existing: segments[dto.id], incomingDate: dto.updatedAt,
                currentDate: { $0.updatedAt },
                apply: { model in
                    model.id = dto.id
                    model.task = dto.taskID.flatMap { tasks[$0] }
                    model.startDate = dto.startDate; model.endDate = dto.endDate
                    model.stateRaw = dto.stateRaw; model.isLocked = dto.isLocked
                    model.sequenceIndex = dto.sequenceIndex; model.sourceRaw = dto.sourceRaw
                    model.continuationOfSegmentID = dto.continuationOfSegmentID
                    model.updatedAt = dto.updatedAt
                },
                create: {
                    TaskSegment(
                        task: dto.taskID.flatMap { tasks[$0] },
                        startDate: dto.startDate, endDate: dto.endDate
                    )
                }
            )
        }

        for dto in archive.subtasks {
            _ = merge(
                existing: subtasks[dto.id], incomingDate: dto.updatedAt,
                currentDate: { $0.updatedAt },
                apply: { model in
                    model.id = dto.id; model.title = dto.title
                    model.isCompleted = dto.isCompleted; model.sortOrder = dto.sortOrder
                    model.estimatedMinutes = dto.estimatedMinutes
                    model.task = dto.taskID.flatMap { tasks[$0] }
                    model.updatedAt = dto.updatedAt
                },
                create: { Subtask(title: dto.title) }
            )
        }

        for dto in archive.maps {
            _ = merge(
                existing: maps[dto.id], incomingDate: dto.updatedAt,
                currentDate: { $0.updatedAt },
                apply: { model in
                    model.id = dto.id; model.title = dto.title; model.summary = dto.summary
                    model.themeToken = dto.themeToken
                    model.canvasOffsetX = dto.canvasOffsetX
                    model.canvasOffsetY = dto.canvasOffsetY
                    model.canvasZoom = dto.canvasZoom
                    model.workspace = dto.workspaceID.flatMap { workspaces[$0] }
                    model.project = dto.projectID.flatMap { projects[$0] }
                    model.updatedAt = dto.updatedAt
                    maps[dto.id] = model
                },
                create: { MapDocument(title: dto.title) }
            )
        }

        // Nodes are merged before parents are linked, so a child arriving first
        // still finds its parent in the second pass below.
        var touchedNodeIDs: Set<UUID> = []
        for dto in archive.mapNodes {
            let wrote = merge(
                existing: mapNodes[dto.id], incomingDate: dto.updatedAt,
                currentDate: { $0.updatedAt },
                apply: { model in
                    model.id = dto.id; model.title = dto.title; model.body = dto.body
                    model.iconName = dto.iconName; model.colourToken = dto.colourToken
                    model.sortOrder = dto.sortOrder; model.isCollapsed = dto.isCollapsed
                    model.isTask = dto.isTask; model.priorityRaw = dto.priorityRaw
                    model.estimatedMinutes = dto.estimatedMinutes
                    model.map = dto.mapID.flatMap { maps[$0] }
                    model.linkedTask = dto.linkedTaskID.flatMap { tasks[$0] }
                    model.updatedAt = dto.updatedAt
                    mapNodes[dto.id] = model
                },
                create: { MapNode(title: dto.title) }
            )
            if wrote { touchedNodeIDs.insert(dto.id) }
        }

        // Parents are linked in a second pass so a child arriving before its
        // parent still finds it. Only nodes this import actually wrote are
        // relinked — reparenting a record we skipped for being older would
        // overwrite a newer local edit by the back door.
        // Loops are judged on the archive's own parent map rather than on the
        // half-linked live objects. Judging them live made the outcome depend on
        // the order records happened to arrive in: the same corrupt archive could
        // import clean or leave a bad link, one run to the next.
        var parentByID: [UUID: UUID] = [:]
        for dto in archive.mapNodes {
            if let parentID = dto.parentID { parentByID[dto.id] = parentID }
        }
        func loopsInArchive(from id: UUID) -> Bool {
            var seen: Set<UUID> = [id]
            var cursor = parentByID[id]
            while let next = cursor {
                if !seen.insert(next).inserted { return true }
                cursor = parentByID[next]
                if seen.count > 256 { return true }
            }
            return false
        }

        for dto in archive.mapNodes {
            guard touchedNodeIDs.contains(dto.id), let node = mapNodes[dto.id] else { continue }
            guard let parentID = dto.parentID, let parent = mapNodes[parentID] else {
                node.parent = nil
                continue
            }
            // A corrupt or hostile archive can name a parent that is the node
            // itself or one of its own descendants. Left unchecked that builds a
            // cycle, and the next read of the tree recurses until the app dies.
            // Every node in the loop loses its parent — the data is already
            // wrong, and picking a survivor would just re-introduce the ordering
            // dependency this check exists to remove.
            guard !loopsInArchive(from: dto.id) else {
                node.parent = nil
                continue
            }
            guard !wouldCreateCycle(child: node, parent: parent) else { continue }
            node.parent = parent
        }

        for dto in archive.notes {
            _ = merge(
                existing: notes[dto.id], incomingDate: dto.updatedAt,
                currentDate: { $0.updatedAt },
                apply: { model in
                    model.id = dto.id; model.title = dto.title; model.iconName = dto.iconName
                    model.isFavourite = dto.isFavourite; model.isArchived = dto.isArchived
                    model.isTrashed = dto.isTrashed
                    model.workspace = dto.workspaceID.flatMap { workspaces[$0] }
                    model.project = dto.projectID.flatMap { projects[$0] }
                    model.task = dto.taskID.flatMap { tasks[$0] }
                    model.updatedAt = dto.updatedAt
                    notes[dto.id] = model
                },
                create: { Note(title: dto.title) }
            )
        }

        for dto in archive.noteBlocks {
            _ = merge(
                existing: noteBlocks[dto.id], incomingDate: dto.updatedAt,
                currentDate: { $0.updatedAt },
                apply: { model in
                    model.id = dto.id; model.typeRaw = dto.typeRaw; model.text = dto.text
                    model.isChecked = dto.isChecked; model.sortOrder = dto.sortOrder
                    model.note = dto.noteID.flatMap { notes[$0] }
                    model.updatedAt = dto.updatedAt
                },
                create: { NoteBlock(text: dto.text) }
            )
        }

        try context.save()
        return summary
    }
}
