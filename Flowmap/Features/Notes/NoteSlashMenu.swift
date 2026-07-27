import SwiftUI

/// Inline "type `/` on an empty block" menu for switching that block's type.
///
/// Deliberately a plain vertical list rather than a `Menu`/popover: it needs to
/// sit right under the block being typed into and stay keyboard-navigable
/// while the text field above it keeps focus.
struct NoteSlashMenu: View {
    @Environment(\.colorScheme) private var scheme
    let onSelect: (NoteBlockType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(NoteBlockType.allCases, id: \.self) { type in
                Button {
                    onSelect(type)
                } label: {
                    HStack(spacing: FlowSpacing.s) {
                        Image(systemName: type.symbolName)
                            .frame(width: 18)
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                        Text(type.displayName)
                            .font(FlowFont.secondary)
                            .foregroundStyle(FlowTheme.primaryText(scheme))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, FlowSpacing.s)
                    .padding(.vertical, FlowSpacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, FlowSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                .fill(FlowTheme.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                .strokeBorder(FlowTheme.separator(scheme), lineWidth: 1)
        )
        .shadow(color: FlowTheme.shadow(scheme), radius: 8, y: 2)
    }
}
