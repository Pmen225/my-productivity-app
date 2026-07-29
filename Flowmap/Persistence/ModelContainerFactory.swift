import Foundation
import SwiftData

/// Builds the app's `ModelContainer`.
///
/// The schema is declared in one place so the app, the tests and the previews
/// can never drift apart.
public enum ModelContainerFactory {
    /// Every persisted type. Adding a model here is what puts it in cloud sync.
    public static var schema: Schema {
        Schema([
            Workspace.self,
            TaskList.self,
            Initiative.self,
            Project.self,
            FlowTask.self,
            TaskSegment.self,
            Subtask.self,
            MapDocument.self,
            MapNode.self,
            Note.self,
            NoteBlock.self,
            FocusSession.self,
            AssistantThread.self,
            AssistantMessage.self,
            AppSettings.self,
        ])
    }

    /// The private CloudKit database backing the app.
    ///
    /// Declared even when the build is unsigned so the entitlement, the
    /// container identifier and the schema stay correct; SwiftData simply falls
    /// back to local-only storage when no iCloud account or signing is present.
    public static let cloudKitContainerIdentifier = "iCloud.com.flowmap.app"

    /// App container. Attempts CloudKit first, then degrades to local-only
    /// storage rather than refusing to launch — the app must work offline and
    /// without an iCloud account.
    @MainActor
    public static func makeAppContainer() -> ModelContainer {
        // `.automatic` reads the container from the app's iCloud entitlement.
        // Naming the container explicitly instead would hard-fail at launch on an
        // unsigned build, where the entitlement is not applied — the entitlement
        // and identifier stay declared in Flowmap.entitlements either way.
        let cloudConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [cloudConfiguration])
        } catch {
            CloudSyncStatus.shared.report(
                .unavailable("iCloud sync is off. Your data is saved on this device.")
            )
            let localConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            do {
                return try ModelContainer(for: schema, configurations: [localConfiguration])
            } catch {
                // A store that cannot open at all is unrecoverable; failing loudly
                // beats launching into a silently empty app.
                fatalError("Could not open the Flowmap store: \(error)")
            }
        }
    }

    /// In-memory container for tests and previews.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
