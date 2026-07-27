import SwiftData
import SwiftUI

/// Chooses the platform shell. Everything below this point is shared.
struct RootView: View {
    var body: some View {
        #if os(macOS)
        MacRootView()
        #else
        PhoneRootView()
        #endif
    }
}
