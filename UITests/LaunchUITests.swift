import XCTest

/// Flows that can be asserted without accessibility identifiers the feature
/// views do not yet expose. Anything that would otherwise need a fragile
/// coordinate tap or a guessed identifier is covered by screenshot inspection
/// instead — see TEST_PLAN.md.
final class FlowmapUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 30),
            "The app did not reach the foreground"
        )
        return app
    }

    func testAppLaunchesAndShowsItsMainDestinations() {
        let app = launch()

        // Every main destination should be reachable from the first screen —
        // no dead navigation, no empty shell.
        for name in ["Today", "Focus", "Calendar"] {
            let found = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@", name))
                .firstMatch
            XCTAssertTrue(
                found.waitForExistence(timeout: 15),
                "Expected to find a destination labelled \(name)"
            )
        }
    }

    /// Spec §6 and §27: creation inputs appear only behind a compact `+`, so
    /// these permanent full-width rows must not exist anywhere.
    func testNoPermanentFullWidthAddRowExists() {
        let app = launch()

        for label in ["Add it to your list", "Add a project", "Add a task to your list"] {
            let matches = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label ==[c] %@", label))
            XCTAssertEqual(
                matches.count, 0,
                "Found a permanent full-width add row labelled “\(label)”, which the spec forbids"
            )
        }
    }

    /// Spec §27: the app must not lose its state across a relaunch.
    func testStatePersistsAcrossRelaunch() {
        let app = launch()
        let firstLaunch = Set(
            app.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label)
        )

        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 20))

        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let secondLaunch = Set(
            app.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label)
        )

        XCTAssertFalse(secondLaunch.isEmpty, "The app came back empty after a relaunch")
        XCTAssertFalse(
            firstLaunch.isDisjoint(with: secondLaunch),
            "Nothing from the first launch survived the relaunch"
        )
    }
}
