import Foundation
import Testing
@testable import Flowmap

/// The gate and duel copy is the mock's, word for word. It lives in statics
/// precisely so a test can pin it — the strings drifted once already.
@MainActor
@Suite("Dialog and duel copy")
struct GateCopyTests {
    @Test("The plan gate explains why a definition of done is wanted")
    func planGateMessage() {
        #expect(
            PlanGateDialog.gateMessage
                == "Break it down. A clear checklist stops the endless tweaking."
        )
    }

    @Test("Blocking the start names what is missing")
    func planGateBlockedMessage() {
        #expect(PlanGateDialog.blockedMessage == "Add at least one subtask — that is your definition of done.")
    }

    @Test("A completed checklist names the exact start block")
    func completedChecklistBlockedMessage() {
        #expect(
            PlanGateDialog.allCompletedBlockedMessage
                == "Everything here is already ticked — un-tick or add what is left."
        )
    }

    @Test("The subtasks eyebrow carries the count")
    func subtasksEyebrowCount() {
        #expect(PlanGateDialog.subtasksEyebrow(count: 0) == "Subtasks · 0")
        #expect(PlanGateDialog.subtasksEyebrow(count: 3) == "Subtasks · 3")
    }

    @Test("The duel counts itself in words, and never past the total")
    func duelCounter() {
        #expect(PrioritiseDuelView.duelCounter(index: 0, total: 5) == "1 of 5")
        #expect(PrioritiseDuelView.duelCounter(index: 4, total: 5) == "5 of 5")
        #expect(PrioritiseDuelView.duelCounter(index: 5, total: 5) == "5 of 5")
    }

    @Test("An initiative is asked for by example, the other kinds by name")
    func namePlaceholders() {
        #expect(FlowCreateKind.task.namePlaceholder == "Task name…")
        #expect(FlowCreateKind.project.namePlaceholder == "Project name…")
        #expect(FlowCreateKind.initiative.namePlaceholder == "Goal — e.g. \"Ship my portfolio\"")
    }

    @Test("Only the container kinds explain themselves")
    func kindExplanations() {
        #expect(FlowCreateKind.task.explanation == nil)
        #expect(
            FlowCreateKind.project.explanation
                == "A project becomes a branch on your map. Attached projects feed the initiative's XP and goal bar."
        )
        #expect(
            FlowCreateKind.initiative.explanation
                == "An initiative is the goal at the root of your map. Projects and tasks under it feed its XP — finish them all to complete it."
        )
    }
}
