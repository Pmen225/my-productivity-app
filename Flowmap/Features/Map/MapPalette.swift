import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The map canvas's own colour system — MindNode's fixed palette (Task 63
/// pass 1), never the app-wide `ColourToken` pastels a task carries
/// everywhere else. A task's `colourToken` keeps flowing into
/// `MapNode.colourToken` unchanged for the rest of the app; only the CANVAS
/// stops reading it for node fill/text.
///
/// Every value here is borrowed verbatim from MindNodeClone's shipping code
/// (never reconstructed from memory) — see each function's doc comment for
/// its exact source file and line.
public enum MapPalette {
    /// `DesignSystem.swift:84-91` (`DS.canvas`), verbatim.
    public static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.13, green: 0.13, blue: 0.15)
            : Color(red: 237 / 255, green: 237 / 255, blue: 242 / 255) // #EDEDF2
    }

    /// The root pill's own tokens — deliberately distinct from
    /// `FlowTheme.mapRootFill`/`mapRootText`, whose values are the app's OLD
    /// root treatment (inverse-of-scheme anchor). MindNode's own default
    /// theme root is `ThemeCard.centerColor` (white) / `centerTextColor`.
    public static func rootFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255) : .white // #2C2C2E
    }

    public static func rootText(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 242 / 255, green: 242 / 255, blue: 244 / 255) // #F2F2F4
            : Color(red: 43 / 255, green: 43 / 255, blue: 46 / 255) // #2B2B2E
    }

    /// `ThemeCard.swift:23-36`, "MindNode Default" — `leftColors +
    /// rightColors`, verbatim order. Inherited FLAT by the whole branch
    /// subtree: no depth variant of any colour.
    private static let branchPalette: [Color] = [
        Color(red: 232 / 255, green: 153 / 255, blue: 105 / 255), // orange #E89969
        Color(red: 117 / 255, green: 166 / 255, blue: 216 / 255), // blue   #75A6D8
        Color(red: 122 / 255, green: 87 / 255, blue: 151 / 255), // purple #7A5797
        Color(red: 247 / 255, green: 210 / 255, blue: 89 / 255), // yellow #F7D259
    ]

    /// `rootChildIndex` is the depth-1 ancestor's `sortOrder`
    /// (`AutoMapBuilder` already assigns that as the branch's position among
    /// its siblings). Rotates past 4 — indices 0-7 map
    /// orange,blue,purple,yellow,orange,blue,purple,yellow.
    public static func branchColour(rootChildIndex: Int) -> Color {
        let count = branchPalette.count
        let index = ((rootChildIndex % count) + count) % count
        return branchPalette[index]
    }

    /// `EditableNodeLabel.titleColor` (`:306`), ported verbatim: fills darker
    /// than the 0.58 brightness threshold flip to white ink, everything else
    /// drops to near-black — MindNode keeps full ink on every fill at every
    /// depth, never a softened grey.
    public static func titleInk(on fill: Color) -> Color {
        brightness(of: fill) < 0.58 ? .white : Color.black.opacity(0.95)
    }

    /// Same brightness formula as the clone: `r*0.299 + g*0.587 + b*0.114`
    /// over the fill's sRGB components.
    private static func brightness(of color: Color) -> Double {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        #if canImport(UIKit)
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
        let native = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        native.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return Double(r) * 0.299 + Double(g) * 0.587 + Double(b) * 0.114
    }
}
