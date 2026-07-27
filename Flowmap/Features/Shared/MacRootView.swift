#if os(macOS)
import SwiftUI

struct MacRootView: View {
    var body: some View {
        NavigationSplitView {
            List { Text("Today") }
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            Text("Today")
        }
    }
}
#endif
