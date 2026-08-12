import AppIntents
import Foundation
import SwiftData

/// Shared container access for intents, which run outside the app's scene.
@MainActor
enum IntentStore {
    static let container: ModelContainer = ModelContainerFactory.makeAppContainer()

    static var context: ModelContext { ModelContext(container) }

    static func settings(in context: ModelContext) -> AppSettings {
        let existing = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        if let first = existing.first { return first }
        let created = AppSettings()
        context.insert(created)
        try? context.save()
        return created
    }
}

/// Capture a task without opening the app.
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"
    static let description = IntentDescription("Capture a task straight into your Flowmap Inbox.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Task", requestValueDialog: "What would you like to add?")
    var taskTitle: String

    @Parameter(title: "Minutes", default: 30)
    var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentStore.context
        let settings = IntentStore.settings(in: context)

        let task = FlowTask(
            title: taskTitle,
            status: .inbox,
            estimatedMinutes: minutes > 0 ? minutes : settings.defaultTaskMinutes
        )
        _ = TaskCreationService.insert(task, in: context)

        return .result(
            dialog: IntentDialog(
                "Added \(taskTitle) to your Inbox for \(DurationFormatter.spoken(minutes: task.estimatedMinutes))."
            )
        )
    }
}

/// Start focusing, either on the next scheduled block or for a chosen length.
struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Focus"
    static let description = IntentDescription("Begin a focus session in Flowmap.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Minutes", default: 30)
    var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = IntentStore.context
        let settings = IntentStore.settings(in: context)
        let engine = FocusEngine(context: context, settings: settings)
        let now = Date()

        if let segment = engine.currentSegment(at: now), let task = segment.task {
            // Siri has no surface for the plan-gate's Definition of Done
            // field, so a gated task is reported through the dialog rather
            // than bypassed — the same compulsory rule the phone UI enforces.
            guard engine.start(segment: segment, now: now) != nil else {
                if engine.pendingGate?.kind == .planGate {
                    return .result(dialog: IntentDialog("\(task.title) needs a Definition of Done first — open Flowmap to plan it."))
                }
                return .result(dialog: IntentDialog("\(task.title) needs a quick clock-in — open Flowmap to start it."))
            }
            return .result(dialog: IntentDialog("Focusing on \(task.title)."))
        }

        let length = minutes > 0 ? minutes : settings.defaultFreeFocusMinutes
        _ = engine.startFreeFocus(minutes: length, now: now)
        return .result(
            dialog: IntentDialog("Focusing for \(DurationFormatter.spoken(minutes: length)).")
        )
    }
}

/// Open the day's plan.
struct OpenTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Today"
    static let description = IntentDescription("Open today's plan in Flowmap.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .flowmapOpenDeepLink,
            object: DeepLinkRequest(destination: .today)
        )
        return .result()
    }
}

extension Notification.Name {
    /// Carries a `DeepLinkRequest` from an intent or notification tap into the UI.
    static let flowmapOpenDeepLink = Notification.Name("flowmap.openDeepLink")
}

struct FlowmapShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task to \(.applicationName)",
                "Capture in \(.applicationName)",
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: StartFocusIntent(),
            phrases: [
                "Start focus in \(.applicationName)",
                "Focus with \(.applicationName)",
            ],
            shortTitle: "Start Focus",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: OpenTodayIntent(),
            phrases: [
                "Open today in \(.applicationName)",
                "Show my \(.applicationName) plan",
            ],
            shortTitle: "Open Today",
            systemImageName: "sun.max"
        )
    }
}
