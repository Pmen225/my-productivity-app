import XCTest

final class AssistantTaskHarnessTests: XCTestCase {
    @MainActor
    func testAssistantCreatesAndCancelsSampleTask() {
        let taskTitle = "Harness task \(UUID().uuidString.prefix(8))"
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapSeedDemo", "-flowmapOpenAIHarness"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        openAssistant(app)
        let localCommands = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Local commands only")
        ).firstMatch
        XCTAssertTrue(localCommands.waitForExistence(timeout: 8), "Harness requires the deterministic local-command Assistant path")

        send("add \(taskTitle) for 30 min", in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Created \"\(taskTitle)\"")).firstMatch.waitForExistence(timeout: 8))
        capture(app, "assistant-task-01-created")

        send("cancel \(taskTitle)", in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Cancelled \"\(taskTitle)\"")).firstMatch.waitForExistence(timeout: 8))
        capture(app, "assistant-task-02-cancelled")
    }

    @MainActor
    private func openAssistant(_ app: XCUIApplication) {
        let menu = app.buttons["Open library"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 8))
        menu.tap()
        let assistant = app.buttons["Assistant"].firstMatch
        guard assistant.waitForExistence(timeout: 5) else {
            XCTFail("Existing Assistant drawer route is missing")
            return
        }
        assistant.tap()
        XCTAssertTrue(app.navigationBars["Assistant"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func send(_ text: String, in app: XCUIApplication) {
        let field = app.textFields["Message, or tap the mic…"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
        app.buttons["Send"].firstMatch.tap()
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
