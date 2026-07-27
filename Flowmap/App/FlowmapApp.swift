import SwiftData
import SwiftUI

@main
struct FlowmapApp: App {
    /// One container for the whole app, created once at launch.
    private let container: ModelContainer = ModelContainerFactory.makeAppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
