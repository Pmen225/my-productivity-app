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
                    .padding(.vertical, FlowSpacing.xs)
            }
        } else {
            swatches
        }
    }

    private var swatches: some View {
        // Eight 44pt hit targets still fit on a phone when the visible dots use
        // the tight swatch rhythm. The old 12pt gap clipped the final colour,
        // making a complete palette look accidentally cut off.
        HStack(spacing: scrollable ? FlowSpacing.xxs : FlowSpacing.s) {
            ForEach(tokens, id: \.self) { token in
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
                .buttonStyle(.plain)
                // Keep the visible swatch quiet while meeting the iOS 44pt
                // touch target. The previous 22pt AX frame was half Apple's
                // minimum and made colour selection unnecessarily fiddly.
                .flowHitTarget()
                .accessibilityLabel(token.displayName)
                .accessibilityValue(selection == token ? "Selected" : "")
                .accessibilityAddTraits(selection == token ? .isSelected : [])
            }
        }
    }
}
