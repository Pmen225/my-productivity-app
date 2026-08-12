import Foundation
import Testing
@testable import Flowmap

/// `@MainActor` because `FlowDurationWheel` is a `View`, so its statics are
/// main-actor isolated.
@MainActor
@Suite("Duration wheel")
struct DurationWheelTests {
    private var options: [Int] { FlowDurationWheel.defaultOptions }

    @Test("Five-minute steps from 5M to 2H")
    func fiveMinuteSteps() {
        #expect(options.first == 5)
        #expect(options.last == 120)
        #expect(options.count == 24)
        #expect(options == options.sorted())
    }

    @Test("Stepping moves one option at a time")
    func stepsOne() {
        #expect(FlowDurationWheel.stepped(from: 30, by: 1, in: options) == 35)
        #expect(FlowDurationWheel.stepped(from: 30, by: -1, in: options) == 25)
    }

    @Test("Stepping clamps at both ends")
    func clamps() {
        #expect(FlowDurationWheel.stepped(from: 5, by: -1, in: options) == 5)
        #expect(FlowDurationWheel.stepped(from: 120, by: 1, in: options) == 120)
    }

    @Test("A value outside the options snaps to the nearest one")
    func snapsToNearest() {
        // A task saved at 32 matches no row, so the wheel would open on
        // nothing; 32 is nearer 30 than 35, so it settles on 30.
        #expect(FlowDurationWheel.stepped(from: 32, by: 0, in: options) == 30)
        #expect(FlowDurationWheel.stepped(from: 32, by: 1, in: options) == 35)
    }

    @Test("An empty option set leaves the value alone")
    func emptyOptions() {
        #expect(FlowDurationWheel.stepped(from: 30, by: 1, in: []) == 30)
    }
}
