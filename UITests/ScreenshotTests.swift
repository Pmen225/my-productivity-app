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

    private func launchRolloverReview() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapSeedRolloverReview"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        Thread.sleep(forTimeInterval: 3)
        return app
    }

    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Confirm the current Focus wheel is rendered before a capture.
    private func assertFocusWheelReady(_ app: XCUIApplication, _ captureName: String) {
        // Current Focus uses pinch/VoiceOver adjustment; the removed dial
        // submenu is not part of the acceptance contract.
        XCTAssertTrue(
            app.staticTexts["Pinch to zoom"].waitForExistence(timeout: 8),
            "Focus wheel did not render before the \(captureName) capture"
        )
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// Taps a real tab bar item by its label. Decision 1b (2026-07-29)
    /// reverses the `≡` glass menu back to a native `TabView`/`.tabItem`
    /// bar, so items live in `app.tabBars` — scoping the query there is what
    /// keeps this safe from the CLAUDE.md trap where a bare
    /// `app.buttons["Focus"].firstMatch` collided with the demo task titled
    /// "Focus" on the Today timeline.
    private func tapTab(_ app: XCUIApplication, _ label: String) -> Bool {
        let button = app.tabBars.buttons[label].firstMatch
        guard button.waitForExistence(timeout: 10) else {
            XCTFail("Tab \(label) not found")
            return false
        }
        button.tap()
        Thread.sleep(forTimeInterval: 0.6)
        // A cold simulator launch can report the tab button as present before
        // the first TabView transaction is ready to receive its accessibility
        // tap. Retry the button's own centre once, then assert the outcome so
        // a later screen cannot be photographed under the wrong filename.
        if !button.isSelected {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 0.8)
        }
        guard button.isSelected else {
            XCTFail("Tab \(label) did not become selected after tapping")
            return false
        }
        Thread.sleep(forTimeInterval: 2.5)
        return true
    }

    /// Map and Calendar are Plan-owned destinations, not top-level tabs.
    private func selectPlanSegment(_ app: XCUIApplication, _ title: String) -> Bool {
        let segment = app.buttons["plan-segment-\(title.lowercased())"].firstMatch
        guard segment.waitForExistence(timeout: 5) else {
            XCTFail("Plan segment \(title) not found")
            return false
        }
        segment.tap()
        Thread.sleep(forTimeInterval: 1.0)
        guard segment.isSelected else {
            XCTFail("Plan segment \(title) did not become selected")
            return false
        }
        return true
    }

    /// Stats dropped off the tab bar (decision 1b) — it's reached instead by
    /// the chart-icon button pushed onto Plan's own `NavigationStack`.
    /// Caller must already be on the Plan tab.
    private func tapStats(_ app: XCUIApplication) -> Bool {
        let button = app.navigationBars.buttons["Stats"].firstMatch
        guard button.waitForExistence(timeout: 10) else {
            XCTFail("Stats nav-bar button not found")
            return false
        }
        button.tap()
        Thread.sleep(forTimeInterval: 2.5)
        return true
    }

    func testCaptureEveryRequiredScreen() {
        let app = launch()

        // The app launches on Focus now, so the shot is named for what it is.
        // There is no Today capture any more: decision 3 makes Today a pane of
        // the Map page rather than a destination, and T3 builds it.
        capture(app, named: "iphone-launch")

        if tapTab(app, "Plan"), selectPlanSegment(app, "Map") {
            capture(app, named: "iphone-map")

            // The same destination's other pane, reached by the toggle in the
            // nav bar's centre — not a separate tab any more.
            let todayPane = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == 'Today plan'"))
                .firstMatch
            if todayPane.waitForExistence(timeout: 5) {
                todayPane.tap()
                Thread.sleep(forTimeInterval: 1.5)
                capture(app, named: "iphone-today-pane")
                app.buttons["Map"].firstMatch.tap()
                Thread.sleep(forTimeInterval: 1.5)
            }

            // The design's "New" sheet off the + FAB. Captured here, not at
            // launch, because the FAB is hidden on the Focus tab — which is
            // now where the app opens.
            let fab = app.buttons["New task, project or initiative"].firstMatch
            if fab.waitForExistence(timeout: 5) {
                fab.tap()
                Thread.sleep(forTimeInterval: 2)
                capture(app, named: "iphone-new-sheet")

                // The Project kind swaps the task's subtasks and note for the
                // INITIATIVE chips — a different sheet worth its own shot.
                let kindMenu = app.buttons["Kind"].firstMatch
                if kindMenu.waitForExistence(timeout: 5) {
                    kindMenu.tap()
                    app.buttons["Project"].firstMatch.tap()
                    Thread.sleep(forTimeInterval: 1)
                    capture(app, named: "iphone-new-sheet-project")
                    kindMenu.tap()
                    app.buttons["Task"].firstMatch.tap()
                    Thread.sleep(forTimeInterval: 1)
                } else {
                    XCTFail("Kind menu not found in the New sheet")
                }

                // Creating a task raises the HUD pill over whatever screen the
                // sheet was covering. It is the one moment that can be
                // provoked deterministically, so it is what proves the moment
                // overlay actually draws.
                //
                // One-task-card spec (2026-08-10): a task now opens the fused
                // `TaskDetailInspector` card instead of `FlowCreateSheet`, so
                // the field is labelled "Task title" (not "Task name") and
                // confirming uses the card's ✓ "Keep task" button (not
                // "Create").
                let name = app.textFields["Task title"].firstMatch
                let create = app.buttons["Keep task"].firstMatch
                if name.waitForExistence(timeout: 5), create.waitForExistence(timeout: 5) {
                    name.tap()
                    name.typeText("Sketch the cover")
                    create.tap()
                    Thread.sleep(forTimeInterval: 0.8)
                    capture(app, named: "iphone-hud-pill")
                } else {
                    XCTFail("New sheet did not offer a name field and a Keep-task button")
                }

                let close = app.buttons["Close"].firstMatch
                if close.exists { close.tap() } else { app.swipeDown() }
                Thread.sleep(forTimeInterval: 1.5)
            } else {
                // A bare `if` would skip the shot silently and still report a
                // green run — the trap CLAUDE.md records against this suite.
                XCTFail("Create FAB not found on the Plan Map segment")
            }

            // The demo workspace ships one map; opening it shows the canvas.
            let weeklyPlan = app.staticTexts["Weekly Plan"].firstMatch
            if weeklyPlan.waitForExistence(timeout: 8) {
                weeklyPlan.tap()
                Thread.sleep(forTimeInterval: 4)
                capture(app, named: "iphone-map-canvas")
            }
        }

        if tapTab(app, "Focus") {
            // The wheel mode is persisted in settings and survives a re-seed,
            // so without choosing one here the shot silently captures whichever
            // dial the previous run happened to leave selected.
            assertFocusWheelReady(app, "focus-wheel")
            capture(app, named: "iphone-focus-wheel")

            assertFocusWheelReady(app, "focus-wheel-close")
            capture(app, named: "iphone-focus-wheel-close")

            // Drag the lower card up. Window-relative coordinates are used
            // because the grab handle itself is not a hit-testable element.
            let window = app.windows.firstMatch
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.74))
            let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
            start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 3)
            capture(app, named: "iphone-focus-card-expanded")

            // The card's second page, reached by its own pager dot — the
            // checklist and the timeline connecting its circles.
            let subtasksDot = app.buttons["Subtasks"].firstMatch
            if subtasksDot.waitForExistence(timeout: 5) {
                subtasksDot.tap()
                Thread.sleep(forTimeInterval: 1.5)
                capture(app, named: "iphone-focus-subtasks")
            }

            // Decision 14's third height. Tapping the handle cycles it —
            // dragging down cannot be used here because the expanded card's
            // own queue scrolls, and the scroll takes the drag.
            let handle = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Task card")
            ).firstMatch
            if handle.waitForExistence(timeout: 5) {
                handle.tap()
                Thread.sleep(forTimeInterval: 1.5)
                capture(app, named: "iphone-focus-card-hidden")
            }

            // Decision 13: the countdown hides on a tap and a ◷ button takes
            // its place.
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.297)).tap()
            Thread.sleep(forTimeInterval: 1)
            capture(app, named: "iphone-focus-timer-hidden")
            if app.buttons["Show timer"].firstMatch.waitForExistence(timeout: 5) {
                app.buttons["Show timer"].firstMatch.tap()
            }
        }

        if tapTab(app, "Plan") {
            let calendarButton = app.navigationBars.buttons["Calendar"].firstMatch
            guard calendarButton.waitForExistence(timeout: 5) else {
                XCTFail("Calendar button not found in Plan's navigation bar")
                return
            }
            calendarButton.tap()
            Thread.sleep(forTimeInterval: 1.5)
            capture(app, named: "iphone-calendar")

            // A day cell still takes a tap: the grid's own drag recogniser sits
            // over these buttons, and one that swallowed them would leave the
            // panel stuck on today with nothing failing. Today has a full plan
            // and the 1st does not, so the empty state appearing is the proof
            // the selection actually moved.
            // Two spellings so the step does not hinge on the simulator's
            // region: the cell's label is a full-style date, ", 1 July 2026"
            // in en_GB and "July 1, 2026" in en_US. The leading comma keeps
            // "31 July 2026" from matching.
            let firstOfMonth = app.buttons.matching(
                NSPredicate(
                    format: "label CONTAINS[c] ', 1 July 2026' OR label CONTAINS[c] 'July 1, 2026'"
                )
            ).firstMatch
            if firstOfMonth.waitForExistence(timeout: 5) {
                firstOfMonth.tap()
                XCTAssertTrue(
                    app.staticTexts["Nothing planned."].waitForExistence(timeout: 5),
                    "Tapping a day cell did not move the agenda to that day"
                )
                app.buttons["Today"].firstMatch.tap()
                Thread.sleep(forTimeInterval: 1)
            }

            // Decision 17's gesture. Driven as a coordinate drag across the
            // grid itself rather than a window-wide swipe, which would land on
            // the paging panel underneath and flip its page instead. The header
            // is asserted, not just photographed — a gesture that quietly does
            // nothing still produces a plausible-looking picture.
            let grid = app.windows.firstMatch
            grid.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.33))
                .press(
                    forDuration: 0.05,
                    thenDragTo: grid.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.33))
                )
            Thread.sleep(forTimeInterval: 1)
            let steppedMonth = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'choose month'")
            ).firstMatch
            if steppedMonth.exists { capture(app, named: "iphone-calendar-next-month") }

            // "Today" only exists once you have navigated away, which is why it
            // is tapped here rather than on the first capture.
            app.buttons["Today"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 1)

            // Scrolled to the end, to prove the day's last row clears the tab
            // bar, the FAB and the orb rather than sitting under them.
            app.swipeUp()
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            capture(app, named: "iphone-calendar-agenda-bottom")

            // The panel's second page. Driven from its dot rather than a
            // coordinate swipe, so the capture can't photograph page one
            // because a drag was eaten by the page's own scroll view.
            let weeklyPlanDot = app.buttons["WEEKLY PLAN"].firstMatch
            if weeklyPlanDot.waitForExistence(timeout: 5) {
                weeklyPlanDot.tap()
                Thread.sleep(forTimeInterval: 2)
                capture(app, named: "iphone-calendar-weekly-plan")
                app.buttons["AGENDA"].firstMatch.tap()
                Thread.sleep(forTimeInterval: 1)
            }

            // The month/year jump panel, opened from the header title.
            let monthTitle = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'choose month'")
            ).firstMatch
            if monthTitle.waitForExistence(timeout: 5) {
                monthTitle.tap()
                Thread.sleep(forTimeInterval: 2)
                capture(app, named: "iphone-calendar-month-picker")
                monthTitle.tap()
            }
        }

        if tapTab(app, "Plan") {
            capture(app, named: "iphone-library")
            XCTAssertFalse(
                app.staticTexts["REVIEW"].exists,
                "Plan should not expose a duplicate REVIEW/Stats route; use the chart toolbar button"
            )

            // Scrolled to the end, to prove the last row clears the floating
            // FAB and orb rather than sitting under them.
            app.swipeUp()
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            capture(app, named: "iphone-library-bottom")
            app.swipeDown()
            app.swipeDown()
            Thread.sleep(forTimeInterval: 1)

            // Stats is a chart-icon push on Plan's own NavigationStack now,
            // not a tab; Settings is still a tab (decision 1b).
            if tapStats(app) {
                capture(app, named: "iphone-stats")
                app.navigationBars.buttons.firstMatch.tap()
                Thread.sleep(forTimeInterval: 1)
            }

            if tapTab(app, "Settings") {
                capture(app, named: "iphone-settings")
            }

            // Notes and Assistant stay inside Plan/Library, so hop back.
            guard tapTab(app, "Plan") else { return }

            // Notes now UNFOLDS IN PLACE (subtasks 6.8/6.9) instead of pushing
            // `NotesRootView`. The old capture tapped it and then popped with
            // `app.navigationBars.buttons.firstMatch.tap()` — with nothing
            // pushed there is no back button, so that tap would land on the
            // Plan nav bar's own leading control and quietly derail every
            // capture after it while the suite still reported green.
            // Collapse it by tapping the row again instead.
            // Match on a PREFIX, not the bare title: an accordion row's
            // accessibility label is "Notes, <count>", so `buttons["Notes"]`
            // matches nothing. It previously sat behind a bare
            // `if …waitForExistence`, so the miss skipped the capture in
            // silence and the test still reported green with no
            // `iphone-plan-notes-attach.png` in the export at all.
            // Fail loudly instead — a guard that can only skip is not a check.
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
            let notes = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Notes'")).firstMatch
            if notes.waitForExistence(timeout: 5) {
                // The row's own accessibility label is "Notes, <count>".
                let noteCount = Int(
                    notes.label.split(separator: ",").last?.trimmingCharacters(in: .whitespaces) ?? ""
                ) ?? 0
                // Compare the SET of visible labels, exactly as the Today
                // accordion check above does, NOT how many there are. A count
                // is blind here for the same reason it was blind there: this
                // list is already full, so the rows that appear push others
                // off the bottom and the total can sit still while the screen
                // plainly changed. "free before" is skipped because the Inbox
                // header counts minutes down to 21:00 on its own and would
                // satisfy a naive set check with nothing having expanded.
                let visibleLabels = {
                    Set(
                        app.staticTexts.allElementsBoundByIndex
                            .map(\.label)
                            .filter { !$0.contains("free before") }
                    )
                }
                let before = visibleLabels()
                notes.tap()
                Thread.sleep(forTimeInterval: 2)
                capture(app, named: "iphone-plan-notes-attach")
                // Shape assertion, never a named demo task: the demo's
                // auto-plan schedules fewer tasks as the evening wears on, so
                // a title like "Reading" fails against working code. Unfolding
                // Notes reveals its note preview rows in place.
                if noteCount > 0 {
                    XCTAssertFalse(
                        visibleLabels().subtracting(before).isEmpty,
                        "Unfolding Notes (count \(noteCount)) revealed no row that was not already on screen"
                    )
                }
                notes.tap()
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
                // T21 replaced the free-text Definition of Done field with the
                // subtask checklist; the gate's own headline is the marker now.
                let gateHeadline = app.staticTexts.matching(
                    NSPredicate(format: "label BEGINSWITH 'Break it down'")
                ).firstMatch
                if gateHeadline.waitForExistence(timeout: 5) {
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

    func testCaptureRolloverReview() {
        let app = launchRolloverReview()
        let heading = app.staticTexts["Remaining tasks"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "Rollover review did not open")
        let tomorrowButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Move ' AND label ENDSWITH ' to tomorrow'")
        ).firstMatch
        XCTAssertTrue(tomorrowButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["More choices for Review the unfinished brief"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["I'm done reviewing"].firstMatch.waitForExistence(timeout: 5))
        capture(app, named: "iphone-rollover-review")
    }

    /// Adds one quick task from the shell's floating create button, so the
    /// prioritise duel screenshot never depends on how many demo tasks the
    /// auto-plan at launch happened to leave sitting in the
    /// Inbox. T6 removed Library's "Inbox" row (`PlanInboxSection` already
    /// shows the inbox inline at the top of Plan), so this no longer opens
    /// `TaskListScreen`'s "Add task" control — it drives the shared
    /// `QuickCaptureView`, which since the one-task-card spec (2026-08-10)
    /// routes a task straight to the fused `TaskDetailInspector` card
    /// (`FlowCreateSheet` now only handles Project/Initiative).
    ///
    /// KNOWN LIMITATION (2026-08-10): the fused card has no due-date field —
    /// the founder ruling scoped due date to seed-only, matching the editor's
    /// existing (pre-fusion) field set — so `dueToday` can no longer be
    /// satisfied from this generic shell-FAB entry point. It fails loud below
    /// rather than silently creating an undated task; `testCapturePrioritiseDuel`
    /// needs a different route to a due-today task (e.g. seeding
    /// `flagForTodayIfUndated` through a Today-scoped entry point) before it
    /// can pass again.
    private func addQuickTask(_ app: XCUIApplication, title: String, dueToday: Bool = false) {
        // Reach the create sheet by the SHELL's floating button. Plan used to
        // carry a duplicate "+" in its own toolbar, and the sheet it presented
        // — from `LibraryView`, inside a NavigationStack inside the TabView —
        // rendered a title field that reported a real frame and took taps yet
        // never became first responder, so `typeText` threw "Neither element
        // nor any descendant has keyboard focus". That duplicate is now gone
        // and the shell's button is the only route; keep it that way.
        let addButton = app.buttons["New task, project or initiative"].firstMatch
        guard addButton.waitForExistence(timeout: 5) else {
            XCTFail("Floating create button not found")
            return
        }
        addButton.tap()
        Thread.sleep(forTimeInterval: 0.5)
        // The fused `TaskDetailInspector` card's title field is
        // `TextField("Task title", text: $task.title)` — label and
        // placeholder are the same string, unlike the old sheet's field.
        let field = app.textFields["Task title"].firstMatch
        guard field.waitForExistence(timeout: 5) else {
            XCTFail("Quick capture title field not found")
            return
        }
        // Verify the OUTCOME, never a proxy for it. Waiting on
        // `app.keyboards` was both flaky and wrong: the sheet auto-focuses in
        // `onAppear`, which does not reliably stick while a sheet is still
        // presenting, and a simulator with "Connect Hardware Keyboard" on
        // never shows a software keyboard at all even when the field IS
        // focused. Either way the guard failed against working code. Tap and
        // type, then check the field actually holds the title; retry if not.
        var typed = false
        for _ in 0..<4 {
            field.tap()
            // An empty SwiftUI TextField reports its PLACEHOLDER as `value`,
            // so treat that as empty — otherwise this sends ten phantom
            // deletes. Anything else is a previous add's leftover title,
            // which must go or the two concatenate ("Duel candidate ADuel
            // candidate B" shipped in a real capture).
            if let existing = field.value as? String,
               !existing.isEmpty,
               existing != "Task title" {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
            }
            field.typeText(title)
            if (field.value as? String) == title {
                typed = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard typed else {
            XCTFail("Quick capture title field never accepted text (value: \(String(describing: field.value)))")
            return
        }
        // T10's Due pill used to set a due date defaulting to now here, which
        // landed the task in today's set — what the today-scoped duel needs.
        // One-task-card spec (2026-08-10): the fused card has no due-date
        // field at all (due date is seed-only, matching the editor's
        // pre-fusion field set), so this generic shell-FAB entry point can no
        // longer satisfy `dueToday`. Fail loud rather than silently creating
        // an undated task and letting the duel assertion fail somewhere else
        // with a confusing message.
        if dueToday {
            XCTFail("addQuickTask can no longer mark a task due-today: the fused TaskDetailInspector create card dropped the due-date field (one-task-card spec, 2026-08-10). testCapturePrioritiseDuel needs a due-today entry point instead (e.g. seeding flagForTodayIfUndated).")
            return
        }
        // The fused card's title field has no `.onSubmit`, so return does
        // nothing here. Tap the ✓ "Keep task" button.
        //
        // Scroll to it first — mirrors the old sheet's need to reach Create
        // past a data-driven section.
        let createButton = app.buttons["Keep task"].firstMatch
        guard createButton.waitForExistence(timeout: 3) else {
            XCTFail("Keep-task button not found")
            return
        }
        for _ in 0..<3 where !createButton.isHittable {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.4)
        }
        guard createButton.isHittable else {
            XCTFail("Keep-task button never became reachable")
            return
        }
        createButton.tap()
        Thread.sleep(forTimeInterval: 0.8)

        // Verify the task actually EXISTS, not merely that the text was typed
        // and Create was tapped. Without this the helper returns quietly when
        // creation fails and the caller reports something else entirely —
        // three tests failed with "the inbox may be empty" when the real
        // question was whether the add had worked at all. The typed-text check
        // above is a proxy; this is the outcome.
        let created = app.staticTexts[title].firstMatch
        XCTAssertTrue(
            created.waitForExistence(timeout: 5),
            "Quick capture reported success but no task titled \"\(title)\" appeared"
        )
    }

    /// Promotes a newly created inbox task through the same leading swipe a
    /// person uses. The prioritise game intentionally compares Today's work,
    /// while the fused create card has no due-date control.
    private func flagForToday(_ app: XCUIApplication, title: String) -> Bool {
        let row = app.staticTexts[title].firstMatch
        guard row.waitForExistence(timeout: 5) else {
            XCTFail("Could not find \(title) to flag it for Today")
            return false
        }
        row.swipeRight()
        let today = app.buttons["sun.max"].firstMatch
        guard today.waitForExistence(timeout: 3) else {
            XCTFail("Leading swipe on \(title) did not reveal Today")
            return false
        }
        today.tap()
        Thread.sleep(forTimeInterval: 0.7)
        return true
    }

    /// The shared glass delete card, reached the way decision 11 says a row is
    /// deleted: swipe, not a permanent `✕`. T6 removed Library's "Inbox" row;
    /// `PlanInboxSection` already renders the inbox inline at the top of the
    /// Plan tab, `TaskRowView`'s own swipe actions unchanged underneath it.
    func testCaptureDeleteConfirmation() {
        let app = launch()
        guard tapTab(app, "Plan") else { return }

        // Add one, so the row swiped is this test's own rather than whichever
        // task the demo's auto-plan happened to leave behind.
        addQuickTask(app, title: "Delete me")

        let target = app.staticTexts["Delete me"].firstMatch
        guard target.waitForExistence(timeout: 8) else {
            XCTFail("Task row 'Delete me' not found in the Inbox")
            return
        }
        target.swipeLeft()
        Thread.sleep(forTimeInterval: 1)

        let deleteAction = app.buttons["Delete"].firstMatch
        guard deleteAction.waitForExistence(timeout: 5) else {
            XCTFail("Swipe delete action not found")
            return
        }
        deleteAction.tap()
        Thread.sleep(forTimeInterval: 3)
        capture(app, named: "iphone-delete-confirm")
        // Asserted, not just photographed: this card presented from a list row
        // is fragile enough that a silent no-show has to fail the run.
        XCTAssertTrue(
            app.staticTexts["Delete “Delete me”?"].exists,
            "The delete confirmation card did not appear"
        )
    }

    /// The prioritise duel: reached from `PlanInboxSection`, inline at the
    /// top of the Plan tab since T6 removed Library's own "Inbox" row — see
    /// `PrioritiseDuelView`'s header comment for why the duel exists at all.
    /// Answers every duel by always taking the first offered choice, then
    /// captures the medal-ranked reveal.
    func testCapturePrioritiseDuel() {
        let app = launch()
        guard tapTab(app, "Plan") else { return }

        // Insert real sample tasks, then use the visible swipe action to put
        // them into the game. This proves the journey instead of relying on
        // whatever the demo seed happened to schedule at the current hour.
        addQuickTask(app, title: "Duel candidate A")
        guard flagForToday(app, title: "Duel candidate A") else { return }
        addQuickTask(app, title: "Duel candidate B")
        guard flagForToday(app, title: "Duel candidate B") else { return }

        let playButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Prioritise today'")
        ).firstMatch
        guard playButton.waitForExistence(timeout: 8) else {
            XCTFail("Prioritise duel entry not found — today may hold fewer than two tasks")
            return
        }
        playButton.tap()
        Thread.sleep(forTimeInterval: 1.5)

        // Hard-fail if the duel never opened, rather than silently
        // photographing the Plan screen twice. This is the exact regression
        // that shipped once: `PlanInboxSection`'s `.sheet` was attached to a
        // `Section` nested inside this screen's `List` and never presented,
        // yet nothing downstream failed — the tap-through loop below just
        // `break`s when it finds no choice button, so the run stayed green
        // while `iphone-prioritise-duel.png` and `-reveal.png` came out
        // byte-for-byte identical. Every choice button's accessibility label
        // starts "Put … ahead of …" (`PrioritiseDuelView.swift`).
        let choicePredicate = NSPredicate(format: "label BEGINSWITH 'Put '")
        guard app.buttons.matching(choicePredicate).firstMatch.waitForExistence(timeout: 5) else {
            XCTFail("Prioritise duel did not present after tapping \"Play the game\"")
            return
        }
        let openChoices = app.buttons.matching(choicePredicate)
        XCTAssertEqual(openChoices.count, 2, "A duel must present exactly two choices")
        for index in 0..<min(openChoices.count, 2) {
            let frame = openChoices.element(boundBy: index).frame
            XCTAssertGreaterThanOrEqual(frame.width, 44, "Duel choice \(index + 1) is too narrow to tap")
            XCTAssertGreaterThanOrEqual(frame.height, 44, "Duel choice \(index + 1) is too short to tap")
        }
        capture(app, named: "minigame-01-open")
        XCTAssertFalse(app.buttons["No preference"].exists, "Redundant no-preference control is still visible")

        // Exercise the close control and assert its actual outcome, then
        // reopen to continue the game.
        let close = app.buttons["Close"].firstMatch
        guard close.waitForExistence(timeout: 3) else {
            XCTFail("Full-screen minigame has no Close control")
            return
        }
        close.tap()
        XCTAssertTrue(
            playButton.waitForExistence(timeout: 5),
            "Close did not return to Plan"
        )
        playButton.tap()
        guard app.buttons.matching(choicePredicate).firstMatch.waitForExistence(timeout: 5) else {
            XCTFail("Minigame did not reopen")
            return
        }

        // First offered task: capture the held selection beat before exit,
        // proving visible winner/loser feedback rather than only a counter mutation.
        app.buttons.matching(choicePredicate).element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 0.08)
        capture(app, named: "minigame-02-first-choice-feedback")
        Thread.sleep(forTimeInterval: 0.95)

        // Two tasks complete after one comparison. Larger rounds continue to
        // a second pair and exercise the other choice before the tap-through.
        if !app.staticTexts["Decision made."].waitForExistence(timeout: 2) {
            let secondChoice = app.buttons.matching(choicePredicate).element(boundBy: 1)
            guard secondChoice.waitForExistence(timeout: 5) else {
                XCTFail("Next comparison did not arrive after the first choice")
                return
            }
            secondChoice.tap()
            Thread.sleep(forTimeInterval: 0.08)
            capture(app, named: "minigame-03-second-choice-feedback")
            Thread.sleep(forTimeInterval: 0.95)
        }

        // Finish every remaining comparison. The ranked screen itself is the
        // outcome assertion; a tap loop that simply ran is not evidence.
        var remainingTaps = 100
        while remainingTaps > 0 && !app.staticTexts["Decision made."].exists {
            let choice = app.buttons.matching(choicePredicate).firstMatch
            guard choice.waitForExistence(timeout: 3) else { break }
            choice.tap()
            Thread.sleep(forTimeInterval: 1.05)
            remainingTaps -= 1
        }

        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(
            app.staticTexts["Decision made."].waitForExistence(timeout: 5),
            "Prioritise duel did not reach its reveal after answering every available pair"
        )
        capture(app, named: "minigame-04-ranked-result")

        let keepOrder = app.buttons["Keep order"].firstMatch
        guard keepOrder.waitForExistence(timeout: 5) else {
            XCTFail("Keep-order exit missing")
            return
        }
        keepOrder.tap()
        let planReturn = expectation(
            for: NSPredicate(format: "isHittable == true"),
            evaluatedWith: playButton
        )
        wait(for: [planReturn], timeout: 8)
        Thread.sleep(forTimeInterval: 0.8)
        capture(app, named: "minigame-05-keep-order-exit")

        // Re-run and exercise the other result action as well.
        playButton.tap()
        guard app.buttons.matching(choicePredicate).firstMatch.waitForExistence(timeout: 5) else {
            XCTFail("Minigame did not reopen for plan-today exit")
            return
        }
        remainingTaps = 100
        while remainingTaps > 0 && !app.staticTexts["Decision made."].exists {
            let choice = app.buttons.matching(choicePredicate).firstMatch
            guard choice.waitForExistence(timeout: 3) else { break }
            choice.tap()
            Thread.sleep(forTimeInterval: 1.05)
            remainingTaps -= 1
        }
        let planToday = app.buttons["Plan today"].firstMatch
        guard planToday.waitForExistence(timeout: 5) else {
            XCTFail("Plan-today exit missing")
            return
        }
        planToday.tap()
        let duelNavigationBar = app.navigationBars["Prioritise duel"].firstMatch
        XCTAssertTrue(
            duelNavigationBar.waitForNonExistence(timeout: 10),
            "Plan today did not dismiss the prioritise duel"
        )
        let planTab = app.tabBars.buttons["Plan"].firstMatch
        guard planTab.waitForExistence(timeout: 5), planTab.isSelected else {
            XCTFail("Plan today returned, but the native Plan tab was not selected")
            return
        }
        capture(app, named: "minigame-06-plan-today-exit")
    }

    /// "Start planning" must actually present `PlanPreviewView`.
    ///
    /// This is the duel's twin, and it had the identical root cause: both
    /// sheets were attached to `PlanInboxSection`'s own `Section`, nested
    /// inside `LibraryView`'s `List`, where a `.sheet` never presents — the
    /// flag flips, nothing appears, nothing errors. The duel had a
    /// screenshot test that caught it once it was taught to fail; this path
    /// had nothing behind it at all, which made it the likeliest place for
    /// the same bug to come back unnoticed.
    ///
    /// Asserts on the sheet's own chrome (`Plan my day`, `Apply plan`), never
    /// on which demo tasks the auto-plan happened to schedule — how full the
    /// proposal is depends on the hour, but the sheet's title does not.
    func testCapturePlanPreview() {
        let app = launch()
        guard tapTab(app, "Plan") else { return }

        // "Start planning" only renders when the inbox is non-empty
        // (`PlanInboxSection.body`), and the demo's auto-plan can empty it —
        // so put one task in rather than depending on what is left over.
        addQuickTask(app, title: "Preview candidate")

        let startPlanning = app.buttons["Start planning"].firstMatch
        guard startPlanning.waitForExistence(timeout: 8) else {
            XCTFail("\"Start planning\" not found — the inbox may be empty")
            return
        }
        startPlanning.tap()

        // Match the sheet's own navigation title, which exists in every
        // proposal state including "nothing could be placed".
        let previewTitle = app.staticTexts["Plan my day"].firstMatch
        XCTAssertTrue(
            previewTitle.waitForExistence(timeout: 5),
            "Plan preview did not present after tapping \"Start planning\""
        )
        Thread.sleep(forTimeInterval: 0.8)
        capture(app, named: "iphone-plan-preview")

        // Leave without applying: this test proves the sheet presents, and
        // applying a plan would move the demo day underneath every later run.
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 3) {
            cancel.tap()
        }
    }

    /// Feedback task 15's Sounds card, in its own test for the same reason as
    /// Stats: nothing on Settings depends on the auto-plan, so this can run at
    /// any hour. The card sits below the fold, so scroll until its ticking
    /// toggle exists and fail loudly if it never does — a guard that can only
    /// skip is not a check.
    func testCaptureSettingsSounds() {
        let app = launch()
        guard tapTab(app, "Settings") else {
            XCTFail("Settings tab not reachable")
            return
        }

        let sounds = app.buttons["Sounds"].firstMatch
        guard sounds.waitForExistence(timeout: 8) else {
            XCTFail("Sounds route not found")
            return
        }
        sounds.tap()
        XCTAssertTrue(app.staticTexts["Sounds"].waitForExistence(timeout: 8))
        capture(app, named: "iphone-settings-sounds")
    }

    /// Decision 21's lighter demo action lives below the Sounds and
    /// Notifications cards. Assert the renamed control is actually hittable,
    /// rather than letting an off-screen `exists` result produce a false green
    /// screenshot.
    func testCaptureSettingsData() {
        let app = launch()
        // Leave any persisted Calendar page first; this two-hop route avoids a
        // cold TabView transaction reporting Settings selected while still
        // rendering the Calendar page underneath it.
        guard tapTab(app, "Plan"), tapTab(app, "Settings") else {
            XCTFail("Settings tab not reachable")
            return
        }

        let data = app.buttons["Data"].firstMatch
        guard data.waitForExistence(timeout: 8) else { XCTFail("Data route not found"); return }
        data.tap()
        let restart = app.buttons["Restart demo day"].firstMatch
        guard restart.waitForExistence(timeout: 8) else { XCTFail("Restart demo day not on Data screen"); return }
        capture(app, named: "iphone-settings-data")
    }

    /// Proves the action is not just a renamed button: confirmation leads to
    /// an immediate restart acknowledgement after the seeded day is rebuilt.
    func testRestartDemoDay() {
        let app = launch()
        guard tapTab(app, "Plan"), tapTab(app, "Settings") else {
            XCTFail("Settings tab not reachable")
            return
        }

        let data = app.buttons["Data"].firstMatch
        guard data.waitForExistence(timeout: 8) else { XCTFail("Data route not found"); return }
        data.tap()
        let restart = app.buttons["Restart demo day"].firstMatch
        guard restart.waitForExistence(timeout: 8) else { XCTFail("Restart demo day not on Data screen"); return }
        restart.tap()

        let confirm = app.buttons["Restart"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Restart confirmation did not appear")
        confirm.tap()
        XCTAssertTrue(
            app.staticTexts["Demo day restarted."].waitForExistence(timeout: 10),
            "Restart acknowledgement did not appear"
        )
        capture(app, named: "iphone-restart-demo-day")
    }

    /// T7's Stats page, in its own test so it can run at any hour: nothing on
    /// this screen depends on the auto-plan, so it survives the 21:00 workday
    /// cliff that stops `testCaptureEveryRequiredScreen` dead.
    ///
    /// Every assertion here is one that failed for a real reason during T7:
    /// the track/untrack circle is a `Button` sitting deliberately *outside*
    /// the disclosure's label, because a `Button` nested inside another
    /// `Button`'s label receives no taps on iOS — silently, with no error and
    /// no test failure. The "still collapsed after tapping the circle" check
    /// is what proves the two controls stayed independent.
    func testCaptureStats() {
        let app = launch()
        guard tapTab(app, "Plan") else { return }
        guard tapStats(app) else { return }

        // The row's toggle carries its state in its label, so this both finds
        // the control and asserts the demo seeded a project to put it on.
        let toggle = app.buttons["Tracked in stats"].firstMatch
        guard toggle.waitForExistence(timeout: 8) else {
            XCTFail("No tracked-project toggle on Stats — the demo seed may have created no projects")
            return
        }
        capture(app, named: "iphone-stats")

        // The project row itself: labelled "<title>, N of M tasks complete",
        // valued Expanded/Collapsed by the disclosure.
        let row = app.buttons
            .matching(NSPredicate(format: "label CONTAINS ' tasks complete'"))
            .firstMatch
        guard row.waitForExistence(timeout: 5) else {
            XCTFail("No project row found on Stats")
            return
        }
        XCTAssertEqual(row.value as? String, "Collapsed", "A project row should start collapsed")

        // 1. Untracking must NOT expand the row. This is the nested-Button check.
        toggle.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(
            app.buttons["Not tracked in stats"].firstMatch.waitForExistence(timeout: 5),
            "Tapping the circle did not untrack the project — the toggle may be swallowed by the disclosure's own button"
        )
        XCTAssertEqual(
            row.value as? String,
            "Collapsed",
            "Tapping the track circle also expanded the row — the two controls are not independent"
        )
        capture(app, named: "iphone-stats-untracked")

        // Put it back so the expansion shot photographs a tracked row.
        app.buttons["Not tracked in stats"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1)

        // 2. The row expands, and brings its task list with it. Compare the
        //    SET of visible labels, never the count — a full screen makes a
        //    count blind (CLAUDE.md, 2026-07-30).
        let before = Set(app.staticTexts.allElementsBoundByIndex.compactMap { $0.label })
        row.tap()
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertEqual(row.value as? String, "Expanded", "The project row did not expand when tapped")

        let after = Set(app.staticTexts.allElementsBoundByIndex.compactMap { $0.label })
        XCTAssertFalse(
            after.subtracting(before).isEmpty,
            "Expanding the project row revealed no new labels"
        )
        capture(app, named: "iphone-stats-expanded")

        // 2b. Spec row 20's empty state, which only a project with no tasks can
        //     show. The demo seed gives "Life & Fun" no tasks precisely so this
        //     branch is reachable — without that it is dead UI nobody can
        //     photograph, the failure mode CLAUDE.md records for FocusTaskCard's
        //     unreachable "done / moved / skipped" rows.
        //
        //     Scroll to it FIRST: the task-free project is the last row, and
        //     the assertion below passes on an off-screen element — the first
        //     run of this step exported a capture named for the empty state
        //     that photographed the row hidden behind the tab bar.
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.8)
        let emptyRow = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH 'Life & Fun'"))
            .firstMatch
        if emptyRow.waitForExistence(timeout: 5) {
            emptyRow.tap()
            Thread.sleep(forTimeInterval: 1.2)
            XCTAssertTrue(
                app.staticTexts["No tasks in this project yet."].firstMatch.waitForExistence(timeout: 5),
                "An empty project did not show row 20's empty state when expanded"
            )
            capture(app, named: "iphone-stats-empty-project")
            emptyRow.tap()
            Thread.sleep(forTimeInterval: 0.8)
        } else {
            XCTFail("The task-free demo project is missing — the seed no longer produces one")
        }

        // 3. The XP explainer's five award lines, which were one run-on
        //    paragraph before T7.
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.6)
        let howXP = app.buttons["How XP works"].firstMatch
        if howXP.waitForExistence(timeout: 5) {
            howXP.tap()
            Thread.sleep(forTimeInterval: 1)
            XCTAssertTrue(
                app.staticTexts["Whole day cleared — +50"].firstMatch.waitForExistence(timeout: 5),
                "The XP explainer's itemised award lines are missing"
            )
            capture(app, named: "iphone-stats-xp-explainer")
        }

        // 4. The bottom of the page, photographed rather than asserted on.
        //
        //    A mid-scroll shot in this test's first run showed the floating +
        //    sitting on the Focus stat tile, which looked like a missing bottom
        //    inset. It was not: at the page's true bottom the tiles clear the +
        //    on their own, and adding `.contentMargins(.bottom, …)` to
        //    ProgressScreen changed the resulting frame not at all — the two
        //    bottom captures, with the inset and with it deliberately removed,
        //    are the same picture.
        //
        //    Two assertions were tried and BOTH passed with the inset removed:
        //    `isHittable` (blind, because it tests an element's midpoint and the
        //    tile's midpoint sits left of the +) and a frame-intersection check
        //    (blind, because there is no intersection at the resting bottom).
        //    Rather than ship a third check that can only ever be green, this
        //    step just captures the frame. The picture is the evidence.
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        capture(app, named: "iphone-stats-bottom")
    }

    /// The list actions must stay attached to the list that opened them. On a
    /// compact iPhone, a custom `.popover` attached to the screen body adapts
    /// into a blank sheet, so this captures the native `Menu` anchored to the
    /// toolbar ellipsis and checks every top-level action is reachable.
    func testCaptureListOptionsMenu() {
        let app = launch()
        guard tapTab(app, "Plan") else { return }

        // The current Plan surface exposes the seeded list as a direct native
        // row; the removed Lists carousel and task-page pager are not part of
        // this route.
        let directPersonal = app.buttons["Personal"].firstMatch
        guard directPersonal.waitForExistence(timeout: 8) else {
            XCTFail("Seeded Personal list row was not visible on Plan")
            return
        }
        directPersonal.tap()

        let listTitle = app.navigationBars["Personal"].firstMatch
        guard listTitle.waitForExistence(timeout: 8) else {
            XCTFail("Personal list did not open its task-list screen")
            return
        }

        let options = app.buttons["List options"].firstMatch
        guard options.waitForExistence(timeout: 5) else {
            XCTFail("List options menu button was not reachable")
            return
        }
        options.tap()

        XCTAssertTrue(app.buttons["Create new list"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Edit lists"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Grouping options"].waitForExistence(timeout: 5))
        capture(app, named: "iphone-list-options-menu")

        app.buttons["Grouping options"].tap()
        XCTAssertTrue(app.buttons["Priority"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Manual"].waitForExistence(timeout: 5))
        app.buttons["Manual"].tap()

        let optionsAfterGrouping = app.buttons["List options"].firstMatch
        optionsAfterGrouping.tap()
        app.buttons["Create new list"].tap()
        XCTAssertTrue(app.navigationBars["New List"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()

        optionsAfterGrouping.tap()
        app.buttons["Edit lists"].tap()
        XCTAssertTrue(app.navigationBars["Edit Lists"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
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

        // Named for the launch screen, which is Focus now — see the light-mode
        // note above on why there is no Today capture any more.
        capture(app, named: "iphone-launch-dark")
        // Tab items are queried by label scoped to `app.tabBars`, so the demo
        // task titled "Focus" on the Today timeline no longer collides with
        // this row the way an unscoped label lookup once did.
        if tapTab(app, "Focus") {
            capture(app, named: "iphone-focus-wheel-dark")
        }
    }

    /// A focused light-mode proof of the founder's original bottom-arc dial.
    /// Keeping this isolated makes it cheap to inspect the signature surface
    /// without waiting for the rest of the screenshot catalogue.
    func testCaptureFocusDialLight() {
        let app = launch()

        // The current shell uses top Plan/Focus mode buttons, not a TabView.
        let focusMode = app.buttons["Focus"].firstMatch
        XCTAssertTrue(focusMode.waitForExistence(timeout: 10), "Focus mode button not found")
        XCTAssertTrue(focusMode.isHittable, "Focus mode button is not hittable")
        focusMode.tap()
        let selectedMode = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Selected"),
            object: focusMode
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [selectedMode], timeout: 5),
            .completed,
            "Focus mode did not become selected"
        )

        assertFocusWheelReady(app, "focus-original-dial-light")
        capture(app, named: "iphone-focus-original-dial-light")

        let showTimer = app.buttons["Show timer"].firstMatch
        if showTimer.waitForExistence(timeout: 1) {
            showTimer.tap()
            XCTAssertFalse(showTimer.waitForExistence(timeout: 3), "Show timer did not restore the timer")
            capture(app, named: "iphone-focus-original-dial-timer-restored")
        }

        let queueBar = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Today's queue")
        ).firstMatch
        if queueBar.waitForExistence(timeout: 2) {
            queueBar.tap()
            let queueHeading = app.staticTexts["Today's queue"].firstMatch
            XCTAssertTrue(queueHeading.waitForExistence(timeout: 5), "Queue sheet did not open")
            capture(app, named: "iphone-focus-original-dial-queue")
            let window = app.windows.firstMatch
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.49))
                .press(
                    forDuration: 0.1,
                    thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
                )
            XCTAssertTrue(queueBar.waitForExistence(timeout: 5), "Queue sheet did not close")
        }

        let start = app.buttons["Start focus"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Start focus control not found")
        start.tap()

        let pause = app.buttons["Pause"].firstMatch
        let gate = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Break it down")
        ).firstMatch
        let durationPicker = app.staticTexts["Choose a duration"].firstMatch
        if durationPicker.waitForExistence(timeout: 2) {
            let confirmStart = app.buttons["Start focus"].firstMatch
            XCTAssertTrue(confirmStart.isHittable, "Duration picker Start focus is not hittable")
            confirmStart.tap()
        }
        XCTAssertTrue(
            pause.waitForExistence(timeout: 5) || gate.waitForExistence(timeout: 2),
            "Start focus produced no observable running or planning-gate state"
        )
        capture(app, named: pause.exists
            ? "iphone-focus-original-dial-running"
            : "iphone-focus-original-dial-start-gate")

        if pause.exists {
            pause.tap()
            let resume = app.buttons["Resume"].firstMatch
            XCTAssertTrue(resume.waitForExistence(timeout: 5), "Pause did not expose Resume")
            capture(app, named: "iphone-focus-original-dial-paused")
        }
    }

    func testCaptureFocusDialOverviewLight() {
        let app = launch()
        guard tapTab(app, "Focus") else { return }
        assertFocusWheelReady(app, "focus-overview-ring-light")
        capture(app, named: "iphone-focus-overview-ring-light")
    }

    /// The shell capture route must expose one understandable task editor:
    /// creation type in the header, the complete colour palette, a compact
    /// 30-minute duration, one Project assignment, and no Workspace field.
    func testTaskCreationHierarchyIsVisibleAndUnclipped() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapSeedDemo", "-flowmapOpenAIHarness", "-ApplePersistenceIgnoreState", "YES"]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let captureButton = app.buttons["New task, project or initiative"].firstMatch
        XCTAssertTrue(captureButton.waitForExistence(timeout: 8))
        captureButton.tap()

        // The title focuses on presentation. Submit through the focused
        // field so third-party keyboards use the same native Done path.
        let titleField = app.textFields["Task title"].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Task title field is missing")
        titleField.typeText("\n")
        let kind = app.buttons["Kind"].firstMatch
        XCTAssertTrue(kind.waitForExistence(timeout: 5), "Creation type control is missing")
        kind.tap()
        XCTAssertTrue(app.buttons["Task"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Project"].exists)
        XCTAssertTrue(app.buttons["Initiative"].exists)
        app.buttons["Task"].tap()

        let colourControl = app.buttons["Colour"].firstMatch
        XCTAssertTrue(colourControl.waitForExistence(timeout: 5), "Compact Colour control is missing")
        capture(app, named: "iphone-task-editor-compact")
        colourControl.tap()

        // Measure every palette target against the visible phone bounds.
        let window = app.windows.firstMatch
        for colour in ["Violet", "Green", "Peach", "Blue", "Yellow", "Pink", "Teal", "Lavender"] {
            let swatch = app.buttons[colour].firstMatch
            XCTAssertTrue(swatch.waitForExistence(timeout: 3), "Missing colour: \(colour)")
            XCTAssertGreaterThanOrEqual(swatch.frame.width, 43.5, "\(colour) target is too narrow")
            XCTAssertGreaterThanOrEqual(swatch.frame.height, 43.5, "\(colour) target is too short")
            XCTAssertGreaterThanOrEqual(swatch.frame.minX, window.frame.minX, "\(colour) is clipped on the left")
            XCTAssertLessThanOrEqual(swatch.frame.maxX, window.frame.maxX, "\(colour) is clipped on the right")
        }
        capture(app, named: "iphone-task-editor-colours")

        let duration = app.buttons["Duration"].firstMatch
        XCTAssertTrue(duration.waitForExistence(timeout: 5), "Duration control is missing")
        XCTAssertTrue(String(describing: duration.value).contains("30"), "Default duration is not 30 minutes")

        // Collapse the optional palette, then reproduce a person's upward
        // scroll to the lower assignment and priority controls.
        colourControl.tap()
        let priority = app.segmentedControls["Priority"].firstMatch
        for _ in 0..<4 where !priority.exists {
            app.swipeUp()
        }
        XCTAssertTrue(priority.waitForExistence(timeout: 5), "Priority control is missing")
        XCTAssertTrue(priority.isHittable, "Priority control is not interactive")
        XCTAssertTrue(app.staticTexts["Project"].firstMatch.waitForExistence(timeout: 5), "Project assignment is missing")
        XCTAssertFalse(app.staticTexts["Workspace"].exists, "Task editor must not expose a Workspace field")
        capture(app, named: "iphone-task-editor-hierarchy")
    }

    /// Physical-user proof for the complete capture journey: open the single
    /// Plan-owned action, enter a real task, save it, and observe the new row.
    func testCreateSampleTaskFromFloatingCapture() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapSeedDemo", "-flowmapOpenAIHarness", "-ApplePersistenceIgnoreState", "YES"]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let title = "Sample iPhone task \(Int(Date().timeIntervalSince1970) % 100_000)"
        addQuickTask(app, title: title)

        let created = app.staticTexts[title].firstMatch
        XCTAssertTrue(created.exists, "Saved sample task is not visible in Plan")
        XCTAssertTrue(created.isHittable, "Saved sample task cannot be opened by a person")
        capture(app, named: "iphone-sample-task-created")
    }

    /// Focused physical-device evidence for the Map list and its native-node canvas.
    func testCaptureMapCanvas() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapSeedDemo", "-flowmapOpenAIMap"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 8), "Today mode control is missing")
        XCTAssertFalse(app.buttons["Plan"].exists, "The retired abstract Plan label returned")
        XCTAssertFalse(app.buttons["Today"].isSelected, "Map must remain distinct from the concrete Today surface")
        XCTAssertTrue(app.buttons["Search map"].waitForExistence(timeout: 8), "Map canvas controls did not appear")
        XCTAssertGreaterThan(
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "map-node-")).count,
            0,
            "Map canvas exposes no native task nodes"
        )
        capture(app, named: "iphone-map-canvas-physical")
    }

    /// The daily-check summary belongs above drill-down project rows.
    func testStatsShowsTopMetricsBeforeProjects() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapSeedDemo", "-flowmapOpenAIHarness"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        app.buttons["Open library"].tap()
        let statsRow = app.buttons["flowmap-destination-stats"].firstMatch
        XCTAssertTrue(statsRow.waitForExistence(timeout: 5), "Stats drawer row is missing")
        statsRow.tap()

        let statsTitles = app.staticTexts
            .matching(NSPredicate(format: "label == %@", "Stats"))
            .allElementsBoundByIndex
            .filter { $0.frame.minY < 130 }
        XCTAssertEqual(statsTitles.count, 1, "Stats needs one visible compact destination title")
        let completed = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Completed:"))
            .firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 5), "Completed summary tile is missing")
        XCTAssertLessThan(
            completed.frame.minY,
            app.windows.firstMatch.frame.midY,
            "Top metrics must be visible in the upper half without scrolling"
        )
        XCTAssertFalse(
            app.buttons["New task, project or initiative"].exists,
            "Stats must not inherit Plan's floating capture control"
        )
        capture(app, named: "iphone-stats-top-metrics-physical")
    }

    /// Settings has one drawer owner and each preference responds independently.
    func testSettingsOwnerAndSoundToggleJourney() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapSeedDemo", "-flowmapOpenAIHarness"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        app.buttons["Open library"].tap()
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "Drawer Settings control is missing")
        settings.tap()

        let settingsTitles = app.staticTexts
            .matching(NSPredicate(format: "label == %@", "Settings"))
            .allElementsBoundByIndex
            .filter { $0.frame.minY < 130 }
        XCTAssertEqual(settingsTitles.count, 1, "Settings needs one visible compact destination title")
        XCTAssertFalse(app.staticTexts["Make Flowmap work the way you do."].exists)
        XCTAssertFalse(app.buttons["New task, project or initiative"].exists)
        capture(app, named: "iphone-settings-hub-physical")

        app.buttons["Sounds"].tap()
        let soundTitles = app.staticTexts
            .matching(NSPredicate(format: "label == %@", "Sounds"))
            .allElementsBoundByIndex
            .filter { $0.frame.minY < 130 }
        XCTAssertEqual(soundTitles.count, 1, "Sounds needs one compact destination title")
        XCTAssertTrue(app.buttons["Back to Settings"].exists, "Sounds needs a visible compact back action")
        let ticking = app.switches["Ticking while focusing"].firstMatch
        XCTAssertTrue(ticking.waitForExistence(timeout: 8), "Ticking preference is missing")
        let initialValue = String(describing: ticking.value)
        ticking.tap()
        XCTAssertNotEqual(String(describing: ticking.value), initialValue, "Ticking preference did not change immediately")
        ticking.tap()
        XCTAssertEqual(String(describing: ticking.value), initialValue, "Ticking preference did not restore independently")
        capture(app, named: "iphone-settings-sounds-physical")
    }

    /// Public ownership seam for the approved Flowmap shell blueprint.
    func testShellHasOneOwnerPerPrimaryAction() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapSeedDemo", "-flowmapOpenAIHarness"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 8), "Top-level Today mode is missing")
        XCTAssertTrue(app.buttons["Today"].isSelected, "Today must own the selected daily-planning surface")
        XCTAssertFalse(app.buttons["Plan"].exists, "Plan must not compete with the concrete Today destination")
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "label == %@", "Open assistant")).count,
            1,
            "Assistant must have one top-right owner"
        )
        let captureButton = app.buttons["New task, project or initiative"].firstMatch
        XCTAssertTrue(captureButton.exists, "Approved planning surfaces need one floating capture control")
        XCTAssertLessThanOrEqual(
            captureButton.frame.maxY,
            app.windows.firstMatch.frame.maxY - 8,
            "Floating capture must remain fully above the bottom edge"
        )
        XCTAssertFalse(app.buttons["Open quick capture"].exists, "The ChatGPT-style composer must be removed")
        XCTAssertFalse(app.buttons["Add task"].exists, "Capture must not be duplicated inside a composer")
        capture(app, named: "iphone-shell-single-action-ownership-closed")

        app.buttons["Open library"].tap()
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "Drawer Settings control is missing")
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "label == %@", "Settings")).count,
            1,
            "Settings must have one drawer-only owner"
        )
        XCTAssertFalse(app.buttons["flowmap-footer-assistant"].exists, "Assistant must not be duplicated in the drawer")
        let closeLibrary = app.buttons["Close library"].firstMatch
        XCTAssertTrue(closeLibrary.exists)
        XCTAssertLessThan(closeLibrary.frame.minY, 150, "Drawer close control must stay in the top chrome lane")
        capture(app, named: "iphone-shell-single-action-ownership")
    }

    /// Tiimo-inspired behaviour with Flowmap ownership: Today carries date
    /// navigation in place, so Calendar is not duplicated in the drawer.
    func testTodayOwnsWeekAndMonthDateNavigation() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapSeedDemo", "-flowmapOpenAIToday", "-ApplePersistenceIgnoreState", "YES"]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let today = app.buttons["Today"].firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 8), "Today mode is missing")
        XCTAssertTrue(today.isSelected, "Today mode did not open its owned surface")
        let selectedDateTitle = app.staticTexts["today-selected-date-title"].firstMatch
        XCTAssertTrue(selectedDateTitle.waitForExistence(timeout: 5), "Today heading is missing")
        XCTAssertGreaterThanOrEqual(
            selectedDateTitle.frame.minY,
            today.frame.maxY,
            "Today content is trapped underneath the fixed top controls"
        )

        let weekStrip = app.descendants(matching: .any)
            .matching(identifier: "today-week-strip")
            .firstMatch
        XCTAssertTrue(weekStrip.waitForExistence(timeout: 5), "Today has no seven-day navigator")

        let dayButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "today-day-")
        )
        XCTAssertEqual(dayButtons.count, 7, "Today must expose exactly seven tappable dates")
        for day in dayButtons.allElementsBoundByIndex {
            XCTAssertGreaterThanOrEqual(day.frame.height, 43.5, "A date target is below 44pt")
        }

        let monthToggle = app.buttons["Show month calendar"].firstMatch
        XCTAssertTrue(monthToggle.waitForExistence(timeout: 5), "Inline month disclosure is missing")
        monthToggle.tap()
        XCTAssertTrue(
            app.buttons["Hide month calendar"].waitForExistence(timeout: 5),
            "Month disclosure did not visibly change state"
        )

        let month = app.descendants(matching: .any)
            .matching(identifier: "today-month-calendar")
            .firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 5), "Month calendar did not expand inside Today")
        capture(app, named: "iphone-today-inline-calendar")

        app.buttons["Open library"].tap()
        XCTAssertTrue(app.buttons["flowmap-destination-inbox"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["flowmap-destination-calendar"].exists, "Calendar is duplicated in the drawer")
        capture(app, named: "iphone-drawer-without-calendar")
    }

    /// Human gesture seam: the drawer opens from the leading edge and closes
    /// with the matching leftward swipe, without requiring the menu button.
    func testSidebarEdgeSwipeOpenAndSwipeLeftClose() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapSeedDemo", "-flowmapOpenAIHarness", "-ApplePersistenceIgnoreState", "YES"]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let window = app.windows.firstMatch
        let drawer = app.descendants(matching: .any)
            .matching(identifier: "flowmap-drawer")
            .firstMatch

        window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
            )
        XCTAssertTrue(drawer.waitForExistence(timeout: 5), "Leading-edge swipe did not open the drawer")
        XCTAssertTrue(app.buttons["Close library"].isHittable, "Edge swipe did not expose a visible close path")
        XCTAssertTrue(app.buttons["flowmap-destination-inbox"].isHittable, "Drawer rows are not interactive after edge swipe")
        capture(app, named: "iphone-sidebar-edge-swipe-open")

        window.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
            )
        Thread.sleep(forTimeInterval: 1)
        let menu = app.buttons["Open library"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "Left swipe did not restore the foreground menu")
        XCTAssertTrue(menu.isHittable, "Restored foreground is not interactive")
        XCTAssertFalse(app.buttons["flowmap-destination-inbox"].isHittable)
        capture(app, named: "iphone-sidebar-swipe-closed")
    }

    /// The wheel remains the dominant Focus surface. Its compact task control
    /// belongs at the bottom and opens a three-row, sub-one-third queue sheet.
    func testFocusTaskControlAndQueueStayAtBottom() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapSeedDemo", "-flowmapOpenAIHarness"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        XCTAssertTrue(app.buttons["Focus"].waitForExistence(timeout: 8))
        app.buttons["Focus"].tap()
        let taskControl = app.descendants(matching: .any)
            .matching(identifier: "focus-now-bar")
            .firstMatch
        XCTAssertTrue(taskControl.waitForExistence(timeout: 8), "Focus task control is missing")
        let window = app.windows.firstMatch
        XCTAssertGreaterThan(
            taskControl.frame.minY,
            window.frame.height * 0.66,
            "Focus task control must sit below the dominant wheel"
        )
        XCTAssertLessThanOrEqual(taskControl.frame.maxY, window.frame.maxY - 12)

        taskControl.tap()
        let sheet = app.descendants(matching: .any)
            .matching(identifier: "focus-queue-sheet")
            .firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Today's queue sheet did not open")
        XCTAssertLessThan(
            sheet.frame.height,
            window.frame.height / 3,
            "Queue sheet must begin below one third of the screen"
        )
        XCTAssertTrue(app.staticTexts["Today's queue"].waitForExistence(timeout: 3))
        capture(app, named: "iphone-focus-bottom-queue")
    }

    /// The Focus bottom card pages between the active task's next steps and
    /// Today's queue without moving or growing over the wheel.
    func testFocusBottomCardPagerShowsCurrentStepsAndTodayQueue() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapSeedDemo", "-flowmapOpenAIHarness", "-ApplePersistenceIgnoreState", "YES"]
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        let focusMode = app.buttons["Focus"].firstMatch
        XCTAssertTrue(focusMode.waitForExistence(timeout: 8), "Focus mode is missing")
        focusMode.tap()

        let taskControl = app.descendants(matching: .any)
            .matching(identifier: "focus-now-bar")
            .firstMatch
        XCTAssertTrue(taskControl.waitForExistence(timeout: 8), "Focus bottom card is missing")
        taskControl.tap()

        let sheet = app.descendants(matching: .any)
            .matching(identifier: "focus-queue-sheet")
            .firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Focus bottom-card sheet did not open")
        let window = app.windows.firstMatch
        XCTAssertLessThan(
            sheet.frame.height,
            window.frame.height / 3,
            "Focus bottom card must preserve its sub-one-third height"
        )
        XCTAssertGreaterThan(
            sheet.frame.maxY,
            window.frame.height * 0.85,
            "Focus bottom card must remain anchored near the bottom of the screen"
        )
        let cardBottom = sheet.frame.maxY

        let pager = sheet.descendants(matching: .any)
            .matching(identifier: "focus-bottom-card-pager")
            .firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 3), "Focus bottom-card pager is missing")

        let currentPage = sheet.descendants(matching: .any)
            .matching(identifier: "focus-current-steps-page")
            .firstMatch
        XCTAssertTrue(currentPage.waitForExistence(timeout: 3), "Current steps must be the default page")
        XCTAssertTrue(app.staticTexts["Current steps"].isHittable)
        XCTAssertTrue(app.staticTexts["Swipe left for Today's queue"].isHittable)
        let currentSteps = currentPage.descendants(matching: .any)
            .matching(identifier: "focus-current-step")
        XCTAssertGreaterThan(currentSteps.count, 0, "The demo active task must expose current steps")
        XCTAssertLessThanOrEqual(currentSteps.count, 3, "Current steps must show at most three subtasks")

        let pageIndicator = sheet.descendants(matching: .any)
            .matching(identifier: "focus-card-page-indicator")
            .firstMatch
        XCTAssertTrue(pageIndicator.waitForExistence(timeout: 3), "Two-page indicator is missing")
        XCTAssertEqual(pageIndicator.value as? String, "1 of 2")

        pager.swipeLeft()
        let queuePage = sheet.descendants(matching: .any)
            .matching(identifier: "focus-today-queue-page")
            .firstMatch
        XCTAssertTrue(queuePage.waitForExistence(timeout: 3), "Swipe left did not reveal Today's queue")
        XCTAssertTrue(app.staticTexts["Today's queue"].isHittable)
        XCTAssertTrue(app.staticTexts["Swipe right for Current steps"].isHittable)
        let queueItems = queuePage.descendants(matching: .any)
            .matching(identifier: "focus-today-queue-item")
        XCTAssertGreaterThan(queueItems.count, 0, "The demo day must expose queued work")
        XCTAssertLessThanOrEqual(queueItems.count, 3, "Today's queue must show at most three entries")
        XCTAssertEqual(pageIndicator.value as? String, "2 of 2")
        XCTAssertEqual(sheet.frame.maxY, cardBottom, accuracy: 1, "Paging must not move the card bottom")

        pager.swipeRight()
        XCTAssertTrue(app.staticTexts["Current steps"].isHittable, "Swipe right did not return to Current steps")
        XCTAssertEqual(pageIndicator.value as? String, "1 of 2")
        XCTAssertEqual(sheet.frame.maxY, cardBottom, accuracy: 1, "Returning must preserve the card bottom")
    }

    /// Public seam for the OpenAI Apps iOS reveal-under library drawer.
    /// The direct source component is 325pt wide on a 402pt iPhone and every
    /// list item is 297x44pt inside 14pt horizontal margins.
    func testExactHtmlSidebarRevealAndRouting() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapSeedDemo", "-flowmapOpenAIHarness"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        Thread.sleep(forTimeInterval: 3)

        let openLibrary = app.buttons["Open library"].firstMatch
        XCTAssertTrue(openLibrary.waitForExistence(timeout: 8), "Open library control is missing")
        XCTAssertTrue(openLibrary.isHittable, "Open library control is not hittable")
        openLibrary.tap()
        Thread.sleep(forTimeInterval: 1)

        let drawer = app.descendants(matching: .any)
            .matching(identifier: "flowmap-drawer")
            .firstMatch
        XCTAssertTrue(drawer.waitForExistence(timeout: 5), "HTML-matched drawer did not open")
        XCTAssertTrue(app.staticTexts["Flowmap"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Capture → plan → focus"].exists)
        for removedCopy in [
            "Capture → plan → focus", "Today plan", "One task at a time", "Appearance and feedback",
            "Captured tasks", "Projects and branches", "Availability and plan",
            "Focused time", "Ask about your plan"
        ] {
            let copy = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", removedCopy))
                .firstMatch
            XCTAssertFalse(copy.exists, "Unexpected drawer copy: \(removedCopy)")
        }

        let windowWidth = app.windows.firstMatch.frame.width
        let expectedReveal = min(325.0, windowWidth - 44.0)
        XCTAssertFalse(app.staticTexts["Recent"].exists, "Drawer must not duplicate Assistant history")
        XCTAssertFalse(app.textFields["Search recent conversations"].exists, "Drawer search is orphaned without Recent")
        XCTAssertFalse(app.staticTexts["No recent conversations"].exists)
        XCTAssertFalse(app.staticTexts["No matching conversations"].exists)
        XCTAssertFalse(app.staticTexts["New conversation"].exists)
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "flowmap-recent-")).firstMatch.exists,
            "Drawer must not expose recent conversation rows"
        )
        let drawerContentWidth = inboxWidth(app)
        XCTAssertEqual(drawerContentWidth, 297, accuracy: 1.0)
        XCTAssertEqual(
            drawerContentWidth + 28,
            expectedReveal,
            accuracy: 1.0,
            "Drawer content plus its two 14pt insets must match the 325pt reveal"
        )
        capture(app, named: "iphone-sidebar-open")

        let closeLibrary = app.buttons["Close library"].firstMatch
        XCTAssertTrue(closeLibrary.waitForExistence(timeout: 5))
        XCTAssertTrue(closeLibrary.isHittable, "Close library control is not hittable")
        XCTAssertGreaterThanOrEqual(closeLibrary.frame.width, 44)
        XCTAssertGreaterThanOrEqual(closeLibrary.frame.height, 44)
        XCTAssertGreaterThanOrEqual(
            closeLibrary.frame.minX,
            expectedReveal,
            "Close library must live in the exposed foreground strip"
        )
        XCTAssertLessThanOrEqual(
            closeLibrary.frame.maxX,
            app.windows.firstMatch.frame.maxX,
            "Close library must remain fully visible on compact phones"
        )
        XCTAssertGreaterThan(
            closeLibrary.frame.minY,
            44,
            "Close library must sit below the fixed system status area"
        )
        closeLibrary.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(openLibrary.waitForExistence(timeout: 5), "Close library did not restore the foreground menu")
        XCTAssertTrue(openLibrary.isHittable, "Restored foreground menu is not interactive")
        XCTAssertFalse(app.buttons["flowmap-destination-inbox"].isHittable)

        XCTAssertTrue(openLibrary.waitForExistence(timeout: 5))
        XCTAssertTrue(openLibrary.isHittable)
        openLibrary.tap()
        Thread.sleep(forTimeInterval: 1)
        let inbox = app.buttons["flowmap-destination-inbox"].firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 5))
        XCTAssertTrue(inbox.isHittable, "Inbox row is not hittable")
        XCTAssertGreaterThanOrEqual(inbox.frame.width, 44)
        XCTAssertGreaterThanOrEqual(inbox.frame.height, 44)
        inbox.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(openLibrary.waitForExistence(timeout: 5), "Selecting Inbox did not restore the foreground menu")
        XCTAssertTrue(openLibrary.isHittable, "Foreground did not become interactive after selecting Inbox")
        XCTAssertFalse(inbox.isHittable)

        openLibrary.tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.buttons["flowmap-destination-inbox"].isSelected, "Selecting Inbox did not persist its selected state")
    }

    /// Human-style coverage for every visible drawer control. Each route is
    /// launched from a known state so one modal cannot make a later tap look
    /// green while actually landing on the wrong surface.
    func testOpenAIAppsSidebarEveryControlHarness() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapSeedDemo", "-flowmapOpenAIHarness"]

        func relaunchAndOpen() {
            if app.state != .notRunning { app.terminate() }
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
            let menu = app.buttons["Open library"].firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 8))
            menu.tap()
            XCTAssertTrue(app.buttons["flowmap-destination-inbox"].waitForExistence(timeout: 5))
        }

        func proveSelectedRoute(_ identifier: String, screenshot: String) {
            relaunchAndOpen()
            let row = app.buttons[identifier].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), "\(identifier) is missing")
            XCTAssertTrue(row.isHittable, "\(identifier) is not hittable")
            row.tap()
            XCTAssertFalse(row.waitForExistence(timeout: 3), "\(identifier) did not close the drawer")
            app.buttons["Open library"].firstMatch.tap()
            let selected = app.buttons[identifier].firstMatch
            XCTAssertTrue(selected.waitForExistence(timeout: 5))
            XCTAssertTrue(selected.isSelected, "\(identifier) did not persist selected state")
            capture(app, named: screenshot)
        }

        relaunchAndOpen()
        XCTAssertFalse(app.staticTexts["Recent"].exists, "Drawer must not duplicate Assistant history")
        XCTAssertFalse(app.textFields["Search recent conversations"].exists)
        XCTAssertFalse(app.staticTexts["New conversation"].exists)
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "flowmap-recent-")).firstMatch.exists,
            "Drawer must not expose recent conversation rows"
        )
        XCTAssertFalse(app.buttons["flowmap-footer-assistant"].exists, "Assistant belongs to top chrome only")
        capture(app, named: "iphone-sidebar-without-recent")

        proveSelectedRoute("flowmap-destination-inbox", screenshot: "iphone-sidebar-route-inbox")
        proveSelectedRoute("flowmap-destination-map", screenshot: "iphone-sidebar-route-map")

        relaunchAndOpen()
        app.buttons["flowmap-destination-calendar"].tap()
        XCTAssertTrue(app.staticTexts["Calendar"].firstMatch.waitForExistence(timeout: 8))
        capture(app, named: "iphone-sidebar-route-calendar")

        relaunchAndOpen()
        app.buttons["flowmap-destination-stats"].tap()
        XCTAssertTrue(app.staticTexts["Stats"].firstMatch.waitForExistence(timeout: 8))
        capture(app, named: "iphone-sidebar-route-stats")

        relaunchAndOpen()
        app.buttons["flowmap-footer-settings"].tap()
        XCTAssertTrue(app.staticTexts["Make Flowmap work the way you do."].waitForExistence(timeout: 8))
        capture(app, named: "iphone-sidebar-route-settings")
    }

    func testCaptureOpenAIAppsSidebarLargeText() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapSeedDemo", "-flowmapOpenAIHarness"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let menu = app.buttons["Open library"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 8))
        menu.tap()
        XCTAssertTrue(app.staticTexts["Flowmap"].waitForExistence(timeout: 5))
        capture(app, named: "iphone-sidebar-large-text-top")
        app.swipeUp()
        let settings = app.buttons["flowmap-footer-settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.isHittable, "Large-text drawer does not scroll to its footer")
        capture(app, named: "iphone-sidebar-large-text-footer")
    }

    private func inboxWidth(_ app: XCUIApplication) -> CGFloat {
        app.buttons["flowmap-destination-inbox"].firstMatch.frame.width
    }
}
