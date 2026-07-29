import Foundation
import Testing
@testable import Flowmap

/// The delete card's copy is the mock's, word for word, so it is worth pinning.
@MainActor
@Suite("Delete confirmation copy")
struct DeleteConfirmationTests {
    @Test("A branch says what comes off with it")
    func branchMessage() {
        #expect(
            FlowDeleteMessage.text(hasChildren: true)
                == "The project and its tasks come off the map, schedule and inbox."
        )
    }

    @Test("A leaf item speaks only for itself")
    func itemMessage() {
        #expect(
            FlowDeleteMessage.text(hasChildren: false)
                == "It comes off the map, schedule and inbox."
        )
    }
}
