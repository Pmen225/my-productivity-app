#if os(macOS)
import SwiftUI

/// Mac menu commands and their keyboard shortcuts.
///
/// Each one posts a notification rather than reaching into a view, so the shell
/// stays the single place that knows what a destination looks like.
struct FlowmapCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") {
                NotificationCenter.default.post(name: .flowmapQuickCapture, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Note") {
                NotificationCenter.default.post(name: .flowmapNewNote, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Button("Search") {
                NotificationCenter.default.post(name: .flowmapShowSearch, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)
        }

        CommandMenu("Focus") {
            Button("Start Focus on Selected Task") {
                NotificationCenter.default.post(name: .flowmapStartFocus, object: nil)
            }
            .keyboardShortcut(.return, modifiers: .command)

            Button("Pause or Resume") {
                NotificationCenter.default.post(name: .flowmapTogglePause, object: nil)
            }
            // Space is reserved for the Focus window itself, which only claims it
            // when no text field is editing.
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(Array(mainDestinations.enumerated()), id: \.offset) { index, destination in
                Button(destination.title) {
                    NotificationCenter.default.post(
                        name: .flowmapOpenDeepLink,
                        object: DeepLinkRequest(destination: destination)
                    )
                }
                .keyboardShortcut(
                    KeyEquivalent(Character("\(index + 1)")),
                    modifiers: .command
                )
            }
        }
    }

    /// ⌘1…⌘5, in sidebar order.
    private var mainDestinations: [DeepLink] {
        [.today, .inbox, .calendar, .focus, .map]
    }
}
#endif
