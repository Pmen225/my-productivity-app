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

    private var header: some View {
        Text("Settings")
            .font(FlowFont.screenTitle)
            .foregroundStyle(FlowTheme.primaryText(scheme))
    }
}
