import XCTest

/// First execution of the screens nobody has ever opened.
///
/// Everything outside the plant-care slice — Travel, Meals, Games, Collections,
/// Sunnie's Home, Journal, Settings — has unit tests passing beneath it and has
/// never been rendered. That gap is where this project's defects have lived:
/// travel returned no trips at all, the hydration catch-up queue silently
/// matched nothing, and Today showed "No plants yet" above five plants. Each of
/// those passed its unit tests and was wrong the moment it ran.
///
/// So these are deliberately shallow and wide. They open every screen and ask
/// three questions:
///
///   1. Does it render at all, or does the app die getting there?
///   2. Does it show a load failure? Every failure string in this app begins
///      "I couldn't", which makes the whole class detectable generically.
///   3. Where content ships with the app and cannot legitimately be empty, is
///      it actually there?
///
/// The third is the one that would have caught travel. An empty screen and a
/// broken screen look identical from outside, so the only way to tell them
/// apart is to know what *must* be present and say so.
final class ScreenWalkUITests: XCTestCase {

    private var app: XCUIApplication!

    /// The app's own failure copy, which is uniform by design
    /// (TONE_COPY_AND_BEHAVIOR.md): every load error opens "I couldn't".
    private static let failurePrefix = "I couldn't"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-SunnieUITesting", "1"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Diagnostics

    /// Static text currently on screen, on one line.
    ///
    /// One line because XCTest logs a failure message only as far as its first
    /// line break — a lesson from the last round, where a carefully formatted
    /// multi-line diagnostic arrived in CI as a heading with nothing under it.
    private func visibleTexts(limit: Int = 30) -> String {
        let labels = app.staticTexts.allElementsBoundByIndex
            .prefix(limit)
            .map(\.label)
            .filter { !$0.isEmpty }
        return labels.isEmpty
            ? "No text on screen."
            : "On screen: " + labels.joined(separator: " | ")
    }

