import SwiftUI

/// The watch's three panes, swiped top to bottom with the crown or a finger —
/// the phone's Focus / Today / Capture loop, reduced to what fits a small
/// screen with nothing added.
struct WatchRootView: View {
    var body: some View {
        TabView {
            WatchFocusView()
            WatchTimelineView()
            WatchCaptureView()
        }
        .tabViewStyle(.verticalPage)
    }
}
