import Foundation
import Testing
@testable import Flowmap

/// The unresolved-gate reminder is pure timing, and the speech it produces
/// leaves nothing to assert on, so the stamp it keeps is what gets pinned.
@MainActor
struct GateNagTests {
    private func settings() -> AppSettings {
        let settings = AppSettings()
        settings.focusVoiceEnabled = false  // the banner path, not the speech
        return settings
    }

    @Test func theFirstCallOnlyStartsTheClock() {
        let service = FocusVoiceService()
        let start = Date(timeIntervalSince1970: 0)
        service.nagUnresolvedGate(now: start, settings: settings())
        #expect(service.lastGateNagAt == start)
    }

    @Test func itStaysQuietUntilTheIntervalHasPassed() {
        let service = FocusVoiceService()
        let start = Date(timeIntervalSince1970: 0)
        service.nagUnresolvedGate(now: start, settings: settings())
        service.nagUnresolvedGate(now: start.addingTimeInterval(17), settings: settings())
        #expect(service.lastGateNagAt == start)
    }

    @Test func itRepeatsOnceTheIntervalHasPassed() {
        let service = FocusVoiceService()
        let start = Date(timeIntervalSince1970: 0)
        let later = start.addingTimeInterval(FocusVoiceService.gateNagInterval)
        service.nagUnresolvedGate(now: start, settings: settings())
        service.nagUnresolvedGate(now: later, settings: settings())
        #expect(service.lastGateNagAt == later)
    }

    @Test func resolvingTheGateLetsTheNextOneStartItsOwnClock() {
        let service = FocusVoiceService()
        service.nagUnresolvedGate(now: Date(timeIntervalSince1970: 0), settings: settings())
        service.gateResolved()
        #expect(service.lastGateNagAt == nil)
    }
}
