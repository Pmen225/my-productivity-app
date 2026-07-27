#if !os(macOS)
import SwiftUI

struct PhoneRootView: View {
    var body: some View {
        TabView {
            Text("Today").tabItem { Label("Today", systemImage: "sun.max") }
            Text("Map").tabItem { Label("Map", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            Text("Calendar").tabItem { Label("Calendar", systemImage: "calendar") }
            Text("Focus").tabItem { Label("Focus", systemImage: "timer") }
            Text("Library").tabItem { Label("Library", systemImage: "square.stack") }
        }
    }
}
#endif
