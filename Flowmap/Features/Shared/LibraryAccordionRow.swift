import SwiftUI

/// Plan page's expand-in-place row.
///
/// A native `DisclosureGroup` wearing the mockup's skin, rather than a
/// hand-rolled open/closed row: the expanded/collapsed VoiceOver trait comes
/// free with the native control, where a bespoke toggle would have
/// re-implemented it — or dropped it. See the T6 rulings in
/// `state/specs/parity-audit.md`.
struct LibraryAccordionRow<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let symbol: String
    let token: ColourToken
    /// `nil` renders no count at all — the mockup's Stats row deliberately has none.
    let count: Int?
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
        } label: {
            header
        }
        .disclosureGroupStyle(FlowAccordionStyle(reduceMotion: reduceMotion))
    }

    /// Matches the mockup's row (`libBodyEl:947-955`) inside the native control.
    private var header: some View {
        HStack(spacing: FlowSpacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: FlowRadius.tile, style: .continuous)
                    .fill(token.soft)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(token.onSoft)
            }
            .frame(width: 27, height: 27)

            Text(title)
                .font(FlowFont.body.weight(.semibold))
                .foregroundStyle(FlowTheme.primaryText(scheme))

            Spacer(minLength: FlowSpacing.s)

            if let count {
                Text("\(count)")
                    .font(FlowFont.caption.weight(.semibold))
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
            }

            // The mockup's `▸`, rotating 90° open — the HIG's own disclosure-
            // triangle convention (points along the leading edge closed, down
            // when open).
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        // Whole row toggles, not just the chevron — sized to the 44pt floor
        // plus its own padding, not clipped to it, so the hit target isn't
        // cut down to the artwork the way a clipped collapsed card was.
        .padding(.vertical, FlowSpacing.xs)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

/// The mockup's skin over `DisclosureGroup`'s structure: no system disclosure
/// indicator (the header already draws its own rotating chevron), unfolded
/// content laid out as plain rows rather than a second bordered container —
/// HIG *Boxes*: nested boxes to mark subgroups "can make your interface feel
/// busy". Reduce Motion drops the expand/collapse straight to its end state,
/// matching the convention `CalendarRootView`/`MapTodayScreen` already use.
struct FlowAccordionStyle: DisclosureGroupStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if reduceMotion {
                    configuration.isExpanded.toggle()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        configuration.isExpanded.toggle()
                    }
                }
            } label: {
                configuration.label
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}
