import SwiftUI

/// Composes every settings section onto one scrollable screen. Each section
/// is its own file and persists straight to the shared `AppSettings` record —
/// there is no separate settings view model.
struct SettingsScreen: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowSpacing.l) {
                header

                GeneralSettingsSection()
                FocusWheelSettingsSection()
                FocusAudioSettingsSection()
                NotificationSettingsSection()
                CalendarSettingsSection()
                AssistantSettingsSection()
                DataSettingsSection()
                AboutSettingsSection()
            }
            .padding(FlowSpacing.screen)
        }
        .background(FlowTheme.background(scheme).ignoresSafeArea())
    }

    /// Drawn in the scroll content rather than the navigation bar: this screen
    /// has no bar for a principal item to sit in, so `.flowScreenTitle` would
    /// leave it with no title at all. Matches `ProgressScreen`'s treatment.
    private var header: some View {
        Text("Settings")
            .font(FlowFont.screenTitleCompact)
            .foregroundStyle(FlowTheme.primaryText(scheme))
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
