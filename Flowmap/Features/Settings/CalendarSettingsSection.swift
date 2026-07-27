import SwiftUI

/// Apple Calendar integration: permission, which calendars are read, and the
/// optional calendar Flowmap writes focus blocks back to.
struct CalendarSettingsSection: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context

    var body: some View {
        FlowCard {
            VStack(alignment: .leading, spacing: FlowSpacing.l) {
                CompactSectionHeader(title: "Calendar")

                if let flow {
                    permissionRow(flow)
                    Toggle("Show Apple Calendar events", isOn: Binding(
                        get: { flow.settings.calendarIntegrationEnabled },
                        set: { newValue in
                            flow.settings.calendarIntegrationEnabled = newValue
                            try? context.save()
                            if newValue { requestAccessIfNeeded(flow) }
                        }
                    ))

                    if flow.settings.calendarIntegrationEnabled {
                        if flow.calendarService.authorisation == .authorised {
                            calendarSelectionRows(flow)
                            writeBackRow(flow)
                        } else {
                            Text("Grant calendar access to choose which calendars to show.")
                                .font(FlowFont.secondary)
                                .foregroundStyle(FlowTheme.secondaryText(scheme))
                        }
                    }
                }
            }
        }
        .task {
            if let flow, flow.settings.calendarIntegrationEnabled, flow.calendarService.authorisation == .authorised {
                flow.calendarService.loadCalendars()
            }
        }
    }

    private func permissionRow(_ flow: AppEnvironment) -> some View {
        HStack(spacing: FlowSpacing.s) {
            StatusIndicator(
                token: flow.calendarService.authorisation == .authorised ? .green : .peach,
                symbolName: flow.calendarService.authorisation == .authorised ? "calendar" : "calendar.badge.exclamationmark",
                label: flow.calendarService.authorisation.explanation
            )
            Text(flow.calendarService.authorisation.explanation)
                .font(FlowFont.secondary)
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: FlowSpacing.s)
        }
    }

    private func calendarSelectionRows(_ flow: AppEnvironment) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            Text("Calendars shown").font(FlowFont.secondary).foregroundStyle(FlowTheme.secondaryText(scheme))
            if flow.calendarService.availableCalendars.isEmpty {
                Text("No calendars found on this device.")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            } else {
                ForEach(flow.calendarService.availableCalendars) { calendar in
                    calendarRow(flow, calendar)
                }
            }
        }
    }

    private func calendarRow(_ flow: AppEnvironment, _ calendar: SelectableCalendar) -> some View {
        let isSelected = flow.settings.selectedCalendarIdentifiers.contains(calendar.id)
        return Toggle(calendar.title, isOn: Binding(
            get: { isSelected },
            set: { newValue in
                var identifiers = flow.settings.selectedCalendarIdentifiers
                if newValue {
                    if !identifiers.contains(calendar.id) { identifiers.append(calendar.id) }
                } else {
                    identifiers.removeAll { $0 == calendar.id }
                }
                flow.settings.selectedCalendarIdentifiers = identifiers
                try? context.save()
            }
        ))
        .font(FlowFont.secondary)
    }

    private func writeBackRow(_ flow: AppEnvironment) -> some View {
        let writableCalendars = flow.calendarService.availableCalendars.filter(\.allowsModification)
        return VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            Toggle("Write focus blocks to a calendar", isOn: Binding(
                get: { flow.settings.writesFocusBlocksToCalendar },
                set: { newValue in
                    flow.settings.writesFocusBlocksToCalendar = newValue
                    try? context.save()
                }
            ))

            if flow.settings.writesFocusBlocksToCalendar {
                if writableCalendars.isEmpty {
                    Text("No writable calendars available.")
                        .font(FlowFont.caption)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
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

    private func requestAccessIfNeeded(_ flow: AppEnvironment) {
        guard flow.calendarService.authorisation != .authorised else {
            flow.calendarService.loadCalendars()
            return
        }
        Task {
            let granted = await flow.calendarService.requestAccess()
            if granted { flow.calendarService.loadCalendars() }
        }
    }
}
