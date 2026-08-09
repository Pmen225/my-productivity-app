import SwiftUI
import Testing
@testable import Flowmap

/// `MapPalette` is MindNode's own fixed colour system for the map canvas
/// (Task 63 pass 1) — values borrowed verbatim from MindNodeClone's shipping
/// code, not the app-wide `ColourToken` pastels. These tests pin the
/// rotation and the luminance-gated ink so a future edit can't silently
/// drift from the clone.
struct MapPaletteTests {

    // MARK: - Branch rotation (ThemeCard.swift:23-36, leftColors + rightColors)

    @Test("branchColour rotates orange, blue, purple, yellow by root-child index, and wraps past 4")
    func branchColourRotatesAndWraps() {
        let orange = Color(red: 232 / 255, green: 153 / 255, blue: 105 / 255)
        let blue = Color(red: 117 / 255, green: 166 / 255, blue: 216 / 255)
        let purple = Color(red: 122 / 255, green: 87 / 255, blue: 151 / 255)
        let yellow = Color(red: 247 / 255, green: 210 / 255, blue: 89 / 255)

        #expect(MapPalette.branchColour(rootChildIndex: 0) == orange)
        #expect(MapPalette.branchColour(rootChildIndex: 1) == blue)
        #expect(MapPalette.branchColour(rootChildIndex: 2) == purple)
        #expect(MapPalette.branchColour(rootChildIndex: 3) == yellow)
        // Wraps: index 4 is a second orange branch, not a fifth new hue —
        // MindNode's palette is 4 colours flat, however many top-level
        // branches the map actually has.
        #expect(MapPalette.branchColour(rootChildIndex: 4) == orange)
        #expect(MapPalette.branchColour(rootChildIndex: 5) == blue)
        #expect(MapPalette.branchColour(rootChildIndex: 6) == purple)
        #expect(MapPalette.branchColour(rootChildIndex: 7) == yellow)
    }

    // MARK: - Title ink luminance gate (EditableNodeLabel.titleColor:306)

    @Test("titleInk flips to white on the dark purple branch fill")
    func titleInkWhiteOnDarkFill() {
        let purple = Color(red: 122 / 255, green: 87 / 255, blue: 151 / 255)
        #expect(MapPalette.titleInk(on: purple) == .white)
    }

    @Test("titleInk drops to near-black on the light yellow branch fill")
    func titleInkBlackOnLightFill() {
        let yellow = Color(red: 247 / 255, green: 210 / 255, blue: 89 / 255)
        #expect(MapPalette.titleInk(on: yellow) == Color.black.opacity(0.95))
    }
}
