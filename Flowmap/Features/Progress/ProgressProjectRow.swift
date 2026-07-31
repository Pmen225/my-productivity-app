import SwiftUI

/// One row on the Stats screen's Projects list: a track/untrack toggle, token
/// dot, name, a thin completion capsule and the raw D/T fraction, expanding to
/// show the project's own tasks — deliberately simpler than
/// `Features/Projects/ProjectRow`, which carries status and due-date chrome
/// this screen doesn't need.
struct ProgressProjectRow: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let project: Project

    @State private var isExpanded = false

    private var counts: (completed: Int, total: Int) {
        (project.completedTaskCount, project.actionableTasks.count)
    }

    private var fraction: Double {
        let counts = counts
        return counts.total > 0 ? Double(counts.completed) / Double(counts.total) : 0
    }

    var body: some View {
        // The toggle circle is a real `Button` living OUTSIDE the disclosure
        // label: a `Button` nested inside `FlowAccordionStyle`'s own label
        // `Button` receives no taps on iOS — the outer one swallows them,
        // silently, no error and no test failure.
        // Tight spacing here on purpose: the toggle's own 44pt hit frame
        // already supplies the visual gap, and FlowSpacing.m on top of it
        // left a conspicuous hole between the circle and the colour dot.
        HStack(alignment: .top, spacing: FlowSpacing.xxs) {
            trackToggle

            DisclosureGroup(isExpanded: $isExpanded) {
                taskList
            } label: {
                header
            }
            .disclosureGroupStyle(FlowAccordionStyle(reduceMotion: reduceMotion))
        }
        .padding(FlowSpacing.m)
        // Card background and border stay on this outer container, wrapping
        // both the toggle and the disclosure — a bordered card nested inside
        // another bordered card reads as busy (HIG Boxes, apple_hig_ios.md:2475).
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .fill(FlowTheme.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .strokeBorder(FlowTheme.separator(scheme), lineWidth: 1)
        )
    }

    // MARK: - Track/untrack toggle

    /// A button that behaves like a toggle, never a system `Toggle`/switch —
    /// settled at `parity-audit.md:286`. Filled-vs-outline is a shape
    /// difference, not colour alone (HIG `:17057`), but that channel only
    /// exists visually until VoiceOver also gets `.isSelected` and a label.
    private var trackToggle: some View {
        Button {
            project.isTrackedInStats.toggle()
            project.touch()
        } label: {
            Circle()
                .fill(project.isTrackedInStats ? FlowTheme.accent : Color.clear)
                .frame(width: 18, height: 18)
                .overlay(
                    Circle().strokeBorder(
                        project.isTrackedInStats ? FlowTheme.accent : FlowTheme.separatorStrong(scheme),
                        lineWidth: 2
                    )
                )
                // 18pt artwork inside a ≥44×44pt hit region.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(project.isTrackedInStats ? "Tracked in stats" : "Not tracked in stats")
        .accessibilityAddTraits(project.isTrackedInStats ? .isSelected : [])
    }

    // MARK: - Header (disclosure label)

    /// Keeps the row's current content in its current order — colour dot,
    /// title, progress capsule, D/T fraction — and gains the mockup's
    /// trailing chevron. Hit target copies `LibraryAccordionRow.header`'s
    /// treatment: sized to the 44pt floor plus its own padding, not clipped
    /// to it.
    private var header: some View {
        let counts = counts

        return HStack(spacing: FlowSpacing.m) {
            Circle()
                .fill(project.colour.onSoft)
                .frame(width: 8, height: 8)
                // Untracked row dims: the colour dot, the progress capsule's
                // fill and any duration chip — never the whole row, which
                // would drop body text below the HIG's 4.5:1 floor
                // (parity-audit.md, T7 section).
                .opacity(project.isTrackedInStats ? 1 : 0.45)
                .accessibilityHidden(true)

            Text(project.title)
                .font(FlowFont.body)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .lineLimit(1)
                // The title wins the squeeze, and the capsule is capped, or a
                // 44pt hit target plus a greedy progress bar truncate it to
                // "Work Prior…" — the mockup gives the name 104pt of a 390pt
                // row and the bar what is left, not the other way round.
                .layoutPriority(1)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(FlowTheme.separator(scheme))
                    Capsule().fill(project.colour.base)
                        .frame(width: proxy.size.width * fraction)
                        .opacity(project.isTrackedInStats ? 1 : 0.45)
                }
            }
            .frame(height: 4)

            Text("\(counts.completed)/\(counts.total)")
                .font(FlowFont.caption.monospacedDigit())
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .frame(minWidth: 32, alignment: .trailing)

            // The mockup's `▸`, rotating 90° open — matches
            // `LibraryAccordionRow`'s own disclosure-triangle convention.
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(.vertical, FlowSpacing.xs)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.title), \(counts.completed) of \(counts.total) tasks complete")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }

    // MARK: - Per-task list

    /// The project's own tasks, unfolded under the header — indented past
    /// the toggle circle and colour dot, matching the mockup's `padding: '0
    /// 14px 10px 41px'` (`Flowmap iPhone.dc.html:1263`).
    private var taskList: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            if project.actionableTasks.isEmpty {
                Text("No tasks in this project yet.")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
            } else {
                // Sorted explicitly: a SwiftData to-many relationship has no
                // guaranteed order, so an unsorted list can reshuffle between
                // reads of the same project.
                ForEach(project.actionableTasks.sorted { $0.sortOrder < $1.sortOrder }) { task in
                    HStack(spacing: FlowSpacing.s) {
                        Circle()
                            .fill(task.status == .completed ? FlowTheme.accent : FlowTheme.separator(scheme))
                            .frame(width: 8, height: 8)

                        Text(task.title)
                            .font(FlowFont.caption)
                            .foregroundStyle(
                                task.status == .completed
                                    ? FlowTheme.tertiaryText(scheme)
                                    : FlowTheme.primaryText(scheme)
                            )
                            .strikethrough(task.status == .completed)
                            .lineLimit(1)

                        Spacer(minLength: FlowSpacing.s)

                        DurationChip(minutes: task.estimatedMinutes)
                            .opacity(project.isTrackedInStats ? 1 : 0.45)
                    }
                }
            }
        }
        .padding(.leading, FlowSpacing.l)
        .padding(.top, FlowSpacing.xs)
    }
}
