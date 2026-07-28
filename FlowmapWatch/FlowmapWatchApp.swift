import SwiftUI

/// The watch app's entry point.
///
/// One `WatchStore` for the whole app, handed down through the environment —
/// every screen reads it and nothing else, so there is exactly one link to the
/// phone and one place the last snapshot lives.
@main
struct FlowmapWatchApp: App {
    @State private var store = WatchStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
        }
        .onChange(of: scenePhase) { _, _ in
            // Mirrors the latest snapshot into the shared app group whenever the
            // scene's lifecycle turns over, so the complication is never stale
            // just because this scene went to the background.
            store.persistLatest()
        }
    }
}
