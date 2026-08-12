import SwiftUI

/// Appearance, accent, app font, first day of week, the working day's shape,
/// and the default duration new tasks are given.
struct GeneralSettingsSection: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context

    var body: some View {
        FlowCard {
            VStack(alignment: .leading, spacing: FlowSpacing.l) {
                FlowEyebrow("General")

                if let flow {
                    appearanceRow(flow)
                    themeRow(flow)
                    accentRow(flow)
                    appFontRow(flow)
                    firstWeekdayRow(flow)
                    workdayRow(flow)
                    defaultDurationRow(flow)
                }
            }
        }
    }

    private func appearanceRow(_ flow: AppEnvironment) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            Text("Appearance").font(FlowFont.secondary).foregroundStyle(FlowTheme.secondaryText(scheme))
            Picker("Appearance", selection: Binding(
                get: { flow.settings.appearance },
                set: { newValue in
                    flow.settings.appearance = newValue
                    save()
                }
            )) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func themeRow(_ flow: AppEnvironment) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            Text("Theme").font(FlowFont.secondary).foregroundStyle(FlowTheme.secondaryText(scheme))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: FlowSpacing.m) {
                ForEach(FlowPalette.all) { palette in
                    themeTile(palette, isSelected: flow.settings.themeRaw == palette.id) {
                        flow.settings.themeRaw = palette.id
                        save()
                    }
                }
            }
        }
    }

    private func themeTile(_ palette: FlowPalette, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                ZStack(alignment: .topLeading) {
                    palette.bgLightColor
                    palette.bgDarkColor.clipShape(ThemeDiagonalSplit())
                    themePreviewPill(palette)
                        .padding(FlowSpacing.xs)
                }
                .frame(height: 72)
                .clipShape(RoundedRectangle(cornerRadius: FlowRadius.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: FlowRadius.medium)
                        .stroke(
                            isSelected ? palette.accentColor : FlowTheme.separatorStrong(scheme),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(palette.accentColor)
                            .padding(FlowSpacing.xs)
                    }
                }

                Text(palette.name)
                    .font(FlowFont.secondary)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(palette.name) theme")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// A miniature of the app's own chrome — three accent dots on a white pill —
    /// sitting in the tile's light half.
    private func themePreviewPill(_ palette: FlowPalette) -> some View {
        HStack(spacing: FlowSpacing.xxs) {
            Circle().fill(palette.accentColor).frame(width: 10, height: 10)
            Circle().fill(palette.accentDeepColor).frame(width: 10, height: 10)
            Circle().fill(palette.accentFillColor).frame(width: 10, height: 10)
        }
        .padding(.horizontal, FlowSpacing.xs)
        .padding(.vertical, FlowSpacing.xxs)
        .background(palette.surfaceLightColor, in: Capsule())
    }

    private func accentRow(_ flow: AppEnvironment) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            Text("Accent colour").font(FlowFont.secondary).foregroundStyle(FlowTheme.secondaryText(scheme))
            HStack(spacing: FlowSpacing.s) {
                ForEach(ColourToken.allCases, id: \.self) { token in
                    accentSwatch(token, current: flow.settings.accent) {
                        flow.settings.accent = token
                        save()
                    }
                }
            }
        }
    }

    private func accentSwatch(_ token: ColourToken, current: ColourToken, action: @escaping () -> Void) -> some View {
        let isSelected = token == current
        return Button(action: action) {
            Circle()
                .fill(token.base)
                .frame(width: 28, height: 28)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(token.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func appFontRow(_ flow: AppEnvironment) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            Text("App font").font(FlowFont.secondary).foregroundStyle(FlowTheme.secondaryText(scheme))
            Picker("App font", selection: Binding(
                get: { flow.settings.appFont },
                set: { newValue in
                    flow.settings.appFont = newValue
                    save()
                }
            )) {
                ForEach(AppFontChoice.allCases, id: \.self) { font in
                    Text(font.displayName).tag(font)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func firstWeekdayRow(_ flow: AppEnvironment) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            Text("First day of week").font(FlowFont.secondary).foregroundStyle(FlowTheme.secondaryText(scheme))
            Picker("First day of week", selection: Binding(
                get: { flow.settings.firstWeekday },
                set: { newValue in
                    flow.settings.firstWeekday = newValue
                    save()
                }
            )) {
                Text("Sunday").tag(1)
                Text("Monday").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func workdayRow(_ flow: AppEnvironment) -> some View {
        HStack(spacing: FlowSpacing.l) {
            VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                Text("Workday starts").font(FlowFont.secondary).foregroundStyle(FlowTheme.secondaryText(scheme))
                DatePicker(
                    "Workday starts",
                    selection: workdayTimeBinding(
                        hour: flow.settings.workdayStartHour,
                        minute: flow.settings.workdayStartMinute
                    ) { hour, minute in
                        flow.settings.workdayStartHour = hour
                        flow.settings.workdayStartMinute = minute
                        save()
                    },
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                Text("Workday ends").font(FlowFont.secondary).foregroundStyle(FlowTheme.secondaryText(scheme))
                DatePicker(
                    "Workday ends",
                    selection: workdayTimeBinding(
                        hour: flow.settings.workdayEndHour,
                        minute: flow.settings.workdayEndMinute
                    ) { hour, minute in
                        flow.settings.workdayEndHour = hour
                        flow.settings.workdayEndMinute = minute
                        save()
                    },
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
            }
        }
    }

    /// Bridges the stored hour/minute integers to the `Date` a `DatePicker`
    /// needs, without introducing a second stored representation of the time.
    private func workdayTimeBinding(hour: Int, minute: Int, onChange: @escaping (Int, Int) -> Void) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                onChange(components.hour ?? hour, components.minute ?? minute)
            }
        )
    }

    private func defaultDurationRow(_ flow: AppEnvironment) -> some View {
        Stepper(
            "Default task duration: \(DurationFormatter.compact(minutes: flow.settings.defaultTaskMinutes))",
            value: Binding(
                get: { flow.settings.defaultTaskMinutes },
                set: { newValue in
                    flow.settings.defaultTaskMinutes = newValue
                    save()
                }
            ),
            in: 5...240,
            step: 5
        )
        .font(FlowFont.secondary)
        .foregroundStyle(FlowTheme.primaryText(scheme))
        .accessibilityValue(DurationFormatter.spoken(minutes: flow.settings.defaultTaskMinutes))
    }

    private func save() {
        try? context.save()
    }
}

/// The lower-right triangle of its bounding rect — clips a theme tile's dark
/// half so a single tile previews light and dark together, split diagonally
/// from the top-right corner to the bottom-left, MindNode-style.
private struct ThemeDiagonalSplit: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
