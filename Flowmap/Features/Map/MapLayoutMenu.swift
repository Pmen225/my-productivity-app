import SwiftUI

/// The dark popover behind the map's "⋯" button — offers the two ways the
/// tree can fan out, with a clay tick beside whichever is active.
///
/// No shared `FlowPopoverMenu` component exists yet, so this mirrors
/// `ListEllipsisMenu`'s dark-popover styling directly (same `popoverSurface`
/// fill, row shape and divider) rather than reaching for a bare system `Menu`,
/// to match the reference's dark dropdown look.
public struct MapLayoutMenu: View {
    @Binding private var isPresented: Bool
    private let current: MapLayoutOrientation
    private let onSelect: (MapLayoutOrientation) -> Void

    public init(
        isPresented: Binding<Bool>,
        current: MapLayoutOrientation,
        onSelect: @escaping (MapLayoutOrientation) -> Void
    ) {
        self._isPresented = isPresented
        self.current = current
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(.leftToRight)
            divider
            row(.topDown)
        }
        .padding(.vertical, FlowSpacing.xs)
        .frame(width: 240)
        .background(FlowTheme.popoverSurface)
        .accessibilityElement(children: .contain)
    }

    private func row(_ orientation: MapLayoutOrientation) -> some View {
        Button {
            onSelect(orientation)
            isPresented = false
        } label: {
            HStack(spacing: FlowSpacing.s) {
                Image(systemName: orientation.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                Text(orientation.displayName)
                    .font(FlowFont.body)
                Spacer()
                if orientation == current {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FlowTheme.accent)
                }
            }
            .padding(.horizontal, FlowSpacing.m)
            .padding(.vertical, FlowSpacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(orientation.displayName)
        .accessibilityAddTraits(orientation == current ? .isSelected : [])
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, FlowSpacing.s)
    }
}
