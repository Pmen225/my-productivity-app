import SwiftUI

/// Calendar accounts: connect, disconnect, choose which calendars are read,
/// and see what's wrong when a connection breaks.
///
/// Both Apple and Google are driven from `CalendarHub.connections` so this
/// view never special-cases which account is "the" calendar — it renders
/// whatever the hub reports. Apple goes through the system permission
/// prompt; Google needs an OAuth client id before it can sign in.
struct CalendarSettingsSection: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context

    /// The account a disconnect confirmation is being asked about.
    @State private var pendingDisconnect: CalendarAccountKind?

    var body: some View {
        FlowCard {
            VStack(alignment: .leading, spacing: FlowSpacing.l) {
                FlowEyebrow("Calendar")

                if let flow {
                    if flow.calendarHub.isWorking {
                        HStack(spacing: FlowSpacing.s) {
                            ProgressView()
                            Text("Working…")
                                .font(FlowFont.caption)
                                .foregroundStyle(FlowTheme.secondaryText(scheme))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Calendar connection working")
                    }

                    appleSection(flow)
                    googleSection(flow)
                }
            }
        }
        .confirmationDialog(
            "Disconnect \(pendingDisconnect?.displayName ?? "calendar")?",
            isPresented: Binding(
                get: { pendingDisconnect != nil },
                set: { isPresented in if !isPresented { pendingDisconnect = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let kind = pendingDisconnect, let flow {
                Button("Disconnect", role: .destructive) {
                    disconnect(kind, flow: flow)
                    pendingDisconnect = nil
                }
                Button("Cancel", role: .cancel) { pendingDisconnect = nil }
            }
        } message: {
            if pendingDisconnect == .apple {
                Text("Flowmap forgets this connection. System calendar permission stays granted until you turn it off in Settings.")
            } else {
                Text("Flowmap signs out and forgets which Google calendars were selected.")
            }
        }
        .task {
            // Picks up whatever each account already knows (cached calendars,
            // last error) without waiting for the next scheduling refresh.
            if let flow { await flow.calendarHub.refreshCalendars() }
        }
    }

    // MARK: - Apple

    @ViewBuilder
    private func appleSection(_ flow: AppEnvironment) -> some View {
        let connection = flow.calendarHub.connection(for: .apple) ?? CalendarConnection(kind: .apple)

        CalendarAccountRow(kind: .apple, connection: connection) {
            VStack(alignment: .leading, spacing: FlowSpacing.s) {
                connectDisconnectButton(
                    kind: .apple,
                    isConnected: connection.isConnected,
                    flow: flow
                ) {
                    flow.settings.calendarIntegrationEnabled = true
                }

                if connection.isConnected {
                    calendarList(
                        calendars: connection.calendars,
                        selected: flow.settings.selectedCalendarIdentifiers,
                        flow: flow
                    ) { identifiers in
                        flow.settings.selectedCalendarIdentifiers = identifiers
                    }
                    writeBackRow(flow, calendars: connection.calendars)
                } else {
                    Text(flow.calendarService.authorisation.explanation)
                        .font(FlowFont.secondary)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Google

    @ViewBuilder
    private func googleSection(_ flow: AppEnvironment) -> some View {
        let connection = flow.calendarHub.connection(for: .google) ?? CalendarConnection(kind: .google)
        let clientIDEmpty = (flow.settings.googleOAuthClientID ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        CalendarAccountRow(kind: .google, connection: connection) {
            VStack(alignment: .leading, spacing: FlowSpacing.s) {
                VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                    Text("OAuth client ID")
                        .font(FlowFont.secondary)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                    TextField("Client ID", text: Binding(
                        get: { flow.settings.googleOAuthClientID ?? "" },
                        set: { newValue in
                            flow.settings.googleOAuthClientID = newValue
                            try? context.save()
                        }
                    ))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, FlowSpacing.m)
                    .padding(.vertical, FlowSpacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                            .fill(FlowTheme.surfaceSunken(scheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                            .strokeBorder(FlowTheme.separatorStrong(scheme), lineWidth: 1)
                    )
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityLabel("Google OAuth client ID")
                    Text("From the Google Cloud Console, under APIs & Services → Credentials.")
                        .font(FlowFont.caption)
                        .foregroundStyle(FlowTheme.tertiaryText(scheme))
                }

                if !connection.isConnected && clientIDEmpty {
                    Text("Add a client id before connecting.")
                        .font(FlowFont.caption)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                }

                connectDisconnectButton(
                    kind: .google,
                    isConnected: connection.isConnected,
                    disabledToConnect: clientIDEmpty,
                    flow: flow
                ) {
                    flow.settings.googleCalendarEnabled = true
                    flow.settings.googleAccountLabel = flow.calendarHub.connection(for: .google)?.accountLabel
                }

                if connection.isConnected {
                    calendarList(
                        calendars: connection.calendars,
                        selected: flow.settings.selectedGoogleCalendarIdentifiers,
                        flow: flow
                    ) { identifiers in
                        flow.settings.selectedGoogleCalendarIdentifiers = identifiers
                    }
                }
            }
        }
    }

    // MARK: - Shared controls

    /// One button that connects or, when already connected, asks to
    /// disconnect. `onConnected` stores whatever that account needs into
    /// settings once the hub reports success.
    @ViewBuilder
    private func connectDisconnectButton(
        kind: CalendarAccountKind,
        isConnected: Bool,
        disabledToConnect: Bool = false,
        flow: AppEnvironment,
        onConnected: @escaping () -> Void
    ) -> some View {
        let isWorking = flow.calendarHub.isWorking
        if isConnected {
            SecondaryActionButton("Disconnect", systemImage: "xmark.circle") {
                pendingDisconnect = kind
            }
            .disabled(isWorking)
            .opacity(isWorking ? 0.5 : 1)
            .accessibilityLabel("Disconnect \(kind.displayName)")
        } else {
            SecondaryActionButton("Connect", systemImage: "link") {
                Task {
                    let success = await flow.calendarHub.connect(kind)
                    guard success else { return }
                    onConnected()
                    try? context.save()
                    flow.refreshCalendarWindow(around: flow.now)
                }
            }
            .disabled(isWorking || disabledToConnect)
            .opacity((isWorking || disabledToConnect) ? 0.5 : 1)
            .accessibilityLabel("Connect \(kind.displayName)")
        }
    }

    /// One toggle per readable calendar. Toggling writes straight into the
    /// account's own settings field and refreshes the busy-time window so the
    /// planner sees the change immediately.
    @ViewBuilder
    private func calendarList(
        calendars: [SelectableCalendarSummary],
        selected: [String],
        flow: AppEnvironment,
        onChange: @escaping ([String]) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            FlowEyebrow("Calendars shown")

            if calendars.isEmpty {
                Text("No calendars found yet.")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
            } else {
                ForEach(calendars) { calendar in
                    Toggle(calendar.title, isOn: Binding(
                        get: { selected.contains(calendar.id) },
                        set: { isOn in
                            var identifiers = selected
                            if isOn {
                                if !identifiers.contains(calendar.id) { identifiers.append(calendar.id) }
                            } else {
                                identifiers.removeAll { $0 == calendar.id }
                            }
                            onChange(identifiers)
                            try? context.save()
                            flow.refreshCalendarWindow(around: flow.now)
                        }
                    ))
                    .font(FlowFont.secondary)
                    .tint(FlowTheme.accent)
                    .accessibilityLabel("Show \(calendar.title)")
                }
            }
        }
    }

    /// Which calendar focus blocks are written back to. Only Apple supports
    /// write-back today, so this stays inside the Apple section; only
    /// calendars the account can actually modify are offered.
    @ViewBuilder
    private func writeBackRow(_ flow: AppEnvironment, calendars: [SelectableCalendarSummary]) -> some View {
        let writableCalendars = calendars.filter(\.allowsModification)
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            Toggle("Write focus blocks to calendar", isOn: Binding(
                get: { flow.settings.writesFocusBlocksToCalendar },
                set: { newValue in
                    flow.settings.writesFocusBlocksToCalendar = newValue
                    try? context.save()
                }
            ))
            .tint(FlowTheme.accent)

            if flow.settings.writesFocusBlocksToCalendar {
                if writableCalendars.isEmpty {
                    Text("No writable calendars available.")
                        .font(FlowFont.caption)
                        .foregroundStyle(FlowTheme.tertiaryText(scheme))
                } else {
                    Picker("Write-back calendar", selection: Binding(
                        get: { flow.settings.writeBackCalendarIdentifier ?? writableCalendars.first?.id },
                        set: { newValue in
                            flow.settings.writeBackCalendarIdentifier = newValue
                            try? context.save()
                        }
                    )) {
                        ForEach(writableCalendars) { calendar in
                            Text(calendar.title).tag(Optional(calendar.id))
                        }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    // MARK: - Disconnect

    private func disconnect(_ kind: CalendarAccountKind, flow: AppEnvironment) {
        flow.calendarHub.disconnect(kind)
        switch kind {
        case .apple:
            flow.settings.calendarIntegrationEnabled = false
            flow.settings.selectedCalendarIdentifiers = []
        case .google:
            flow.settings.googleCalendarEnabled = false
            flow.settings.selectedGoogleCalendarIdentifiers = []
            flow.settings.googleAccountLabel = nil
        }
        try? context.save()
        flow.refreshCalendarWindow(around: flow.now)
    }
}
