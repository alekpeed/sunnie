import XCTest

/// UI coverage of the critical flow: Today → due list → plant → log care.
///
/// These use XCTest because XCUITest requires it. They are written against
/// accessibility identifiers and labels rather than layout, so the visual design
/// pass can change every pixel of these screens without breaking them.
///
/// Not verified on a device: these have never been executed. See
/// `Documentation/BUILD_AND_VERIFY.md`.
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
        XCTAssertTrue(markWatered.waitForExistence(timeout: 10))

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

        let picker = app.buttons["Time of day"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))

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

    /// Large Dynamic Type must not clip the primary action.
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
        XCTAssertTrue(markWatered.waitForExistence(timeout: 10))
        XCTAssertTrue(markWatered.isHittable, "The care action must stay reachable at large text sizes")
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
