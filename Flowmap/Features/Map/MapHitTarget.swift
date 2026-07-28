import SwiftUI

extension View {
    /// Apple HIG override (see project report, override 1 of 2): guarantees a
    /// 44×44pt minimum tap/click region around a control that draws smaller —
    /// the mock's floating controls, pill badges and "⋯" button are all
    /// thinner than that on screen. Grows the hit region symmetrically so the
    /// visible control stays exactly where it was drawn.
    func mapMinimumHitTarget(_ dimension: CGFloat = 44) -> some View {
        frame(minWidth: dimension, minHeight: dimension)
            .contentShape(Rectangle())
    }
}
