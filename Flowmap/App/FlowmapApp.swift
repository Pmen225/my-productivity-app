import SwiftData
import SwiftUI
import UserNotifications

@main
struct FlowmapApp: App {
    /// One container and one environment for the whole app, built once at launch.
    private let container: ModelContainer
    @State private var environment: AppEnvironment
    @State private var notificationRouter = NotificationRouter()

    init() {
        let container = ModelContainerFactory.makeAppContainer()
        self.container = container
        _environment = State(initialValue: AppEnvironment(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.flow, environment)
                .preferredColorScheme(environment.colourScheme)
                .tint(environment.settings.accent.base)
                .task {
                    UNUserNotificationCenter.current().delegate = notificationRouter
                    environment.reconcileOnActivation()
                }
                .onOpenURL { url in
                    guard let link = DeepLink(url: url) else { return }
                    NotificationCenter.default.post(
                        name: .flowmapOpenDeepLink,
                        object: DeepLinkRequest(destination: link)
                    )
                }
        }
        .modelContainer(container)
        #if os(macOS)
        .commands { FlowmapCommands() }
        #endif
    }
}

/// Turns a notification tap into a deep link.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Resolve the payload here: `DeepLinkRequest` is Sendable, the raw
        // `userInfo` dictionary is not, so only the former crosses to the main actor.
        guard let request = DeepLinkRequest(
            userInfo: response.notification.request.content.userInfo
        ) else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .flowmapOpenDeepLink, object: request)
        }
    }

    /// A task reminder is worth seeing even with the app in front of you.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

extension Notification.Name {
    static let flowmapShowSearch = Notification.Name("flowmap.showSearch")
    static let flowmapQuickCapture = Notification.Name("flowmap.quickCapture")
    static let flowmapNewNote = Notification.Name("flowmap.newNote")
    static let flowmapStartFocus = Notification.Name("flowmap.startFocus")
    static let flowmapTogglePause = Notification.Name("flowmap.togglePause")
}
