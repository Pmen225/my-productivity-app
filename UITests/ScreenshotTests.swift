import XCTest

/// Drives the app to each screen the spec asks to see and attaches a screenshot.
///
/// Run with:
/// ```
/// xcodebuild -scheme Flowmap -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///   -only-testing:FlowmapUITests/ScreenshotTests test
/// ```
/// then extract the attachments from the resulting `.xcresult`.
@MainActor
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapSeedDemo"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        // Let the seed and the first plan settle before photographing anything.
        Thread.sleep(forTimeInterval: 4)
        return app
    }

    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapTab(_ app: XCUIApplication, _ label: String) -> Bool {
        let button = app.tabBars.buttons[label]
        guard button.waitForExistence(timeout: 10) else { return false }
        button.tap()
        Thread.sleep(forTimeInterval: 2.5)
        return true
    }

    func testCaptureEveryRequiredScreen() {
        let app = launch()

        capture(app, named: "iphone-today")

        if tapTab(app, "Map") {
            capture(app, named: "iphone-map")
            // The demo workspace ships one map; opening it shows the canvas.
            let weeklyPlan = app.staticTexts["Weekly Plan"].firstMatch
            if weeklyPlan.waitForExistence(timeout: 8) {
                weeklyPlan.tap()
                Thread.sleep(forTimeInterval: 4)
                capture(app, named: "iphone-map-canvas")
            } else {
                XCTFail("Could not open a map from the map list")
            }
        }

        if tapTab(app, "Focus") {
            capture(app, named: "iphone-focus-wheel")

            // Drag the lower card up. Window-relative coordinates are used
            // because the grab handle itself is not a hit-testable element.
            let window = app.windows.firstMatch
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.74))
            let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
            start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 3)
            capture(app, named: "iphone-focus-card-expanded")
        }

        if tapTab(app, "Calendar") {
            capture(app, named: "iphone-calendar")
        }

        if tapTab(app, "Library") {
            capture(app, named: "iphone-library")

            let notes = app.buttons["Notes"].firstMatch
            if notes.waitForExistence(timeout: 5) {
                notes.tap()
                Thread.sleep(forTimeInterval: 2.5)
                capture(app, named: "iphone-notes")
            }
        }
    }
}
