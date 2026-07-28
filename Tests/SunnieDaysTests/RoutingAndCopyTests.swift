import Foundation
import Testing
import SunnieShared
@testable import SunnieDays

@Suite("Deep links and routing")
struct RoutingTests {

    @Test(
        "Documented links resolve to their routes",
        arguments: [
            ("sunniedays://today", AppRoute.today),
            ("sunniedays://jungle", AppRoute.jungle),
            ("sunniedays://jungle/due", AppRoute.jungleDue),
            ("sunniedays://wellness/checkin", AppRoute.checkIn),
            ("sunniedays://games/daily", AppRoute.games),
            ("sunniedays://journal/new", AppRoute.journal),
            ("sunniedays://settings", AppRoute.settings)
        ]
    )
    func documentedLinksResolve(link: String, expected: AppRoute) throws {
        let url = try #require(URL(string: link))
        #expect(DeepLinkParser.route(from: url) == expected)
    }

    @Test("Entity links carry their identifier")
    func entityLinksCarryIdentifier() throws {
        let id = UUID()
        let url = try #require(URL(string: "sunniedays://plant/\(id.uuidString)"))

        #expect(DeepLinkParser.route(from: url) == .plant(id))
    }

    @Test("A malformed identifier resolves to nothing rather than somewhere wrong")
    func malformedIdentifierIsRejected() throws {
        let url = try #require(URL(string: "sunniedays://plant/not-a-uuid"))
        #expect(DeepLinkParser.route(from: url) == nil)
    }

    @Test("Links from another scheme are ignored")
    func foreignSchemeIsIgnored() throws {
        let url = try #require(URL(string: "https://example.com/plant/1"))
        #expect(DeepLinkParser.route(from: url) == nil)
    }

    @Test("An unknown destination resolves to nothing rather than a default screen")
    func unknownDestinationIsIgnored() throws {
        let url = try #require(URL(string: "sunniedays://somethingElse"))
        #expect(DeepLinkParser.route(from: url) == nil)
    }

    @Test("Every route belongs to exactly one tab")
    func routesMapToTabs() {
        #expect(AppRoute.plant(UUID()).tab == .jungle)
        #expect(AppRoute.jungleDue.tab == .jungle)
        #expect(AppRoute.checkIn.tab == .wellness)
        #expect(AppRoute.themes.tab == .more)
        #expect(AppRoute.settings.tab == .more)
        #expect(AppRoute.trip(UUID()).tab == .travel)
    }

    @Test("The five tabs are in the locked order")
    func tabOrderIsLocked() {
        #expect(AppTab.allCases == [.today, .jungle, .travel, .wellness, .more])
    }

    @MainActor
    @Test("Routing to a detail selects its tab and pushes once")
    func routerSelectsTabAndPushes() {
        let router = AppRouter()
        let plantID = UUID()

        router.handle(.plant(plantID))

        #expect(router.selectedTab == .jungle)
        #expect(router.path(for: .jungle).wrappedValue == [.plant(plantID)])
    }

    @MainActor
    @Test("Handling the same route twice does not stack duplicates")
    func repeatedRouteDoesNotStack() {
        let router = AppRouter()
        let plantID = UUID()

        router.handle(.plant(plantID))
        router.handle(.plant(plantID))

        #expect(router.path(for: .jungle).wrappedValue.count == 1)
    }

    @MainActor
    @Test("Each tab keeps its own stack when the user switches away")
    func stacksArePreservedPerTab() {
        let router = AppRouter()
        let plantID = UUID()

        router.handle(.plant(plantID))
        router.handle(.settings)

        #expect(router.selectedTab == .more)
        // The Jungle stack is untouched by the visit to More.
        #expect(router.path(for: .jungle).wrappedValue == [.plant(plantID)])
        #expect(router.path(for: .more).wrappedValue == [.settings])
    }

    @MainActor
    @Test("Routing to a tab root clears that tab's stack")
    func tabRootClearsStack() {
        let router = AppRouter()
        router.handle(.plant(UUID()))

        router.handle(.jungle)

        #expect(router.path(for: .jungle).wrappedValue.isEmpty)
    }
}

/// Applies the tone rules to the app's own localized strings.
///
/// The content validator already guards Sunnie's dialogue. This extends the same
/// gate to UI copy, so a shaming phrase cannot arrive through a button label or
/// an error message either.
@Suite("User-facing copy")
struct CopyToneTests {

    /// Every string in the English table, read from the built app bundle.
    ///
    /// This is a hosted unit-test bundle, so `Bundle.main` is the app. The test
    /// bundle is checked as a fallback in case the strings move.
    private func localizedStrings() throws -> [String: String] {
        let candidates = [Bundle.main, Bundle(for: BundleToken.self)]
        let url = try #require(
            candidates.lazy.compactMap {
                $0.url(forResource: "Localizable", withExtension: "strings")
                    ?? $0.url(
                        forResource: "Localizable",
                        withExtension: "strings",
                        subdirectory: nil,
                        localization: "en"
                    )
            }.first,
            "Localizable.strings was not found in the app or test bundle"
        )
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        )
        return try #require(plist as? [String: String])
    }

    @Test("No localized string uses shaming, guilt, or fake urgency")
    func localizedCopyPassesToneRules() throws {
        let strings = try localizedStrings()
        #expect(!strings.isEmpty)

        for (key, value) in strings {
            let issues = ContentValidator.toneIssues(in: value, contentID: key)
            #expect(issues.isEmpty, "\(key): \(issues.map(\.description))")
        }
    }

    @Test("No localized string uses a forbidden day-cycle name")
    func localizedCopyUsesApprovedNames() throws {
        for (key, value) in try localizedStrings() {
            let lowered = value.lowercased()
            #expect(!lowered.contains("sunnie mornings"), "\(key)")
            #expect(!lowered.contains("sunnie evenings"), "\(key)")
        }
    }

    @Test("The three branded names are present and spelled correctly")
    func brandedNamesArePresent() throws {
        let strings = try localizedStrings()

        #expect(strings["dayCycle.sunnieDays"] == "Sunnie Days")
        #expect(strings["dayCycle.sunnieAfternoonies"] == "Sunnie Afternoonies")
        #expect(strings["dayCycle.sunnieNights"] == "Sunnie Nights")
    }

    @Test("Waiting tasks are never described as overdue or late")
    func waitingVocabularyIsKind() throws {
        // The vocabulary rule from PLANT_CARE.md and the tone guide: a task past
        // its date is waiting, not failed.
        for (key, value) in try localizedStrings() {
            let lowered = value.lowercased()
            #expect(!lowered.contains("overdue"), "\(key) uses 'overdue'")
            #expect(!lowered.contains("you forgot"), "\(key) blames the user")
            #expect(!lowered.contains("you missed"), "\(key) blames the user")
        }
    }
}

/// Anchor for locating the test bundle.
private final class BundleToken {}
