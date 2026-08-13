import XCTest

/// Harness Mode (founder /goal 2026-08-10): reproduce a human user's journey —
/// tab through the app, insert a sample task, exercise the rename/edit
/// affordances — asserting the OUTCOME of every step and photographing it.
///
/// Written against the decisions-40/41 structure: tabs are Plan / Focus /
/// Settings; Plan carries a Today | Inbox | Map segmented control; the old
/// Smart-task-views menu is replaced by Browse rows; Calendar is a Plan
/// nav-bar button.
///
/// Step order matters: the BUILD accordions are visited BEFORE the Browse
/// rows because `scrollUntil` only scrolls downwards and BUILD sits above
/// BROWSE — run 2 proved the reverse order strands the viewport below the
/// accordions.
///
/// Runs at any hour: no assertion depends on the auto-plan, so the
/// 20:00–23:59 evening window that empties the demo plan cannot fail it.
/// Focus is photographed in whatever legitimate state the hour produces.
///
/// Run with:
/// ```
/// xcodebuild -scheme Flowmap -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///   -only-testing:FlowmapUITests/HarnessJourneyTests/testHumanJourney test
/// ```
@MainActor
final class HarnessJourneyTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // A failed tap aborts the method regardless (known trap); keeping this
        // true at least lets soft assertions accumulate before that point.
        continueAfterFailure = true
    }

    // MARK: - Helpers (mirrors ScreenshotTests)

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // Each journey must start from its own deterministic workspace. A
        // shared simulator store made a preceding rename or first-run test
        // change this journey's data and produced false failures.
        app.launchArguments += ["-flowmapHarnessClean", "-flowmapSeedDemo"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
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
        let button = app.tabBars.buttons[label].firstMatch
        guard button.waitForExistence(timeout: 10) else {
            XCTFail("Tab \(label) not found")
            return false
        }
        button.tap()
        Thread.sleep(forTimeInterval: 0.6)
        if !button.isSelected {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 0.8)
        }
        guard button.isSelected else {
            XCTFail("Tab \(label) did not become selected after tapping")
            return false
        }
        Thread.sleep(forTimeInterval: 2.0)
        return true
    }

    /// Switches Plan's Today | Inbox | Map segmented control and asserts the
    /// segment took (isSelected), so a swallowed tap fails here rather than
    /// several steps later.
    private func selectPlanSegment(_ app: XCUIApplication, _ title: String) -> Bool {
        // This is the current iOS 26 glass three-way control, not the stock
        // UISegmentedControl from the obsolete build. Query the stable IDs
        // the live accessibility tree exposes rather than its container type.
        let identifier = "plan-segment-\(title.lowercased())"
        let segment = app.buttons[identifier].firstMatch
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

    /// Scrolls until `element` exists — never a blind fixed swipe count
    /// (known trap: swiping a screen that fits derails it). Downwards only;
    /// order journey steps top-to-bottom within a page.
    /// Uses a press-then-drag rather than `swipeUp()`, so a drag that starts
    /// over a tappable row cannot register as a tap on it. Plan's rows carry no
    /// context menu, so the brief press opens nothing.
    private func scrollUntil(_ app: XCUIApplication, _ element: XCUIElement, maxSwipes: Int = 6) -> Bool {
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.2, thenDragTo: end)
            Thread.sleep(forTimeInterval: 0.6)
            swipes += 1
        }
        return element.waitForExistence(timeout: 2)
    }

    /// Map selection shares the viewport with a simultaneous pan recogniser.
    /// A synthetic tap can occasionally be swallowed during the last frame
    /// of an automatic fit, so retry against the visible outcome rather than
    /// trusting the input event.
    private func revealMapChildAction(
        _ app: XCUIApplication,
        node: XCUIElement,
        parentTitle: String
    ) -> XCUIElement? {
        let addChild = app.buttons["Add child task to \(parentTitle)"].firstMatch
        for attempt in 0..<3 {
            if attempt == 0 {
                node.tap()
            } else {
                node.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            if addChild.waitForExistence(timeout: 4) { return addChild }
        }
        XCTFail("Selecting \(parentTitle) did not reveal its add-child control")
        return nil
    }

    /// Pops any accidentally pushed details until Plan's segmented control is
    /// back. One blind back tap is not enough: in run 3 a swipe registered as
    /// a row tap and left extra project screens on the navigation stack.
    private func popToPlan(_ app: XCUIApplication) -> Bool {
        for _ in 0..<8 {
            if app.buttons["plan-segment-inbox"].exists { return true }
            let custom = app.buttons["BackButton"].firstMatch
            let back = custom.exists ? custom : app.navigationBars.buttons.firstMatch
            guard back.exists else { break }
            back.tap()
            Thread.sleep(forTimeInterval: 0.8)
        }
        let onPlan = app.buttons["plan-segment-inbox"].waitForExistence(timeout: 3)
        if !onPlan { XCTFail("Could not navigate back to Plan") }
        return onPlan
    }

    /// Taps a row and asserts the OUTCOME — the expected detail's nav bar —
    /// rather than trusting that the tap landed. This caught a real app defect:
    /// every project link in the accordion activated at once, so a tap on
    /// Learning stranded the user in Life & Fun. Recovers to Plan and retries
    /// once, so a genuinely swallowed tap still gets a second chance.
    private func openDetail(_ app: XCUIApplication, from row: XCUIElement, expecting navTitle: String) -> Bool {
        Thread.sleep(forTimeInterval: 0.8)
        row.tap()
        if app.navigationBars[navTitle].waitForExistence(timeout: 4) { return true }
        guard popToPlan(app), scrollUntil(app, row) else {
            XCTFail("Could not recover to Plan to retry opening \(navTitle)")
            return false
        }
        Thread.sleep(forTimeInterval: 0.8)
        row.tap()
        guard app.navigationBars[navTitle].waitForExistence(timeout: 4) else {
            XCTFail("Tapping the \(navTitle) row did not open its detail")
            return false
        }
        return true
    }

    /// Expands a BUILD accordion whose label is "Title, <count>" (known trap:
    /// the bare title matches nothing).
    private func expandAccordion(_ app: XCUIApplication, titled title: String) -> Bool {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", title)
        let row = app.buttons.matching(predicate).firstMatch
        guard scrollUntil(app, row) else {
            XCTFail("Accordion \(title) not found on Plan")
            return false
        }
        row.tap()
        Thread.sleep(forTimeInterval: 1.0)
        return true
    }

    /// Creates a task through the shell's floating button and asserts the
    /// OUTCOME — the titled row existing — not merely that steps were taken.
    private func addQuickTask(_ app: XCUIApplication, title: String) -> Bool {
        let addButton = app.buttons["New task, project or initiative"].firstMatch
        guard addButton.waitForExistence(timeout: 5) else {
            XCTFail("Floating create button not found")
            return false
        }
        addButton.tap()
        Thread.sleep(forTimeInterval: 0.5)

        let field = app.textFields["Task title"].firstMatch
        guard field.waitForExistence(timeout: 5) else {
            XCTFail("Create card title field not found")
            return false
        }
        var typed = false
        for _ in 0..<4 {
            field.tap()
            if let existing = field.value as? String, !existing.isEmpty, existing != "Task title" {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
            }
            field.typeText(title)
            if (field.value as? String) == title { typed = true; break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard typed else {
            XCTFail("Title field never accepted text (value: \(String(describing: field.value)))")
            return false
        }
        capture(app, named: "journey-03-create-card-filled")

        let keep = app.buttons["Keep task"].firstMatch
        guard keep.waitForExistence(timeout: 3) else {
            XCTFail("Keep-task button not found")
            return false
        }
        for _ in 0..<3 where !keep.isHittable {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.4)
        }
        keep.tap()
        Thread.sleep(forTimeInterval: 0.8)

        let created = app.staticTexts[title].firstMatch
        guard created.waitForExistence(timeout: 5) else {
            XCTFail("Create reported success but no task titled \"\(title)\" appeared")
            return false
        }
        return true
    }

    /// Finishes the shared task card after its caller has opened it. Unlike
    /// `addQuickTask`, this does not assume the new task belongs on the
    /// current screen — Focus and Map both use this exact editor, but only
    /// Plan's Inbox immediately lists every new root.
    private func finishOpenTaskCard(
        _ app: XCUIApplication,
        title: String
    ) -> Bool {
        let field = app.textFields["Task title"].firstMatch
        guard field.waitForExistence(timeout: 8) else {
            XCTFail("Shared task card did not open")
            return false
        }

        field.tap()
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: field
        )
        guard XCTWaiter.wait(for: [focused], timeout: 5) == .completed else {
            XCTFail("Task title field never received keyboard focus")
            return false
        }
        var acceptedTitle = false
        for _ in 0..<3 {
            if let existing = field.value as? String,
               !existing.isEmpty,
               existing != "Task title",
               existing != title {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
            }
            if (field.value as? String) != title {
                field.typeText(title)
            }
            if (field.value as? String) == title {
                acceptedTitle = true
                break
            }
            field.tap()
            Thread.sleep(forTimeInterval: 0.4)
        }
        guard acceptedTitle else {
            XCTFail("Task title field did not contain \(title) (value: \(String(describing: field.value)))")
            return false
        }

        let keep = app.buttons["Keep task"].firstMatch
        guard keep.waitForExistence(timeout: 5) else {
            XCTFail("Shared task card has no Keep task control")
            return false
        }
        keep.tap()
        guard field.waitForNonExistence(timeout: 8) else {
            XCTFail("Keep task did not dismiss the shared task card")
            return false
        }
        return true
    }

    private func openGlobalTaskCard(_ app: XCUIApplication) -> Bool {
        let add = app.buttons["New task, project or initiative"].firstMatch
        guard add.waitForExistence(timeout: 8) else {
            XCTFail("Global create control is missing on the current tab")
            return false
        }
        let titleField = app.textFields["Task title"].firstMatch
        for attempt in 0..<3 {
            if attempt == 0 {
                add.tap()
            } else {
                add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            if titleField.waitForExistence(timeout: 4) { return true }
        }
        XCTFail("Global create control did not open the shared task card")
        return false
    }

    private func openMapChildTaskCard(_ app: XCUIApplication, addChild: XCUIElement) -> Bool {
        let titleField = app.textFields["Task title"].firstMatch
        for attempt in 0..<3 {
            if attempt == 0 {
                addChild.tap()
            } else {
                addChild.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            if titleField.waitForExistence(timeout: 4) { return true }
        }
        XCTFail("Map add-child control did not open the shared task card")
        return false
    }

    /// Switches the canvas to the downward hierarchy the founder requested
    /// and verifies the control's state. This is a real product interaction,
    /// not test-only styling: people can move between the spatial mind-map
    /// and org-chart views without changing the task relationships.
    private func selectTopDownMapLayout(_ app: XCUIApplication) -> Bool {
        let topDown = app.buttons["map-layout-org-chart"].firstMatch
        guard topDown.waitForExistence(timeout: 8) else {
            XCTFail("Map has no Top-down org chart layout control")
            return false
        }
        if !topDown.isSelected {
            topDown.tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
        guard topDown.isSelected else {
            XCTFail("Top-down org chart did not become the selected map layout")
            return false
        }
        return true
    }

    // MARK: - The journey

    func testHumanJourney() {
        let app = launch()

        // 1. Launch lands on Focus — photograph whatever state the hour gives.
        capture(app, named: "journey-01-launch-focus")

        // 2. Plan tab — defaults to the Inbox segment.
        guard tapTab(app, "Plan") else { return }
        capture(app, named: "journey-02-plan-inbox")

        // 3. Insert the sample task; outcome asserted inside the helper.
        let sampleTitle = "Harness sample task"
        guard addQuickTask(app, title: sampleTitle) else { return }
        capture(app, named: "journey-04-sample-in-inbox")

        // 4. Today is a Plan segment, not a tab or a nested swipe action.
        // Drive the stable segmented-control outcome directly; the task's
        // presence on Today is the proof that the page switch worked.
        guard selectPlanSegment(app, "Today") else { return }
        let onToday = app.staticTexts[sampleTitle].firstMatch
        if !onToday.exists { _ = scrollUntil(app, onToday, maxSwipes: 3) }
        XCTAssertTrue(
            onToday.waitForExistence(timeout: 5),
            "Swipe-to-Today did not land \"\(sampleTitle)\" on the Today segment"
        )
        // `exists` is true for a row scrolled past the bottom of the timeline,
        // so the assertion above passed while the capture showed a screen the
        // task was nowhere on. Bring it on screen before photographing it —
        // the harness's evidence is the picture, not the query.
        var pulls = 0
        while !onToday.isHittable && pulls < 4 {
            app.swipeUp()
            pulls += 1
        }
        XCTAssertTrue(
            onToday.isHittable,
            "\"\(sampleTitle)\" is on the Today segment but never scrolls into view"
        )
        capture(app, named: "journey-06-sample-on-today")

        // Back to the Inbox segment for the BUILD accordions.
        guard selectPlanSegment(app, "Inbox") else { return }

        // 6. Projects accordion → project detail → rename via the Title card.
        guard expandAccordion(app, titled: "Projects") else { return }
        capture(app, named: "journey-07-projects-accordion")

        let learning = app.staticTexts["Learning"].firstMatch
        guard scrollUntil(app, learning) else {
            XCTFail("Seeded project Learning not found in accordion")
            return
        }
        guard openDetail(app, from: learning, expecting: "Learning") else { return }

        let titleField = app.textFields["Project title"].firstMatch
        guard titleField.waitForExistence(timeout: 5) else {
            XCTFail("Project detail did not show the editable Title card")
            return
        }
        capture(app, named: "journey-08-project-detail")
        titleField.tap()
        Thread.sleep(forTimeInterval: 0.5)
        titleField.typeText(" Lab\n")
        Thread.sleep(forTimeInterval: 0.8)
        guard (titleField.value as? String) == "Learning Lab" else {
            XCTFail("Typed rename did not land in the Title field (value: \(titleField.value ?? "nil"))")
            return
        }

        guard popToPlan(app) else { return }

        // OUTCOME: renamed title visible in the accordion list.
        XCTAssertTrue(
            app.staticTexts["Learning Lab"].firstMatch.waitForExistence(timeout: 5),
            "Project rename via Title card did not propagate to the Plan list"
        )
        capture(app, named: "journey-09-project-renamed")

        // 7. Initiatives accordion → edit sheet → rename → outcome on the row.
        guard expandAccordion(app, titled: "Initiatives") else { return }
        capture(app, named: "journey-10-initiatives-accordion")

        let initiativeRow = app.staticTexts["Autumn reset"].firstMatch
        guard scrollUntil(app, initiativeRow) else {
            XCTFail("Seeded initiative Autumn reset not found")
            return
        }
        Thread.sleep(forTimeInterval: 0.8)
        initiativeRow.tap()
        Thread.sleep(forTimeInterval: 1.2)

        let initiativeField = app.textFields["Initiative title"].firstMatch
        guard initiativeField.waitForExistence(timeout: 5) else {
            XCTFail("Initiative edit sheet did not present (title field absent)")
            return
        }
        capture(app, named: "journey-11-initiative-sheet")
        initiativeField.tap()
        Thread.sleep(forTimeInterval: 0.5)
        initiativeField.typeText(" 2026")
        let done = app.buttons["Done"].firstMatch
        guard done.waitForExistence(timeout: 3) else {
            XCTFail("Initiative edit sheet has no Done button")
            return
        }
        done.tap()
        Thread.sleep(forTimeInterval: 1.0)

        XCTAssertTrue(
            app.staticTexts["Autumn reset 2026"].firstMatch.waitForExistence(timeout: 5),
            "Initiative rename did not propagate to its Plan row"
        )
        capture(app, named: "journey-12-initiative-renamed")

        // 8. Browse rows (the menu's replacement): All tasks lists the sample.
        // Below BUILD in the layout, so the downward scroll reaches it.
        let allTasksRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "All tasks")
        ).firstMatch
        guard scrollUntil(app, allTasksRow) else {
            XCTFail("Browse row All tasks not found on the Inbox page")
            return
        }
        capture(app, named: "journey-13-browse-rows")
        allTasksRow.tap()
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertTrue(
            app.staticTexts[sampleTitle].firstMatch.waitForExistence(timeout: 5),
            "All-tasks Browse row did not list \"\(sampleTitle)\""
        )
        capture(app, named: "journey-14-all-tasks")
        guard popToPlan(app) else { return }

        // 9. Map segment — the map now lives inside Plan. The segmented
        // control is pinned above the list, so no scrolling is needed.
        guard selectPlanSegment(app, "Map") else { return }
        capture(app, named: "journey-15-plan-map")

        // Map search is a reachable control with a visible clear outcome.
        let mapSearch = app.buttons["map-search"].firstMatch
        guard mapSearch.waitForExistence(timeout: 5) else {
            XCTFail("Map search control not found")
            return
        }
        mapSearch.tap()
        let mapSearchField = app.textFields["Search ideas"].firstMatch
        guard mapSearchField.waitForExistence(timeout: 5) else {
            XCTFail("Map search control did not reveal its search field")
            return
        }
        XCTAssertTrue(mapSearch.isSelected, "Map search control did not expose its shown state")
        mapSearchField.tap()
        mapSearchField.typeText("Harness")
        let clearMapSearch = app.buttons["map-search-clear"].firstMatch
        guard clearMapSearch.waitForExistence(timeout: 5) else {
            XCTFail("Map search text did not reveal its clear control")
            return
        }
        capture(app, named: "journey-15-map-search-filled")
        clearMapSearch.tap()
        XCTAssertTrue(
            clearMapSearch.waitForNonExistence(timeout: 5),
            "Clearing Map search did not remove the clear control"
        )
        XCTAssertEqual(
            mapSearchField.value as? String,
            "",
            "Clearing Map search did not empty the search field"
        )
        capture(app, named: "journey-15-map-search-cleared")
        mapSearch.tap()
        XCTAssertTrue(
            mapSearchField.waitForNonExistence(timeout: 5),
            "Closing Map search did not dismiss its field"
        )

        // 10. Calendar from Plan's nav bar (decision 41), then back.
        let calendar = app.navigationBars.buttons["Calendar"].firstMatch
        guard calendar.waitForExistence(timeout: 5) else {
            XCTFail("Calendar button not found in Plan's nav bar")
            return
        }
        calendar.tap()
        Thread.sleep(forTimeInterval: 1.5)
        capture(app, named: "journey-16-calendar")
        let nextMonth = app.buttons["Next month"].firstMatch
        XCTAssertTrue(nextMonth.waitForExistence(timeout: 5))
        nextMonth.tap()
        let todayButton = app.buttons["Today"].firstMatch
        XCTAssertTrue(
            todayButton.waitForExistence(timeout: 5),
            "Calendar next-month control did not move away from today"
        )
        capture(app, named: "journey-16-calendar-next-month")
        todayButton.tap()
        XCTAssertTrue(
            todayButton.waitForNonExistence(timeout: 5),
            "Calendar Today control did not return to the current month"
        )
        capture(app, named: "journey-16-calendar-today")
        _ = popToPlan(app)

        // 11. Settings → Calendar: verify the native push and the account
        // control's explicit state without starting a permission flow.
        if tapTab(app, "Settings") {
            capture(app, named: "journey-17-settings")
            let calendarSettingsRow = app.buttons["Calendar"].firstMatch
            guard calendarSettingsRow.waitForExistence(timeout: 5) else {
                XCTFail("Settings Calendar row not found")
                return
            }
            calendarSettingsRow.tap()
            let calendarSettingsTitle = app.navigationBars["Calendar"].firstMatch
            guard calendarSettingsTitle.waitForExistence(timeout: 5) else {
                XCTFail("Settings Calendar row did not open Calendar settings")
                return
            }
            let appleConnection = app.buttons["calendar-apple-connection"].firstMatch
            XCTAssertTrue(appleConnection.waitForExistence(timeout: 5))
            XCTAssertEqual(appleConnection.value as? String, "Not connected")
            capture(app, named: "journey-18-settings-calendar")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Calendar"].waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Calendar"].waitForExistence(timeout: 5))
        }

        // 12. Remaining tab — asserted selected by tapTab.
        if tapTab(app, "Focus") { capture(app, named: "journey-19-focus-return") }
    }

    /// Regression test for the wrong-project push that failed journey runs 3-5.
    /// The accordion's expanded rows share ONE `List` cell, and every
    /// `NavigationLink(value:)` in that cell activated together: one tap pushed
    /// all five projects and left the user in the last one, whichever row they
    /// aimed at. Rows are plain Buttons driving `navigationDestination(item:)`
    /// now. Isolated so the loop runs in ~30s, not the journey's six minutes.
    func testProjectRowOpensItsOwnDetail() {
        let app = launch()
        guard tapTab(app, "Plan"), selectPlanSegment(app, "Inbox") else { return }
        guard expandAccordion(app, titled: "Projects") else { return }

        let learning = app.staticTexts["Learning"].firstMatch
        guard scrollUntil(app, learning) else {
            XCTFail("Seeded project Learning not found in the accordion")
            return
        }
        learning.tap()
        Thread.sleep(forTimeInterval: 2.0)

        let opened = app.navigationBars.firstMatch.identifier
        capture(app, named: "repro-project-tap-result")
        XCTAssertEqual(
            opened, "Learning",
            "Tapping the Learning row opened \"\(opened)\" instead of Learning"
        )
    }

    /// The very first screen a new user sees. Launches WITHOUT the demo seed,
    /// so it needs the app's container wiped first:
    /// `xcrun simctl uninstall <udid> com.flowmap.app`.
    ///
    /// Asserts the outcome, not the steps — an off-screen button reports as
    /// existing and taps silently, so the check is that Plan's Inbox actually
    /// arrived.
    func testFirstRunCallToAction() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapHarnessClean"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        Thread.sleep(forTimeInterval: 4)
        // Tab selection is persisted outside the in-memory model store, so a
        // genuine first-run data state may still reopen on Plan or Settings.
        // Navigate to Focus before asserting its first-run empty state.
        guard tapTab(app, "Focus") else { return }

        let title = app.staticTexts["Nothing here yet"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 10),
            "First run did not show the first-run empty state"
        )
        capture(app, named: "firstrun-01-focus-empty")

        let cta = app.buttons["Add your first task"].firstMatch
        XCTAssertTrue(cta.waitForExistence(timeout: 5), "First-run CTA missing")
        cta.tap()
        Thread.sleep(forTimeInterval: 3.0)

        capture(app, named: "firstrun-02-after-tap")
        XCTAssertTrue(
            app.buttons["Inbox"].firstMatch.waitForExistence(timeout: 10),
            "The first-run CTA did not land on Plan's Inbox segment"
        )
    }

    /// TaskMaster 147.3 acceptance journey. Run against a wiped container so
    /// the three authored tasks are the whole map and every visual assertion
    /// is deterministic.
    func testTaskHierarchyJourney() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapHarnessClean"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        Thread.sleep(forTimeInterval: 4)

        // Plan creates the root through the same shared card used everywhere.
        guard tapTab(app, "Plan"), selectPlanSegment(app, "Inbox") else { return }
        guard openGlobalTaskCard(app), finishOpenTaskCard(app, title: "Project A") else { return }
        XCTAssertTrue(app.staticTexts["Project A"].firstMatch.waitForExistence(timeout: 8))

        // Map grows that root directly. The attached + is deliberately a
        // visible 44pt action; a context-menu-only authoring path would fail
        // this human journey.
        guard selectPlanSegment(app, "Map") else { return }
        guard selectTopDownMapLayout(app) else { return }
        let projectNode = app.buttons["Project A"].firstMatch
        guard projectNode.waitForExistence(timeout: 10) else {
            XCTFail("Project A did not appear as a map node")
            return
        }
        Thread.sleep(forTimeInterval: 1.2)
        guard let addChild = revealMapChildAction(app, node: projectNode, parentTitle: "Project A") else { return }
        guard openMapChildTaskCard(app, addChild: addChild) else { return }
        guard finishOpenTaskCard(app, title: "Subtask B") else { return }
        XCTAssertTrue(app.buttons["Subtask B"].firstMatch.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.2)

        // The branch control must really collapse and restore the child.
        let collapse = app.buttons["Collapse Project A branch"].firstMatch
        guard collapse.waitForExistence(timeout: 10) else {
            XCTFail("Expanded Project A branch has no collapse control")
            return
        }
        collapse.tap()
        XCTAssertTrue(app.buttons["Subtask B"].firstMatch.waitForNonExistence(timeout: 5))
        let expand = app.buttons["Expand Project A branch"].firstMatch
        guard expand.waitForExistence(timeout: 10) else {
            XCTFail("Collapsed Project A branch has no expand control")
            return
        }
        expand.tap()
        XCTAssertTrue(app.buttons["Subtask B"].firstMatch.waitForExistence(timeout: 8))

        // Focus must expose the same stable global create control. Before this
        // fix the control was hidden on Focus, making Root C impossible.
        guard tapTab(app, "Focus") else { return }
        guard openGlobalTaskCard(app), finishOpenTaskCard(app, title: "Root C") else { return }

        // Plan proves the child is indented and carries explicit parent text.
        guard tapTab(app, "Plan"), selectPlanSegment(app, "Inbox") else { return }
        let projectLabels = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Project A")
        ).allElementsBoundByIndex
        let projectTitle = projectLabels
            .min(by: { $0.frame.minX < $1.frame.minX })
        let childTitle = app.staticTexts["Subtask B"].firstMatch
        let rootCTitle = app.staticTexts["Root C"].firstMatch
        guard let projectTitle,
              childTitle.waitForExistence(timeout: 8),
              rootCTitle.waitForExistence(timeout: 8) else {
            XCTFail("Plan did not show Project A, Subtask B and Root C")
            return
        }
        XCTAssertGreaterThan(
            childTitle.frame.minX,
            projectTitle.frame.minX + 12,
            "Subtask B is not visually indented beneath Project A"
        )
        XCTAssertTrue(
            app.staticTexts["Child of Project A"].firstMatch.waitForExistence(timeout: 5),
            "Subtask B does not restate its parent in metadata"
        )
        let parentRow = app.descendants(matching: .any)
            .matching(identifier: "Task: Project A")
            .firstMatch
        let dependencyRow = app.descendants(matching: .any)
            .matching(identifier: "Dependency task: Subtask B")
            .firstMatch
        let independentRow = app.descendants(matching: .any)
            .matching(identifier: "Task: Root C")
            .firstMatch
        XCTAssertTrue(parentRow.waitForExistence(timeout: 5))
        XCTAssertTrue(dependencyRow.waitForExistence(timeout: 5))
        XCTAssertTrue(independentRow.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            abs(dependencyRow.frame.minX - parentRow.frame.minX),
            2,
            "A dependency should share its parent's outer card edge"
        )
        XCTAssertLessThan(
            abs(dependencyRow.frame.width - parentRow.frame.width),
            2,
            "A dependency should share its parent's outer card width"
        )
        XCTAssertGreaterThanOrEqual(
            dependencyRow.frame.minY,
            parentRow.frame.maxY,
            "A dependency should sit immediately below its parent"
        )
        XCTAssertGreaterThan(
            independentRow.frame.minY - dependencyRow.frame.maxY,
            dependencyRow.frame.minY - parentRow.frame.maxY,
            "The next root needs more separation than rows inside one dependency group"
        )
        capture(app, named: "iphone-task-hierarchy")
        Thread.sleep(forTimeInterval: 1.0)

        // Map proves Root C is separate: collapsing Project A hides only its
        // child while Root C stays visible. The automatic tree has rebuilt
        // twice since layout selection (Subtask B and Root C); the chosen
        // org-chart orientation must survive those data changes.
        guard selectPlanSegment(app, "Map") else { return }
        let orgChartLayout = app.buttons["map-layout-org-chart"].firstMatch
        XCTAssertTrue(orgChartLayout.waitForExistence(timeout: 8))
        XCTAssertTrue(orgChartLayout.isSelected,
                      "Task changes reset the selected org-chart layout")
        let finalProjectNode = app.buttons["Project A"].firstMatch
        let finalChildNode = app.buttons["Subtask B"].firstMatch
        let finalRootCNode = app.buttons["Root C"].firstMatch
        XCTAssertTrue(finalProjectNode.waitForExistence(timeout: 10))
        XCTAssertTrue(finalChildNode.waitForExistence(timeout: 10))
        XCTAssertTrue(finalRootCNode.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertGreaterThan(
            finalChildNode.frame.midY,
            finalProjectNode.frame.maxY + 8,
            "Subtask B is not below Project A in the org-chart layout"
        )
        XCTAssertLessThan(
            abs(finalRootCNode.frame.midY - finalProjectNode.frame.midY),
            24,
            "Separate top-level tasks do not share the org chart's first row"
        )
        let planSearch = app.navigationBars.buttons["Search"].firstMatch
        XCTAssertTrue(planSearch.waitForExistence(timeout: 5))
        XCTAssertTrue(
            planSearch.isHittable,
            "Embedded Map left Plan's navigation chrome in the tree but off-screen"
        )
        XCTAssertGreaterThan(
            app.buttons["plan-segment-map"].firstMatch.frame.minY,
            planSearch.frame.maxY,
            "Plan's Map segment moved underneath the navigation bar"
        )
        capture(app, named: "iphone-map-task-hierarchy")
        Thread.sleep(forTimeInterval: 1.0)

        let mapCollapse = app.buttons["Collapse Project A branch"].firstMatch
        guard mapCollapse.waitForExistence(timeout: 10) else {
            XCTFail("Project A collapse control never appeared in the map")
            return
        }
        Thread.sleep(forTimeInterval: 1.2)
        mapCollapse.tap()
        XCTAssertTrue(app.buttons["Subtask B"].firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Root C"].firstMatch.exists,
                      "Collapsing Project A incorrectly hid separate root Root C")

        // Deletion policy is non-destructive: deleting Project A promotes its
        // child to a root instead of silently deleting work.
        guard selectPlanSegment(app, "Inbox") else { return }
        let parentRowTitle = app.staticTexts.matching(
            NSPredicate(format: "label == %@", "Project A")
        ).allElementsBoundByIndex
            .min(by: { $0.frame.minX < $1.frame.minX })
        guard let parentRowTitle else {
            XCTFail("Project A row missing before deletion")
            return
        }
        parentRowTitle.swipeLeft()
        let deleteAction = app.buttons["Delete"].firstMatch
        guard deleteAction.waitForExistence(timeout: 5) else {
            XCTFail("Project A swipe did not reveal Delete")
            return
        }
        deleteAction.tap()
        guard app.staticTexts["Delete “Project A”?"].firstMatch.waitForExistence(timeout: 5) else {
            XCTFail("Project A delete confirmation did not appear")
            return
        }
        let confirm = app.buttons["Delete"].firstMatch
        guard confirm.waitForExistence(timeout: 5) else {
            XCTFail("Project A delete confirmation has no Delete action")
            return
        }
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Project A"].firstMatch.waitForNonExistence(timeout: 8))
        XCTAssertTrue(childTitle.waitForExistence(timeout: 8),
                      "Deleting Project A also deleted Subtask B")
        XCTAssertLessThan(abs(childTitle.frame.minX - rootCTitle.frame.minX), 12,
                          "Subtask B was not promoted to the top level after parent deletion")
    }

    /// Focused visual contract for the Plan dependency stack. Unlike the full
    /// human journey above, this launches a deterministic in-memory hierarchy
    /// and reaches the acceptance screenshot without depending on keyboard or
    /// map-authoring timing.
    func testCaptureTaskDependencyStack() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapHarnessClean", "-flowmapHarnessHierarchy"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        Thread.sleep(forTimeInterval: 4)

        // The hierarchy harness opens Plan directly; the segment is the
        // destination-level proof and avoids testing the tab bar twice here.
        guard selectPlanSegment(app, "Inbox") else { return }

        let projectTitle = app.staticTexts["Project A"].firstMatch
        let dependencyTitle = app.staticTexts["Subtask B"].firstMatch
        let independentTitle = app.staticTexts["Root C"].firstMatch
        XCTAssertTrue(projectTitle.waitForExistence(timeout: 8))
        XCTAssertTrue(dependencyTitle.waitForExistence(timeout: 8))
        XCTAssertTrue(independentTitle.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(
            dependencyTitle.frame.minX,
            projectTitle.frame.minX + 12,
            "The dependency title must indent beneath its parent"
        )
        XCTAssertTrue(
            app.staticTexts["Child of Project A"].firstMatch.waitForExistence(timeout: 5),
            "The dependency must restate its parent"
        )

        let parentRow = app.descendants(matching: .any)
            .matching(identifier: "Task: Project A")
            .firstMatch
        let dependencyRow = app.descendants(matching: .any)
            .matching(identifier: "Dependency task: Subtask B")
            .firstMatch
        let independentRow = app.descendants(matching: .any)
            .matching(identifier: "Task: Root C")
            .firstMatch
        XCTAssertTrue(parentRow.waitForExistence(timeout: 5))
        XCTAssertTrue(dependencyRow.waitForExistence(timeout: 5))
        XCTAssertTrue(independentRow.waitForExistence(timeout: 5))
        XCTAssertLessThan(abs(dependencyRow.frame.minX - parentRow.frame.minX), 2)
        XCTAssertLessThan(abs(dependencyRow.frame.width - parentRow.frame.width), 2)
        XCTAssertLessThanOrEqual(
            abs(dependencyRow.frame.minY - parentRow.frame.maxY),
            2,
            "The dependency card must physically join its parent"
        )
        XCTAssertGreaterThan(
            independentRow.frame.minY - dependencyRow.frame.maxY,
            dependencyRow.frame.minY - parentRow.frame.maxY,
            "The next root needs more separation than the joined dependency"
        )

        capture(app, named: "iphone-task-dependency-stack")
    }

    /// Regression coverage for TICKET-425: a parent task with real checklist
    /// items keeps a tappable disclosure footer inside its card.
    func testPlanTaskCardRevealsChecklistFromFooter() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapHarnessClean", "-flowmapHarnessHierarchy"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        Thread.sleep(forTimeInterval: 4)

        guard selectPlanSegment(app, "Inbox") else { return }

        let expand = app.buttons["Expand sub-tasks"].firstMatch
        guard expand.waitForExistence(timeout: 8) else {
            XCTFail("Project A has no collapsed sub-task disclosure footer")
            return
        }
        XCTAssertGreaterThanOrEqual(
            expand.frame.height,
            44,
            "The sub-task disclosure footer must have a 44pt target"
        )
        capture(app, named: "ticket-425-task-card-collapsed")

        expand.tap()
        let checklistItem = app.staticTexts["Prepare project brief"].firstMatch
        XCTAssertTrue(
            checklistItem.waitForExistence(timeout: 5),
            "Expanding Project A did not reveal its inline checklist item"
        )

        if app.textFields["Rename task"].firstMatch.waitForExistence(timeout: 1) {
            XCTFail("Expanding the checklist must not also open the parent task editor")
            return
        }

        let collapse = app.buttons["Collapse sub-tasks"].firstMatch
        guard collapse.waitForExistence(timeout: 5) else {
            XCTFail("The expanded footer did not expose its collapse action")
            return
        }
        let parentCard = app.otherElements["Task: Project A"].firstMatch
        XCTAssertGreaterThan(checklistItem.frame.minY, parentCard.frame.minY)
        XCTAssertLessThan(checklistItem.frame.maxY, parentCard.frame.maxY)
        XCTAssertGreaterThan(collapse.frame.minY, checklistItem.frame.maxY)
        capture(app, named: "ticket-425-task-card-expanded")

        collapse.tap()
        XCTAssertTrue(
            checklistItem.waitForNonExistence(timeout: 5),
            "Collapsing Project A did not hide its inline checklist item"
        )
    }

    /// Human-facing controls for TICKET-425 must each change the visible
    /// state that their label promises: direct edit, swipe edit, long-press
    /// edit, completion, and inline sub-task completion.
    func testPlanTaskCardControlsJourney() {
        let app = XCUIApplication()
        app.launchArguments += ["-flowmapHarnessClean", "-flowmapHarnessHierarchy"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        Thread.sleep(forTimeInterval: 4)

        guard selectPlanSegment(app, "Inbox") else { return }

        // Ordinary content tap opens the inline editor and a second tap closes it.
        let projectContent = app.buttons["Project A"].firstMatch
        guard projectContent.waitForExistence(timeout: 8) else {
            XCTFail("Project A task content is not tappable")
            return
        }
        projectContent.tap()
        let projectEditor = app.textFields["Rename task"].firstMatch
        XCTAssertTrue(projectEditor.waitForExistence(timeout: 5))
        capture(app, named: "ticket-425-direct-edit")
        let green = app.buttons["Green"].firstMatch
        XCTAssertTrue(green.waitForExistence(timeout: 5))
        green.tap()
        XCTAssertTrue(green.isSelected, "Choosing Green did not update Project A's task colour")
        capture(app, named: "ticket-425-colour-changed-in-plan")
        projectContent.tap()
        XCTAssertTrue(projectEditor.waitForNonExistence(timeout: 5))

        // The protected trailing swipe exposes its explicit Edit action.
        let rootContent = app.buttons["Root C"].firstMatch
        rootContent.swipeLeft()
        let swipeEdit = app.buttons["Edit"].firstMatch
        guard swipeEdit.waitForExistence(timeout: 5) else {
            XCTFail("Trailing swipe did not expose Edit")
            return
        }
        capture(app, named: "ticket-425-trailing-edit")
        swipeEdit.tap()
        XCTAssertTrue(projectEditor.waitForExistence(timeout: 5))
        rootContent.tap()
        XCTAssertTrue(projectEditor.waitForNonExistence(timeout: 5))

        // The long-press menu exposes the same explicit editing outcome.
        projectContent.press(forDuration: 1.0)
        let longPressEdit = app.buttons["Edit task"].firstMatch
        guard longPressEdit.waitForExistence(timeout: 5) else {
            XCTFail("Long press did not expose Edit task")
            return
        }
        capture(app, named: "ticket-425-long-press-edit")
        longPressEdit.tap()
        XCTAssertTrue(projectEditor.waitForExistence(timeout: 5))
        projectContent.tap()
        XCTAssertTrue(projectEditor.waitForNonExistence(timeout: 5))

        // Completion remains a separate trailing control and never opens editing.
        let rootCard = app.otherElements["Task: Root C"].firstMatch
        let complete = rootCard.buttons["Mark task complete"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()
        XCTAssertTrue(
            rootCard.waitForNonExistence(timeout: 5),
            "Completing an Inbox task did not remove it from the open-task list"
        )
        XCTAssertTrue(projectEditor.waitForNonExistence(timeout: 1))
        capture(app, named: "ticket-425-task-completed")

        // The child completion control is independent from the disclosure footer.
        let expand = app.buttons["Expand sub-tasks"].firstMatch
        expand.tap()
        let childComplete = app.buttons["Prepare project brief"].firstMatch
        guard childComplete.waitForExistence(timeout: 5) else {
            XCTFail("Expanded checklist has no completion control")
            return
        }
        childComplete.tap()
        XCTAssertEqual(childComplete.value as? String, "Completed")
        capture(app, named: "ticket-425-subtask-completed")

        // Map is derived from the same stored token, so the user-set colour
        // must survive the surface change without a second map-only setting.
        guard selectPlanSegment(app, "Map") else { return }
        XCTAssertTrue(app.buttons["Project A"].firstMatch.waitForExistence(timeout: 8))
        capture(app, named: "ticket-425-colour-propagated-to-map")
    }

}
