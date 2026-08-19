import SwiftUI

/// Row of colour swatches shared by every colour-storing model's editor
/// (Task, Project, Initiative, Note, List) — one implementation instead of
/// several near-identical inline `ForEach(ColourToken...)` rows.
public struct FlowColourPicker: View {
    @Binding private var selection: ColourToken
    private let tokens: [ColourToken]
    private let diameter: CGFloat
    private let scrollable: Bool

    public init(
        selection: Binding<ColourToken>,
        tokens: [ColourToken] = ColourToken.taskTokens,
        diameter: CGFloat = 22,
        scrollable: Bool = false
    ) {
        self._selection = selection
        self.tokens = tokens
        self.diameter = diameter
        self.scrollable = scrollable
    }

    public var body: some View {
        if scrollable {
            ScrollView(.horizontal, showsIndicators: false) {
                swatches
                    .padding(.horizontal, FlowSpacing.xs)
                    .padding(.vertical, FlowSpacing.xs)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                swatches
                wrappedSwatches
            }
        }
    }

    private var swatches: some View {
        HStack(spacing: scrollable ? FlowSpacing.xxs : FlowSpacing.s) {
            ForEach(tokens, id: \.self) { token in
                swatch(token)
            }
        }
    }

    /// A balanced fallback for compact editor rows. Eight 44pt targets cannot
    /// fit in one iPhone Form row, so wrapping keeps every colour visible
    /// instead of presenting a deliberately clipped horizontal strip.
    private var wrappedSwatches: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 44), spacing: FlowSpacing.s), count: 4),
            spacing: FlowSpacing.xs
        ) {
            ForEach(tokens, id: \.self) { token in
                swatch(token)
            }
        }
    }

    private func swatch(_ token: ColourToken) -> some View {
        Button {
            selection = token
        } label: {
            Circle()
                .fill(token.base)
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle().strokeBorder(.primary, lineWidth: selection == token ? 2 : 0)
                )
        }
        .buttonStyle(FlowNavigationRowPressStyle())
        .flowHitTarget()
        .accessibilityLabel(token.displayName)
        .accessibilityValue(selection == token ? "Selected" : "")
        .accessibilityAddTraits(selection == token ? .isSelected : [])
    }
}
