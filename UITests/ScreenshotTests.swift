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

    /// The compulsory planning gate: every seeded demo task starts
    /// unplanned, so the first "Start focus" tap on a fresh demo always
    /// opens the Definition of Done modal rather than starting the clock.
    func testCaptureGate() {
        let app = launch()
        if tapTab(app, "Focus") {
            let startButton = app.buttons["Start focus"].firstMatch
            if startButton.waitForExistence(timeout: 8) {
                startButton.tap()
                let definitionField = app.textFields["Definition of done"].firstMatch
                if definitionField.waitForExistence(timeout: 5) {
                    Thread.sleep(forTimeInterval: 1)
                    capture(app, named: "iphone-focus-gate")
                } else {
                    XCTFail("Plan gate did not appear after Start focus")
                }
            } else {
                XCTFail("Start focus button not found")
            }
        }
    }

    /// Adds one quick task from the Inbox screen's own "Add task" control, so
    /// the prioritise duel screenshot never depends on how many demo tasks
    /// the auto-plan at launch happened to leave sitting in the Inbox.
    private func addQuickTask(_ app: XCUIApplication, title: String) {
        let addButton = app.buttons["Add task"].firstMatch
        guard addButton.waitForExistence(timeout: 5) else {
            XCTFail("Add task button not found")
            return
        }
        addButton.tap()
        Thread.sleep(forTimeInterval: 0.5)
        let field = app.textFields["Task name…"].firstMatch
        guard field.waitForExistence(timeout: 5) else {
            XCTFail("Quick-add title field not found")
            return
        }
        field.tap()
        // The quick-add field keeps whatever the previous add left in it, so
        // typing straight in concatenates the two titles — the duel reveal
        // once showed a task literally named "Duel candidate ADuel candidate B".
        if let existing = field.value as? String, !existing.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText(title)
        field.typeText("\n")
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// The prioritise duel: reached from the Inbox listing (Library → Inbox),
    /// not a dedicated Plan screen — see `PrioritiseDuelView`'s header
    /// comment for why. Answers every duel by always taking the first
    /// offered choice, then captures the medal-ranked reveal.
    func testCapturePrioritiseDuel() {
        let app = launch()
        guard tapTab(app, "Library") else { return }

        let inboxRow = app.buttons["Inbox"].firstMatch
        guard inboxRow.waitForExistence(timeout: 8) else {
            XCTFail("Inbox row not found in Library")
            return
        }
        inboxRow.tap()
        Thread.sleep(forTimeInterval: 2)

        // The demo's auto-plan at launch can leave the Inbox with fewer than
        // two tasks, which hides the duel entry entirely — top up with two
        // fresh ones so the entry point is guaranteed regardless.
        addQuickTask(app, title: "Duel candidate A")
        addQuickTask(app, title: "Duel candidate B")

        let playButton = app.buttons["Play the prioritise game"].firstMatch
        guard playButton.waitForExistence(timeout: 8) else {
            XCTFail("Prioritise duel entry not found — inbox may hold fewer than two tasks")
            return
        }
        playButton.tap()
        Thread.sleep(forTimeInterval: 1.5)
        capture(app, named: "iphone-prioritise-duel")

        // Every choice button's accessibility label starts "Put … ahead of
        // …"; always taking the first one offered clears every pair without
        // needing to know the demo's exact task count in advance.
        let choicePredicate = NSPredicate(format: "label BEGINSWITH 'Put '")
        var remainingTaps = 30
        while remainingTaps > 0 {
            let choice = app.buttons.matching(choicePredicate).firstMatch
            guard choice.waitForExistence(timeout: 3) else { break }
            choice.tap()
            Thread.sleep(forTimeInterval: 0.3)
            remainingTaps -= 1
        }

        Thread.sleep(forTimeInterval: 1.5)
        capture(app, named: "iphone-prioritise-duel-reveal")

        let keepOrder = app.buttons["Keep order, plan later"].firstMatch
        if keepOrder.waitForExistence(timeout: 5) {
            keepOrder.tap()
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
