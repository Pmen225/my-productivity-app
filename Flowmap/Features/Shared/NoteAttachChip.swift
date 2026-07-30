import SwiftUI

/// One task a note can attach to. Filled when attached, with a `✓ ` text
/// prefix — the tick is mandatory, not decorative: HIG *Toggles* → Best
/// practices warns against signalling state by colour alone, and the tick is
/// the non-colour channel. See the T6 stage 2 rulings in
/// `state/specs/parity-audit.md`.
///
/// A button that behaves like a toggle, per HIG *Toggles* → iOS: "Outside of
/// a list, use a button that behaves like a toggle, not a switch." Not a
/// `Toggle`, and not a token field — HIG *Token fields* names those
/// unsupported on iOS. This is the same shape `FlowCreateSheet.chip`
/// (`FlowChrome.swift:791`), `QuickAddTaskView.destinationPill` (`:176`) and
/// `.durationChip` (`:136`) already draw three times; this is a deliberate
/// fourth private copy, not a refactor of those three (parity-audit.md,
/// T6 stage 2 rulings) — promoting them to one shared component is a
/// follow-up, not part of this diff.
struct NoteAttachChip: View {
    @Environment(\.colorScheme) private var scheme

    let title: String
    let colour: ColourToken
    let isAttached: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: FlowSpacing.xs) {
                if !isAttached {
                    Circle().fill(colour.base).frame(width: 8, height: 8)
                }
                Text(isAttached ? "✓ \(title)" : title)
                    .font(FlowFont.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, FlowSpacing.m)
            // HIG override: matches the three existing chip copies — the
            // mock's own chip reads shorter than 44pt, so the tappable frame
            // guarantees the hit target regardless of drawn height.
            .frame(minHeight: 44)
            .background(Capsule().fill(isAttached ? FlowTheme.accentFill : FlowTheme.surface(scheme)))
            .foregroundStyle(isAttached ? .white : FlowTheme.primaryText(scheme))
            .overlay(
                Capsule().strokeBorder(FlowTheme.separator(scheme), lineWidth: isAttached ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
        // The `✓ ` is a visual-only channel for the tick's sighted purpose;
        // VoiceOver already gets the attached state from `.isSelected`, so
        // the spoken label stays the plain title rather than "check mark
        // Write agenda".
        .accessibilityLabel(title)
        .accessibilityAddTraits(isAttached ? [.isButton, .isSelected] : .isButton)
    }
}

/// The chip row beneath one note's preview row inside the unfolded Notes
/// accordion (ruling 5, T6 stage 2) — attach or detach its task.
struct NoteAttachRow: View {
    @Environment(\.colorScheme) private var scheme

    let note: Note
    let candidates: [FlowTask]
    let onToggle: (FlowTask?) -> Void

    @State private var showingPicker = false

    /// Beyond this many candidates the chip row would need its own scroll
    /// view at large Dynamic Type sizes — the anti-pattern the HIG-read
    /// forbids. A searchable picker takes over instead (ruling 6,
    /// `### T6 — Library sections` in parity-audit.md).
    static let chipLimit = 8

    /// `candidates` plus the currently attached task if a status change
    /// (e.g. completing it) has since dropped it out of the open-task
    /// filter. Without this, "tap the lit chip to detach" (ruling 4) would
    /// silently stop being true the moment the attached task closes — a
    /// dead-affordance bug this repo has shipped before (see CLAUDE.md's
    /// "dead UI branches are silent"). Exposed so a test can assert the
    /// merge without touching view state.
    static func displayCandidates(_ candidates: [FlowTask], attached: FlowTask?) -> [FlowTask] {
        guard let attached, !candidates.contains(where: { $0.id == attached.id }) else {
            return candidates
        }
        return [attached] + candidates
    }

    private var displayCandidates: [FlowTask] {
        Self.displayCandidates(candidates, attached: note.task)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            // No open task exists at all — there is nothing to attach to, so
            // the whole row goes, eyebrow included. Rendering the "ATTACH TO A
            // TASK" heading above no controls would be a label promising an
            // action that cannot be taken — the dead-affordance shape CLAUDE.md
            // records as silent, because nothing errors and every test passes.
            if !displayCandidates.isEmpty {
                // The mockup's own wording (`Flowmap iPhone.dc.html:973`) —
                // wording is the mockup's to own. `FlowEyebrow` uppercases.
                FlowEyebrow(note.task != nil ? "Attached — tap to detach" : "Attach to a task")
            }

            if displayCandidates.count > Self.chipLimit {
                pickerButton
            } else {
                NoteAttachChipWrap(spacing: FlowSpacing.s) {
                    ForEach(displayCandidates) { task in
                        NoteAttachChip(
                            title: task.title,
                            colour: task.colour,
                            isAttached: note.task?.id == task.id
                        ) {
                            // The single-select toggle rule (attach vs.
                            // detach vs. re-assign) lives in one place —
                            // `LibraryView.attachToggleResult` — and runs
                            // here via `onToggle`; this view only reports
                            // which chip was tapped.
                            onToggle(task)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            NoteAttachPickerView(candidates: displayCandidates, current: note.task) { task in
                onToggle(task)
            }
        }
    }

    private var pickerButton: some View {
        Button {
            showingPicker = true
        } label: {
            Text("Attach task…")
                .font(FlowFont.secondary)
                .padding(.horizontal, FlowSpacing.m)
                .frame(minHeight: 44)
                .background(Capsule().fill(FlowTheme.surface(scheme)))
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .overlay(Capsule().strokeBorder(FlowTheme.separator(scheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// A plain `.searchable` list in a sheet — `GlobalSearchView` searches the
/// whole app with no candidate-filtering entry point, so it does not fit a
/// picker scoped to one note's open tasks (ruling 6 names this fallback).
private struct NoteAttachPickerView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    let candidates: [FlowTask]
    let current: FlowTask?
    let onSelect: (FlowTask?) -> Void

    @State private var query = ""

    private var filtered: [FlowTask] {
        guard !query.isEmpty else { return candidates }
        return candidates.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { task in
                Button {
                    // Same single-select toggle rule as the chip row — the
                    // caller (`LibraryView.toggleAttach`) applies it via
                    // `attachToggleResult`; this view only reports the tap.
                    onSelect(task)
                    dismiss()
                } label: {
                    HStack(spacing: FlowSpacing.s) {
                        Circle().fill(task.colour.base).frame(width: 8, height: 8)
                        Text(task.title)
                        Spacer()
                        if task.id == current?.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(FlowTheme.accentText(scheme))
                        }
                    }
                }
                .foregroundStyle(FlowTheme.primaryText(scheme))
            }
            .searchable(text: $query, prompt: "Search tasks")
            .navigationTitle("Attach to task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Wraps chips onto as many lines as they need, so the row never becomes its
/// own horizontal scroll view at large Dynamic Type sizes. A local copy of
/// `FlowChrome.swift`'s private `FlowChipWrap` — that one is `private` to its
/// file and unreachable from here, and the T6 stage 2 spec calls for copying
/// it "in the same deliberately-local way" the existing chip views already
/// do, rather than loosening its access level.
private struct NoteAttachChipWrap: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
