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

    /// Pick a wheel visibility chip by its accessibility label. The chip's own
    /// text is a bare "2" or "All", which collides with other content, so the
    /// spoken label is queried instead.
    private func selectWheelMode(_ app: XCUIApplication, _ mode: String) {
        let chip = app.buttons["\(mode) tasks visible"].firstMatch
        guard chip.waitForExistence(timeout: 10) else {
            XCTFail("Wheel mode chip \(mode) not found")
            return
        }
        chip.tap()
        Thread.sleep(forTimeInterval: 2.5)
    }

    private func tapTab(_ app: XCUIApplication, _ label: String) -> Bool {
        // The tab bar is the custom glass FlowTabBar, not a system tab bar, so
        // its items surface as plain buttons. Fall back for the Mac idiom.
        var button = app.buttons[label].firstMatch
        if !button.waitForExistence(timeout: 10) {
            button = app.tabBars.buttons[label]
            guard button.waitForExistence(timeout: 5) else {
                XCTFail("Tab \(label) not found")
                return false
            }
        }
        button.tap()
        Thread.sleep(forTimeInterval: 2.5)
        return true
    }

    func testCaptureEveryRequiredScreen() {
        let app = launch()

        capture(app, named: "iphone-today")

        // The create sheet — the design's "New" sheet off the + FAB.
        let fab = app.buttons["New task, project or initiative"].firstMatch
        if fab.waitForExistence(timeout: 5) {
            fab.tap()
            Thread.sleep(forTimeInterval: 2)
            capture(app, named: "iphone-new-sheet")
            let close = app.buttons["Close"].firstMatch
            if close.exists { close.tap() } else { app.swipeDown() }
            Thread.sleep(forTimeInterval: 1.5)
        }

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
            // The wheel mode is persisted in settings and survives a re-seed,
            // so without choosing one here the shot silently captures whichever
            // dial the previous run happened to leave selected.
            selectWheelMode(app, "All")
            capture(app, named: "iphone-focus-wheel")

            selectWheelMode(app, "2")
            capture(app, named: "iphone-focus-wheel-close")

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

            let monthMode = app.buttons["Month"].firstMatch
            if monthMode.waitForExistence(timeout: 5) {
                monthMode.tap()
                Thread.sleep(forTimeInterval: 2)
                capture(app, named: "iphone-calendar-month")
            } else {
                XCTFail("Month mode control not found")
            }
        }

        if tapTab(app, "Library") {
            capture(app, named: "iphone-library")

            let progress = app.buttons["Progress"].firstMatch
            if progress.waitForExistence(timeout: 5) {
                progress.tap()
                Thread.sleep(forTimeInterval: 2)
                capture(app, named: "iphone-stats")
                app.navigationBars.buttons.firstMatch.tap()
                Thread.sleep(forTimeInterval: 1)
            }

            let settings = app.buttons["Settings"].firstMatch
            if settings.waitForExistence(timeout: 5) {
                settings.tap()
                Thread.sleep(forTimeInterval: 2)
                capture(app, named: "iphone-settings")
                app.navigationBars.buttons.firstMatch.tap()
                Thread.sleep(forTimeInterval: 1)
            }

            let notes = app.buttons["Notes"].firstMatch
            if notes.waitForExistence(timeout: 5) {
                notes.tap()
                Thread.sleep(forTimeInterval: 2.5)
                capture(app, named: "iphone-notes")
                app.navigationBars.buttons.firstMatch.tap()
                Thread.sleep(forTimeInterval: 1)
            }

            let assistant = app.buttons["Assistant"].firstMatch
            if assistant.waitForExistence(timeout: 5) {
                assistant.tap()
                Thread.sleep(forTimeInterval: 2)
                capture(app, named: "iphone-assistant")
            }
        }
    }

    /// Dark-scheme passes of the two signature screens, via the legacy
    /// interface-style launch override (the in-app Appearance control is a
    /// scroll-wheel the test cannot reliably drive).
    func testCaptureDarkModeScreens() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapSeedDemo", "-flowmapDemoDark"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        Thread.sleep(forTimeInterval: 4)

        capture(app, named: "iphone-today-dark")
        // Hop via Map first: on Today a demo task titled "Focus" sits in the
        // timeline and steals the firstMatch from the tab of the same name.
        if tapTab(app, "Map"), tapTab(app, "Focus") {
            capture(app, named: "iphone-focus-wheel-dark")
        }
    }
}
