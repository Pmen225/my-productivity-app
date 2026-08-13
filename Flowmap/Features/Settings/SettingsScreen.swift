import SwiftUI

/// The Settings hub: a native drill-in list (task 55) rather than one long
/// scroll of every section at once. `SettingsHub.groups` owns the grouping;
/// each row pushes its section's existing content, unchanged, as its own
/// screen. Each section still persists straight to the shared `AppSettings`
/// record — there is no separate settings view model.
struct SettingsScreen: View {
    var body: some View {
        List {
            ForEach(SettingsHub.groups) { group in
                Section {
                    ForEach(group.rows) { row in
                        NavigationLink {
                            destination(for: row)
                        } label: {
                            Label(row.title, systemImage: row.symbolName)
                        }
                        .accessibilityLabel(row.title)
                        .accessibilityHint("Opens this Settings section")
                        .buttonStyle(FlowNavigationRowPressStyle())
                    }
                } header: {
                    FlowEyebrow(group.title)
                }
            }
        }
        #if os(iOS)
        .safeAreaPadding(.bottom, FlowSpacing.floatingControlsInset)
        #endif
        .navigationTitle("Settings")
        .flowScreenTitle("Settings")
    }

    @ViewBuilder
    private func destination(for row: SettingsHubRow) -> some View {
        switch row {
        case .general: SettingsSectionScreen(title: row.title) { GeneralSettingsSection() }
        case .focusWheel: SettingsSectionScreen(title: row.title) { FocusWheelSettingsSection() }
        case .sounds: SettingsSectionScreen(title: row.title) { SoundSettingsSection() }
        case .notifications: SettingsSectionScreen(title: row.title) { NotificationSettingsSection() }
        case .calendar: SettingsSectionScreen(title: row.title) { CalendarSettingsSection() }
        case .assistant: SettingsSectionScreen(title: row.title) { AssistantSettingsSection() }
        case .data: SettingsSectionScreen(title: row.title) { DataSettingsSection() }
        case .about: SettingsSectionScreen(title: row.title) { AboutSettingsSection() }
        }
    }
}

/// Wraps one existing `…SettingsSection` as its own pushed screen. Reproduces
/// the hub's old all-sections-at-once scroll container, now per-section — the
/// section content itself is untouched, only its container changed.
private struct SettingsSectionScreen<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowSpacing.l) {
                content()
            }
            .padding(FlowSpacing.screen)
        }
        #if os(iOS)
        .safeAreaPadding(.bottom, FlowSpacing.floatingControlsInset)
        #endif
        .background(FlowTheme.background(scheme).ignoresSafeArea())
        .navigationTitle(title)
        .flowScreenTitle(title)
    }
}
