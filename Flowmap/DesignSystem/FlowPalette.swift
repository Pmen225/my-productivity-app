import Foundation
import SwiftUI

fileprivate extension Color {
    init(paletteHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Whether this theme paints task colours as MindNode-style pastels or as
/// Flowmap's original saturated set. Two sets, not one per theme — a theme is
/// still five hexes plus this flag.
public enum NodeStyle: String, Sendable { case pastel, vivid }

/// A named background + accent pair the user picks in Settings. Everything else
/// in `FlowTheme` is derived or shared, so a theme is five hexes, not a fork of
/// the design system.
public struct FlowPalette: Identifiable, Hashable, Sendable {
    public let id: String        // persisted raw string
    public let name: String      // shown under the tile
    let bgLight: UInt32, bgDark: UInt32
    let surfaceLight: UInt32, surfaceDark: UInt32
    let sunkenLight: UInt32, sunkenDark: UInt32
    let wellLight: UInt32, wellDark: UInt32
    let accent: UInt32, accentFill: UInt32, accentDeep: UInt32
    let accentTextLight: UInt32, accentTextDark: UInt32
    public let nodeStyle: NodeStyle

    public static let minimal = FlowPalette(
        id: "minimal", name: "OpenAI",
        bgLight: 0xFFFFFF, bgDark: 0x212121,
        surfaceLight: 0xFFFFFF, surfaceDark: 0x2F2F2F,
        sunkenLight: 0xF3F3F3, sunkenDark: 0x303030,
        wellLight: 0xE8E8E8, wellDark: 0x424242,
        accent: 0x0D0D0D, accentFill: 0x0D0D0D, accentDeep: 0x0D0D0D,
        accentTextLight: 0x0D0D0D, accentTextDark: 0xF8F8F8,
        nodeStyle: .pastel
    )

    public static let clay = FlowPalette(
        id: "clay", name: "Clay",
        bgLight: 0xEFE7DA, bgDark: 0x171310,
        surfaceLight: 0xFFFFFF, surfaceDark: 0x2E2721,
        sunkenLight: 0xEBE1D2, sunkenDark: 0x201B17,
        wellLight: 0xE5DAC7, wellDark: 0x3A322A,
        accent: 0xC25518, accentFill: 0xB84E18, accentDeep: 0x9E4410,
        accentTextLight: 0x9E4410, accentTextDark: 0xE0834F,
        nodeStyle: .vivid
    )

    public static let rainbow = FlowPalette(
        id: "rainbow", name: "Rainbow",
        bgLight: 0xF2F2F2, bgDark: 0x141414,
        surfaceLight: 0xFFFFFF, surfaceDark: 0x1E1E1E,
        sunkenLight: 0xEAE8F0, sunkenDark: 0x191919,
        wellLight: 0xDFDCEC, wellDark: 0x2A2A2A,
        accent: 0x6B4BC4, accentFill: 0x5E40B4, accentDeep: 0x50359C,
        accentTextLight: 0x50359C, accentTextDark: 0xA98CF0,
        nodeStyle: .pastel
    )

    public static let beach = FlowPalette(
        id: "beach", name: "Beach Day",
        bgLight: 0xFBF5EC, bgDark: 0x141414,
        surfaceLight: 0xFFFFFF, surfaceDark: 0x1E1E1E,
        sunkenLight: 0xF1E9DC, sunkenDark: 0x191919,
        wellLight: 0xE7DCCB, wellDark: 0x2A2A2A,
        accent: 0x2E9E92, accentFill: 0x27897E, accentDeep: 0x1F6F66,
        accentTextLight: 0x1F6F66, accentTextDark: 0x5FCFC2,
        nodeStyle: .pastel
    )

    public static let tropical = FlowPalette(
        id: "tropical", name: "Tropical",
        bgLight: 0xF3F6F4, bgDark: 0x141414,
        surfaceLight: 0xFFFFFF, surfaceDark: 0x1E1E1E,
        sunkenLight: 0xE7EDE9, sunkenDark: 0x191919,
        wellLight: 0xDCE5DF, wellDark: 0x2A2A2A,
        accent: 0x3E8E5A, accentFill: 0x357C4E, accentDeep: 0x2B6740,
        accentTextLight: 0x2B6740, accentTextDark: 0x74C48E,
        nodeStyle: .pastel
    )

    /// Presented in this order in the Settings theme grid.
    public static let all: [FlowPalette] = [.minimal, .clay, .rainbow, .beach, .tropical]

    /// A fresh install is neutral grey, not cream.
    public static let `default` = minimal

    public static func named(_ id: String) -> FlowPalette {
        all.first { $0.id == id } ?? .minimal
    }

    // MARK: - Theme tile colours

    /// Colour swatches the Settings theme grid previews — never used by the
    /// app's own painted surfaces, which read `FlowTheme.palette` instead.
    public var bgLightColor: Color { Color(paletteHex: bgLight) }
    public var bgDarkColor: Color { Color(paletteHex: bgDark) }
    public var surfaceLightColor: Color { Color(paletteHex: surfaceLight) }
    public var accentColor: Color { Color(paletteHex: accent) }
    public var accentFillColor: Color { Color(paletteHex: accentFill) }
    public var accentDeepColor: Color { Color(paletteHex: accentDeep) }
}
