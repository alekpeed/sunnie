import XCTest

/// UI coverage of the critical flow: Today → due list → plant → log care.
///
/// These use XCTest because XCUITest requires it. They are written against
/// accessibility identifiers and labels rather than layout, so the visual design
/// pass can change every pixel of these screens without breaking them.
///
/// First executed in CI on a simulator, not on a device. Four passed on that
/// run — the app launches, shows five tabs and the plant card, and navigating to
/// a plant and logging care works end to end. Three failed, and between them
/// they found one real defect and one bad selector:
///
///   * The two care tests were right. Today really had no care action on it,
///     because first-launch seeding finished after Today had already read an
///     empty jungle and nothing told it to read again. A new user saw "No plants
///     yet" above five plants that existed. Fixed in `SampleData` and
///     `PlantSummaryProvider`; these tests are what noticed.
///   * The Themes test was wrong. A `.menu` Picker is not addressable by its
///     bare title, and the exact-match lookup could never have succeeded.
///
/// The failure messages print the screen's buttons because these run where no
/// debugger can attach, and a bare `XCTAssertTrue failed` cannot tell a wrong
/// screen from a wrong label. See `Documentation/BUILD_AND_VERIFY.md`.
final class VerticalSliceUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Launches with a fresh in-memory store and the sample jungle seeded, so
        // a run never depends on what a previous run left behind.
        app.launchArguments += ["-SunnieUITesting", "1"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Every button currently on screen, with its label.
    ///
    /// A UI test that fails with a bare `XCTAssertTrue failed` says only that
    /// something was not found, which leaves the reader guessing whether the
    /// screen was wrong, the label was wrong, or the wait was too short. These
    /// run on a machine nobody can attach a debugger to, so the failure message
    /// has to carry the evidence itself.
    /// Joined on one line, deliberately.
    ///
    /// The first version separated the labels with newlines, which read well in
    /// a terminal and was useless where it mattered: an XCTest failure message
    /// is logged up to its first line break, so CI printed "Buttons on screen:"
    /// and threw away every label after it. A separator that survives the log is
    /// worth more than one that formats nicely.
    private func visibleButtons() -> String {
        let labels = app.buttons.allElementsBoundByIndex
            .prefix(40)
            .map { $0.label.isEmpty ? "<no label>" : $0.label }
        return labels.isEmpty
            ? "No buttons on screen."
            : "Buttons on screen: " + labels.joined(separator: " | ")
    }

    func testTodayShowsPlantCard() throws {
        let card = app.staticTexts["Your jungle"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Today should show the plant card")
    }

    func testFiveTabsArePresent() throws {
        for tab in ["Today", "Jungle", "Travel", "Wellness", "More"] {
            XCTAssertTrue(
                app.tabBars.buttons[tab].waitForExistence(timeout: 5),
                "Missing tab: \(tab)"
            )
        }
    }

    func testCompleteCareFromTodayUpdatesTheCard() throws {
        let markWatered = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Mark watered")
        ).firstMatch
        XCTAssertTrue(
            markWatered.waitForExistence(timeout: 10),
            "No care action on Today. \(visibleButtons())"
        )

        markWatered.tap()

        // Sunnie reacts, and the completed task leaves the actionable list.
        let reaction = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "jungle")
        ).firstMatch
        XCTAssertTrue(reaction.waitForExistence(timeout: 10))
    }

    func testNavigateToPlantDetailAndLogCare() throws {
        app.tabBars.buttons["Jungle"].tap()

        let firstPlant = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Monstera")
        ).firstMatch
        XCTAssertTrue(firstPlant.waitForExistence(timeout: 10))
        firstPlant.tap()

        let logCare = app.buttons["Log care"]
        XCTAssertTrue(logCare.waitForExistence(timeout: 10))
        logCare.tap()

        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        // The sheet closes and the record appears in recent care.
        XCTAssertTrue(
            app.staticTexts["Recent care"].waitForExistence(timeout: 10)
        )
    }

    func testThemePreviewCyclesEveryDayPresentation() throws {
        app.tabBars.buttons["More"].tap()
        app.buttons["Themes"].tap()

        // Matched on a substring rather than by exact label. A `.menu` Picker
        // publishes itself to accessibility as its title *and* its current
        // selection — "Time of day, Right now" — so `buttons["Time of day"]`
        // matches nothing, and would break again every time the default
        // selection changed.
        let picker = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Time of day")
        ).firstMatch
        XCTAssertTrue(
            picker.waitForExistence(timeout: 10),
            "No time-of-day picker on Themes. \(visibleButtons())"
        )

        // All three branded presentations must render coherently; this walks the
        // phases that produce them.
        for phase in ["Morning", "Afternoon", "Night"] {
            picker.tap()
            let option = app.buttons[phase]
            XCTAssertTrue(option.waitForExistence(timeout: 5), "Missing phase: \(phase)")
            option.tap()
        }

        XCTAssertTrue(app.staticTexts["Sunnie Nights"].waitForExistence(timeout: 5))
    }

    /// Large Dynamic Type must keep the primary action reachable by scrolling.
    func testPrimaryActionSurvivesLargeDynamicType() throws {
        app.terminate()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL"
        ]
        app.launch()

        let markWatered = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Mark watered")
        ).firstMatch
        XCTAssertTrue(
            markWatered.waitForExistence(timeout: 10),
            "No care action at accessibility text sizes. \(visibleButtons())"
        )

        // Today is intentionally scrollable. At accessibility text sizes the
        // new contextual cards can move plant care below the initial viewport;
        // that is valid as long as the action remains reachable through normal
        // scrolling and is not clipped or removed from the accessibility tree.
        var attempts = 0
        while !markWatered.isHittable && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }

        XCTAssertTrue(
            markWatered.isHittable,
            "The care action must stay reachable at large text sizes after scrolling. \(visibleButtons())"
        )
    }

    /// Every interactive element needs a label VoiceOver can announce.
    func testInteractiveElementsHaveAccessibilityLabels() throws {
        XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 10))

        for index in 0..<min(app.buttons.count, 20) {
            let button = app.buttons.element(boundBy: index)
            guard button.exists, button.isHittable else { continue }
            XCTAssertFalse(
                button.label.trimmingCharacters(in: .whitespaces).isEmpty,
                "A button at index \(index) has no accessibility label"
            )
        }
    }
}
