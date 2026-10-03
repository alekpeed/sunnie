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

        // Named copy, not "some text". The first version of this asked for any
        // label over three characters, which the tab bar alone satisfies — it
        // would have passed on a completely blank Travel screen. An assertion
        // that cannot fail is worse than none, because it reports success.
        //
        // No trips are seeded, so the empty state is the correct outcome here
        // and its own copy is what proves the screen rendered its body.
        XCTAssertTrue(
            waitForAnywhere("Nothing planned") || existsAnywhere("Plan a trip"),
            "Travel rendered without its own content. \(visibleTexts())"
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

        // Wellness's own words rather than "any button" — the tab bar would
        // have satisfied that on an otherwise empty screen.
        XCTAssertTrue(
            waitForAnywhere("How are you right now?") || existsAnywhere("Check in"),
            "Wellness did not offer its check-in. \(visibleTexts())"
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

        // Two named sections, so a Settings screen that rendered its chrome and
        // none of its content still fails.
        XCTAssertTrue(
            waitForAnywhere("Time of day") || existsAnywhere("Sound"),
            "Settings rendered without its sections. \(visibleTexts())"
        )
    }

    // MARK: - The deeper walk
    //
    // The first pass proved every screen opens. These go a level in, to the
    // sub-screens and the write paths — which is where the defects have actually
    // been. All three real bugs so far were repository reads, and a screen that
    // renders is no evidence at all about the fetch behind the next one.

    /// The three lists behind Meals, each with its own repository.
    func testMealsSubScreensOpen() throws {
        guard openFromMore("Meals") else { return }

        // Labels, not routes: "Shopping list" and "What's in" are what the rows
        // say, and the nav titles they push to are the same strings.
        for destination in ["Shopping list", "What's in", "Recipes"] {
            let row = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", destination)
            ).firstMatch
            guard row.waitForExistence(timeout: 10) else {
                XCTFail("No '\(destination)' row on Meals. \(visibleTexts())")
                return
            }
            row.tap()

            XCTAssertTrue(
                app.navigationBars[destination].waitForExistence(timeout: 10),
                "'\(destination)' did not open. \(visibleTexts())"
            )
            assertNoLoadFailure(destination)

            let back = app.navigationBars.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Meals")
            ).firstMatch
            if back.exists { back.tap() }
        }
    }

    /// Travel's saved places, which read through the travel repository.
    ///
    /// Worth its own test because that repository is where the null-column
    /// predicate emptied four surfaces at once. Places is a different fetch on
    /// the same store, and it has never run.
    func testTravelPlacesOpens() throws {
        app.tabBars.buttons["Travel"].tap()

        let places = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Places")
        ).firstMatch
        guard places.waitForExistence(timeout: 10) else {
            XCTFail("No route into Places from Travel. \(visibleTexts())")
            return
        }
        places.tap()

        XCTAssertTrue(
            app.navigationBars["Places"].waitForExistence(timeout: 10),
            "Places did not open. \(visibleTexts())"
        )
        assertNoLoadFailure("Places")
    }

    /// A plant's health and growth screens, two more never-run fetches.
    func testPlantDetailSubScreensOpen() throws {
        app.tabBars.buttons["Jungle"].tap()

        let plant = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Monstera")
        ).firstMatch
        guard plant.waitForExistence(timeout: 10) else {
            XCTFail("No seeded plant to open. \(visibleTexts())")
            return
        }
        plant.tap()

        for section in ["What you've noticed", "How it's grown"] {
            let link = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", section)
            ).firstMatch
            guard link.waitForExistence(timeout: 10) else {
                XCTFail("No '\(section)' on the plant. \(visibleTexts())")
                return
            }
            link.tap()

            XCTAssertTrue(
                app.navigationBars[section].waitForExistence(timeout: 10),
                "'\(section)' did not open. \(visibleTexts())"
            )
            assertNoLoadFailure(section)

            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    /// Write an entry, then find it again.
    ///
    /// The first write path any of these tests exercises, and deliberately the
    /// journal's: this is the repository whose search predicate threw on every
    /// query while being documented as fixed. A create-then-read round trip is
    /// the shape that catches that class, because it makes the store answer for
    /// what it was just told.
    func testJournalRoundTripsAnEntry() throws {
        guard openFromMore("Journal") else { return }
        assertNoLoadFailure("Journal")

        let newEntry = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "New entry")
        ).firstMatch
        guard newEntry.waitForExistence(timeout: 10) else {
            XCTFail("No way to start an entry. \(visibleTexts())")
            return
        }
        newEntry.tap()

        guard app.navigationBars["Entry"].waitForExistence(timeout: 10) else {
            XCTFail("The journal editor did not open. \(visibleTexts())")
            return
        }

        // A title rather than the body: a title is a TextField, which XCUITest
        // types into reliably, while the body is a TextEditor and is not worth
        // the flakiness when either proves the same round trip.
        let title = app.textFields.firstMatch
        guard title.waitForExistence(timeout: 5) else {
            XCTFail("The editor offered no title field. \(visibleTexts())")
            return
        }
        title.tap()

        // Distinctive enough that finding it later cannot be a coincidence.
        let text = "Walkthrough entry 4718"
        title.typeText(text)

        let done = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Done")
        ).firstMatch
        guard done.waitForExistence(timeout: 5) else {
            XCTFail("No Done button in the editor. \(visibleTexts())")
            return
        }
        done.tap()

        XCTAssertTrue(
            waitForAnywhere(text),
            "The entry saved but does not appear in the journal. \(visibleTexts())"
        )
        assertNoLoadFailure("Journal")
    }

    /// Starting a game has to actually open one.
    ///
    /// The interesting failure is silent: choosing a difficulty calls into the
    /// engine and pushes only if it returns a session, so a nil there leaves the
    /// player looking at the list they just tapped, with nothing said. Asserting
    /// that the Games screen is behind us is what distinguishes that from a
    /// puzzle opening.
    func testStartingAGameOpensIt() throws {
        guard openFromMore("Games") else { return }

        let game = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Jungle Logic")
        ).firstMatch
        guard game.waitForExistence(timeout: 10) else {
            XCTFail("Jungle Logic is not on the games list. \(visibleTexts())")
            return
        }
        game.tap()

        guard waitForAnywhere("How it works", timeout: 10) else {
            XCTFail("Tapping a game offered no difficulty choice. \(visibleTexts())")
            return
        }

        let gentle = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Gentle")
        ).firstMatch
        guard gentle.waitForExistence(timeout: 5) else {
            XCTFail("No difficulty to choose. \(visibleTexts())")
            return
        }
        gentle.tap()

        let leftTheList = app.navigationBars["Games"].waitForNonExistence(timeout: 15)
        XCTAssertTrue(
            leftTheList,
            "Choosing a difficulty did not open a puzzle. \(visibleTexts())"
        )
    }

    // MARK: - Compiled-in content that cannot legitimately be empty
    //
    // The strongest assertion available without seeded data. Where content ships
    // as Swift, a fresh install has no honest empty state, so an empty screen
    // means the content never reached the view — silently, which is exactly how
    // `ColorValue` once reduced the app to one theme.
    //
    // Collections is deliberately *not* tested this way: it filters by whether
    // an item has been earned, so an empty list there is a legitimate first-run
    // state and an assertion would be wrong rather than strict.

    /// Sunnie's Home renders its slots whether or not anything is in them.
    ///
    /// The slots come from the compiled-in definitions and are rows in the view,
    /// so they appear on an untouched install. That makes them structural: no
    /// slots means the definitions did not arrive, not that the room is bare.
    func testSunnieHomeShowsItsSlots() throws {
        guard openFromMore("Sunnie's Home") else { return }
        assertNoLoadFailure("Sunnie's Home")

        let slots = [
            "The shelf", "The wall", "The floor",
            "The plant stand", "The hanger", "The potting bench", "The travel shelf"
        ]
        let found = slots.filter { existsAnywhere($0) }

        XCTAssertFalse(
            found.isEmpty,
            "Sunnie's Home has seven compiled-in slots and shows none. \(visibleTexts())"
        )
    }

    /// Wellness offers the calm practices that ship with the app.
    ///
    /// The ambiences are synthesised rather than recorded, so unlike the music —
    /// which is declared against files nobody has recorded — these genuinely
    /// exist on a fresh install with no assets and no account.
    func testWellnessOffersItsPractices() throws {
        app.tabBars.buttons["Wellness"].tap()

        guard app.navigationBars["Wellness"].waitForExistence(timeout: 10) else {
            XCTFail("Wellness did not open. \(visibleTexts())")
            return
        }
        assertNoLoadFailure("Wellness")

        let expected = ["A quiet moment", "Soft rain", "Ocean waves", "Quiet café", "Jungle"]
        let found = expected.filter { existsAnywhere($0) }

        XCTAssertFalse(
            found.isEmpty,
            "Wellness offers none of its shipped practices or ambiences. \(visibleTexts())"
        )
    }

    /// The full plant list behind Jungle, which is a different fetch again.
    ///
    /// Reached through the toolbar menu, not directly. The first version of this
    /// looked for "All plants" on the Jungle screen and did not find it, because
    /// the row lives inside an "Options" menu that has to be opened first — a
    /// wrong interaction rather than a wrong label, and one the failure message
    /// diagnosed itself by printing what actually was on screen.
    func testJungleAllPlantsListsThem() throws {
        app.tabBars.buttons["Jungle"].tap()

        let options = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Options")
        ).firstMatch
        guard options.waitForExistence(timeout: 10) else {
            XCTFail("No options menu on Jungle. \(visibleTexts())")
            return
        }
        options.tap()

        let allPlants = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "All plants")
        ).firstMatch
        guard allPlants.waitForExistence(timeout: 10) else {
            XCTFail("No 'All plants' in the options menu. \(visibleTexts())")
            return
        }
        allPlants.tap()

        guard app.navigationBars["All plants"].waitForExistence(timeout: 10) else {
            XCTFail("The full plant list did not open. \(visibleTexts())")
            return
        }
        assertNoLoadFailure("All plants")

        // Five plants are seeded, so this list has a right answer.
        XCTAssertTrue(
            waitForAnywhere("Monstera") || existsAnywhere("Pothos"),
            "The full plant list is empty despite five seeded plants. \(visibleTexts())"
        )
    }
}
