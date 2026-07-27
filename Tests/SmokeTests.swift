import Foundation
import Testing
@testable import Flowmap

@Suite("Duration formatting")
struct DurationFormatterTests {
    @Test("Compact labels match the product's duration vocabulary")
    func compactLabels() {
        #expect(DurationFormatter.compact(minutes: 15) == "15M")
        #expect(DurationFormatter.compact(minutes: 30) == "30M")
        #expect(DurationFormatter.compact(minutes: 45) == "45M")
        #expect(DurationFormatter.compact(minutes: 60) == "1H")
        #expect(DurationFormatter.compact(minutes: 90) == "1H 30M")
    }

    @Test("Countdown pads seconds and only shows hours when needed")
    func countdownLabels() {
        #expect(DurationFormatter.countdown(seconds: 1476) == "24:36")
        #expect(DurationFormatter.countdown(seconds: 9) == "0:09")
        #expect(DurationFormatter.countdown(seconds: 3849) == "1:04:09")
    }
}
