import Testing
@testable import Flowmap

/// The Settings font option: persistence round-trip and safe fallbacks.
struct AppFontChoiceTests {
    @Test func rawValuesRoundTrip() {
        for choice in AppFontChoice.allCases {
            #expect(AppFontChoice(rawValue: choice.rawValue) == choice)
        }
    }

    @Test func settingsDefaultIsSystem() {
        let settings = AppSettings()
        #expect(settings.appFont == .system)
    }

    @Test func accessorPersistsRaw() {
        let settings = AppSettings()
        settings.appFont = .quattro
        #expect(settings.appFontRaw == "quattro")
        #expect(settings.appFont == .quattro)
        // The setter also drives the global token switch; put it back so no
        // other suite in this process renders the test's font choice.
        #expect(FlowFont.choice == .quattro)
        settings.appFont = .system
        #expect(FlowFont.choice == .system)
    }

    /// An unknown raw — an older build reading a newer record — must never
    /// crash or invent a face; it falls back to the system font.
    @Test func unknownRawFallsBackToSystem() {
        let settings = AppSettings()
        settings.appFontRaw = "papyrus"
        #expect(settings.appFont == .system)
    }
}
