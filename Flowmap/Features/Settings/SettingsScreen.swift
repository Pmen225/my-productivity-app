import SwiftUI

/// The Settings hub: a native drill-in list (task 55) rather than one long
/// scroll of every section at once. `SettingsHub.groups` owns the grouping;
/// each row pushes its section's existing content, unchanged, as its own
/// screen. Each section still persists straight to the shared `AppSettings`
/// record — there is no separate settings view model.
struct SettingsScreen: View {
    @Environment(\.colorScheme) private var scheme
    @Binding private var selectedRow: SettingsHubRow?
    var showsTitle = true

    init(
        selectedRow: Binding<SettingsHubRow?> = .constant(nil),
        showsTitle: Bool = true
    ) {
        _selectedRow = selectedRow
        self.showsTitle = showsTitle
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if showsTitle {
                    Text("Settings")
                        .font(FlowFont.screenTitle)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                        .padding(.top, FlowSpacing.xl)
                }

                if showsTitle {
                    Text("Make Flowmap work the way you do.")
                        .font(FlowFont.secondary)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                        .padding(.top, FlowSpacing.s)
                }

                ForEach(SettingsHub.groups) { group in
                    Text(group.title.uppercased())
                        .font(FlowFont.eyebrow)
                        .tracking(0.6)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                        .padding(.top, FlowSpacing.xxxl)

                    ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            selectedRow = row
                        } label: {
                            HStack(spacing: FlowSpacing.m) {
                                Image(systemName: row.symbolName)
                                    .font(FlowFont.cardTitle)
                                    .foregroundStyle(FlowTheme.primaryText(scheme))
                                    .frame(width: FlowControlSize.utility, height: FlowControlSize.utility)
                                    .background(Circle().fill(FlowTheme.surfaceSunken(scheme)))

                                Text(row.title)
                                    .font(FlowFont.body)
                                    .foregroundStyle(FlowTheme.primaryText(scheme))

                                Spacer(minLength: FlowSpacing.s)

                                Image(systemName: "chevron.right")
                                    .font(FlowFont.caption.weight(.semibold))
                                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
                            }
                            .frame(minHeight: FlowControlSize.create)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel(row.title)
                        .accessibilityHint("Opens this Settings section")
                        .buttonStyle(FlowNavigationRowPressStyle())

                        if index < group.rows.count - 1 {
                            Divider()
                                .overlay(FlowTheme.separator(scheme))
                                .padding(.leading, FlowControlSize.utility + FlowSpacing.m)
                        }
                    }
                }
            }
            .padding(.horizontal, FlowSpacing.xl)
            .padding(.bottom, FlowSpacing.xxxl)
        }
        .scrollIndicators(.hidden)
        .background(FlowTheme.background(scheme).ignoresSafeArea())
        #if os(iOS)
        .safeAreaPadding(.top, showsTitle ? 0 : FlowControlSize.secondary)
        #endif
        .navigationDestination(
            isPresented: Binding(
                get: { selectedRow != nil },
                set: { if !$0 { selectedRow = nil } }
            )
        ) {
            if let selectedRow {
                destination(for: selectedRow)
            }
        }
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
        .safeAreaPadding(.top, FlowControlSize.secondary)
        .safeAreaPadding(.bottom, FlowSpacing.floatingControlsInset)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .background(FlowTheme.background(scheme).ignoresSafeArea())
        #if os(macOS)
        .navigationTitle(title)
        .flowScreenTitle(title)
        #endif
    }
}
