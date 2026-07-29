import Foundation
import Testing
@testable import Flowmap

/// `@MainActor` because `FlowDurationWheel` is a `View`, so its statics are
/// main-actor isolated.
@MainActor
@Suite("Duration wheel")
struct DurationWheelTests {
    private var options: [Int] { FlowDurationWheel.defaultOptions }

    @Test("The mockup's eight options, in order")
    func mockupOptions() {
        #expect(options == [15, 20, 25, 30, 45, 60, 90, 120])
    }

    @Test("Stepping moves one option at a time")
    func stepsOne() {
        #expect(FlowDurationWheel.stepped(from: 30, by: 1, in: options) == 45)
        #expect(FlowDurationWheel.stepped(from: 30, by: -1, in: options) == 25)
    }

    @Test("Stepping clamps at both ends")
    func clamps() {
        #expect(FlowDurationWheel.stepped(from: 15, by: -1, in: options) == 15)
        #expect(FlowDurationWheel.stepped(from: 120, by: 1, in: options) == 120)
    }

    @Test("A value outside the options snaps to the nearest one")
    func snapsToNearest() {
        // 35 sits between 30 and 45, closer to 30, so stepping up lands on 45.
        #expect(FlowDurationWheel.stepped(from: 35, by: 1, in: options) == 45)
        #expect(FlowDurationWheel.stepped(from: 35, by: 0, in: options) == 30)
    }

    @Test("An empty option set leaves the value alone")
    func emptyOptions() {
        #expect(FlowDurationWheel.stepped(from: 30, by: 1, in: []) == 30)
    }
}