    /// Whether some text is on screen, as static text *or* as a control's label.
    ///
    /// Both, always, because which one a piece of text becomes is not a property
    /// of the text — it is a property of whether an ancestor merged its children
    /// for VoiceOver. The Jungle rows do (`accessibilityElement(children:
    /// .combine)`), so a plant name there is a button label and no static text
    /// carries it; the games list does not, so its names may be either. Asserting
    /// on the shape rather than the presence is how the Themes picker test came
    /// to be permanently red against working code.
    private func existsAnywhere(_ text: String) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        return app.staticTexts.matching(predicate).firstMatch.exists
            || app.buttons.matching(predicate).firstMatch.exists
    }

    /// The same question, but willing to wait for a screen that is still loading.
    private func waitForAnywhere(_ text: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let asText = app.staticTexts.matching(predicate).firstMatch
        if asText.waitForExistence(timeout: timeout) { return true }
        return app.buttons.matching(predicate).firstMatch.exists
    }

    /// Fails if the screen is showing one of the app's load-failure messages.
    private func assertNoLoadFailure(_ screen: String) {
        let failure = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", Self.failurePrefix)
        ).firstMatch
        XCTAssertFalse(
            failure.exists,
            "\(screen) is showing a load failure: \(failure.label)"
        )
    }

    // MARK: - Navigation helpers

    /// Opens one row of the More tab and waits for its screen.
    ///
    /// Matched on a substring rather than an exact label: the row combines its
    /// icon, title, and chevron into one accessibility element, and the exact
    /// text that produces is not worth depending on.
    @discardableResult
    private func openFromMore(_ title: String) -> Bool {
        app.tabBars.buttons["More"].tap()

        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", title)
        ).firstMatch
        guard row.waitForExistence(timeout: 10) else {
            XCTFail("No '\(title)' row on More. \(visibleTexts())")
            return false
        }
        row.tap()

        let bar = app.navigationBars[title]
        guard bar.waitForExistence(timeout: 10) else {
            XCTFail("Tapping '\(title)' did not open its screen. \(visibleTexts())")
            return false
        }
        return true
    }

    /// Back to More, so one test can walk several destinations in a launch.
    private func returnToMore() {
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "More")
        ).firstMatch
        if back.exists { back.tap() }
    }

    // MARK: - The walk

    /// Opens all seven More destinations in one launch.
    ///
    /// The cheapest question worth asking, and the one no unit test answers: does
    /// the app survive being navigated? A screen that traps on an unwrapped
    /// value or a missing content id takes the whole process down, and every
    /// later assertion in this file would then fail for a reason that has
    /// nothing to do with it.
    func testEveryMoreDestinationOpens() throws {
        let destinations = [
            "Meals", "Games", "Journal", "Collections",
            "Sunnie's Home", "Themes", "Settings"
        ]

        for destination in destinations {
            guard openFromMore(destination) else { return }
            assertNoLoadFailure(destination)
            returnToMore()
        }
    }

    /// Every tab renders, and none of them opens onto a failure.
    func testEveryTabRendersWithoutFailure() throws {
        for tab in ["Today", "Jungle", "Travel", "Wellness", "More"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing tab: \(tab)")
            button.tap()

            // Give the screen's own load a moment before judging it, so a slow
            // fetch is not mistaken for a failure.
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 5)
            assertNoLoadFailure(tab)
        }
    }

    /// The games list must not be empty, because its content is compiled in.
    ///
    /// Seven games ship as Swift rather than JSON (ADR-022), so unlike Travel or
    /// Journal there is no legitimate empty state here on a fresh install. An
    /// empty Games screen means the content did not reach the view, which is
    /// precisely the defect that once reduced the whole app to a single theme —
    /// content present in the bundle, absent on screen, and silent about it.
    func testGamesScreenListsTheShippedGames() throws {
        guard openFromMore("Games") else { return }
        assertNoLoadFailure("Games")

        // Not all seven need to be on screen at once — the list scrolls, and
        // asserting on layout is what this suite deliberately avoids. Finding
        // none of them is the finding.
        let names = [
            "Word Layover", "Postcard Cipher", "Jungle Logic", "Memory Atlas",
            "Lost in Translation", "Sunnie's Suitcase", "Trivia Trail"
        ]
        let found = names.filter { existsAnywhere($0) }

        XCTAssertFalse(
            found.isEmpty,
            "Games shipped seven games and the screen shows none of them. \(visibleTexts())"
        )
    }

    /// The jungle must show the plants first launch seeded.
    ///
    /// The counterpart to the Today bug: five plants are written on first launch,
    /// so a jungle that looks empty is a reading fault rather than a true empty
    /// state. Named plants make that unambiguous.
    func testJungleShowsTheSeededPlants() throws {
        app.tabBars.buttons["Jungle"].tap()

        XCTAssertTrue(
            waitForAnywhere("Monstera"),
            "The seeded jungle is not on the Jungle screen. \(visibleTexts())"
        )
        assertNoLoadFailure("Jungle")
    }

    /// Travel opens, and says something rather than nothing.
    ///
    /// No trips are seeded, so an empty state here is correct and this cannot
    /// assert on trip content. What it can assert is that the screen is not
    /// blank and not failing — the state travel was actually in for months,
    /// where a working empty state and a broken fetch were indistinguishable.
    func testTravelOpensAndSaysSomething() throws {
        app.tabBars.buttons["Travel"].tap()

        XCTAssertTrue(
            app.navigationBars["Travel"].waitForExistence(timeout: 10),
            "Travel did not open. \(visibleTexts())"
        )
        assertNoLoadFailure("Travel")

        // An empty state is copy, not an absence of copy. A screen with nothing
        // on it at all is a different thing and is worth failing on.
        let anyText = app.staticTexts.matching(
            NSPredicate(format: "label.length > 3")
        ).firstMatch
        XCTAssertTrue(
            anyText.waitForExistence(timeout: 5),
            "Travel rendered with no text of any kind. \(visibleTexts())"
        )
    }

    /// Wellness opens and offers its check-in.
    func testWellnessOpensAndOffersCheckIn() throws {
        app.tabBars.buttons["Wellness"].tap()

        XCTAssertTrue(
            app.navigationBars["Wellness"].waitForExistence(timeout: 10),
            "Wellness did not open. \(visibleTexts())"
        )
        assertNoLoadFailure("Wellness")

        let anyControl = app.buttons.matching(
            NSPredicate(format: "label.length > 2")
        ).firstMatch
        XCTAssertTrue(
            anyControl.waitForExistence(timeout: 5),
            "Wellness offered nothing to tap. \(visibleTexts())"
        )
    }

    /// Settings opens and is not empty.
    ///
    /// Worth its own test because Settings reads more subsystems than any other
    /// screen — permissions, storage, audio, export — and a fault in any of them
    /// surfaces here first.
    func testSettingsOpensWithItsSections() throws {
        guard openFromMore("Settings") else { return }
        assertNoLoadFailure("Settings")

        let anyRow = app.staticTexts.matching(
            NSPredicate(format: "label.length > 3")
        ).firstMatch
        XCTAssertTrue(
            anyRow.waitForExistence(timeout: 5),
            "Settings rendered with no rows. \(visibleTexts())"
        )
    }
}
