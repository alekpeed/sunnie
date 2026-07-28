import Foundation
import Testing
@testable import SunnieShared

@Suite("Shipped content validation")
struct ContentValidationTests {

    @Test("The built-in packs decode from the bundle")
    func builtInPacksDecode() throws {
        let messages = try #require(
            ContentRegistry.decode(SunnieMessagePack.self, resource: "sunnie.messages.v1"),
            "The core message pack failed to decode; the app would fall back to minimal content."
        )
        let themes = try #require(
            ContentRegistry.decode(ThemePack.self, resource: "themes.v1"),
            "The core theme pack failed to decode."
        )

        #expect(!messages.messages.isEmpty)
        #expect(themes.themes.count == 3)
    }

    @Test("The built-in content has no validation issues")
    func builtInContentIsValid() {
        let issues = ContentRegistry.builtIn().allIssues
        #expect(issues.isEmpty, "Content issues: \(issues.map(\.description))")
    }

    @Test("The fallback content is itself valid")
    func fallbackContentIsValid() {
        // The fallback is what ships if a pack fails to load, so it must pass the
        // same bar as the real content.
        let issues = ContentValidator.validate(FallbackContent.messagePack)
            + ContentValidator.validate(FallbackContent.themePack)

        #expect(issues.isEmpty, "Fallback issues: \(issues.map(\.description))")
    }

    @Test("All three initial theme families are present")
    func themeFamiliesPresent() {
        let registry = ContentRegistry.builtIn()

        #expect(registry.theme(id: ThemeCatalog.lushTropicalJungleID) != nil)
        #expect(registry.theme(id: ThemeCatalog.travelScrapbookID) != nil)
        #expect(registry.theme(id: ThemeCatalog.dayCycleID) != nil)
    }

    @Test("Every theme covers the dark phases so night is never unstyled")
    func themesCoverDarkPhases() {
        let registry = ContentRegistry.builtIn()

        for theme in registry.themePack.themes {
            for phase in [TimePhase.evening, .night, .lateNight] {
                #expect(
                    theme.variant(for: phase) != nil,
                    "\(theme.id) has no \(phase.rawValue) variant"
                )
            }
        }
    }

    @Test("Shaming and guilt language is rejected")
    func toneGateCatchesProhibitedPhrases() {
        let samples = [
            "You failed to water this plant.",
            "You broke your streak.",
            "Sunnie is disappointed in you.",
            "Your plants are dying because you forgot.",
            "No excuses, water it now.",
            "You must do this now."
        ]

        for sample in samples {
            let issues = ContentValidator.toneIssues(in: sample, contentID: "test.sample")
            #expect(!issues.isEmpty, "Tone gate missed: \(sample)")
        }
    }

    @Test("Negative labels are rejected as whole words")
    func toneGateCatchesNegativeLabels() {
        #expect(!ContentValidator.toneIssues(
            in: "That was careless of you.", contentID: "test.sample"
        ).isEmpty)

        #expect(!ContentValidator.toneIssues(
            in: "Don't be lazy about it.", contentID: "test.sample"
        ).isEmpty)
    }

    @Test("Innocent words containing a banned substring are not flagged")
    func toneGateAvoidsFalsePositives() {
        // "badge" contains "bad"; "unhealthy" is banned but "healthy" is not.
        let issues = ContentValidator.toneIssues(
            in: "Your travel badge is ready, and this looks healthy.",
            contentID: "test.sample"
        )

        #expect(issues.isEmpty, "False positives: \(issues.map(\.description))")
    }

    @Test("Forbidden day-cycle names are rejected")
    func toneGateCatchesForbiddenDayCycleNames() {
        #expect(!ContentValidator.toneIssues(
            in: "Welcome to Sunnie Mornings.", contentID: "test.sample"
        ).isEmpty)

        #expect(!ContentValidator.toneIssues(
            in: "Welcome to Sunnie Evenings.", contentID: "test.sample"
        ).isEmpty)

        #expect(ContentValidator.toneIssues(
            in: "Welcome to Sunnie Afternoonies.", contentID: "test.sample"
        ).isEmpty)
    }

    @Test("No shipped message uses a forbidden day-cycle name")
    func shippedContentUsesOnlyApprovedNames() {
        let registry = ContentRegistry.builtIn()

        for message in registry.messagePack.messages {
            let lowered = message.template.lowercased()
            #expect(!lowered.contains("sunnie mornings"))
            #expect(!lowered.contains("sunnie evenings"))
        }
    }

    @Test("A nickname placeholder in a serious category is rejected")
    func nicknamePlaceholderInSeriousCategoryIsRejected() {
        let pack = SunnieMessagePack(
            manifest: FallbackContent.manifest,
            messages: FallbackContent.messagePack.messages + [
                .init(
                    id: "sunnie.message.bad.privacy",
                    category: .privacyNotice,
                    template: "Your data is private, {name}.",
                    localizationKey: "sunnie.message.bad.privacy",
                    expression: .calmBreathing,
                    pose: .standingNeutral
                )
            ]
        )

        let issues = ContentValidator.validate(pack)
        #expect(issues.contains {
            if case .nicknamePlaceholderInIneligibleCategory = $0.kind { return true }
            return false
        })
    }

    @Test("A missing category is reported")
    func missingCategoryIsReported() {
        let pack = SunnieMessagePack(
            manifest: FallbackContent.manifest,
            messages: FallbackContent.messagePack.messages.filter { $0.category != .error }
        )

        let issues = ContentValidator.validate(pack)
        #expect(issues.contains {
            if case .noMessagesForCategory(.error) = $0.kind { return true }
            return false
        })
    }

    @Test("Duplicate and malformed content IDs are reported")
    func idProblemsAreReported() {
        let duplicate = FallbackContent.messagePack.messages[0]
        let malformed = SunnieMessageDefinition(
            id: "not-dot-delimited!",
            category: .greeting,
            template: "Hello.",
            localizationKey: "x",
            expression: .gentleWave,
            pose: .waving
        )
        let pack = SunnieMessagePack(
            manifest: FallbackContent.manifest,
            messages: FallbackContent.messagePack.messages + [duplicate, malformed]
        )

        let issues = ContentValidator.validate(pack)
        #expect(issues.contains { if case .duplicateID = $0.kind { return true }; return false })
        #expect(issues.contains { if case .malformedID = $0.kind { return true }; return false })
    }

    @Test("An unreadable colour is reported rather than crashing")
    func malformedColourIsReported() {
        var palette = FallbackContent.warmPalette
        palette.canvas = ColorValue(hex: "#ZZZZZZ")
        let pack = ThemePack(
            manifest: FallbackContent.manifest,
            themes: [ThemeDefinition(
                id: "sunnie.theme.broken",
                version: 1,
                displayNameKey: "theme.broken",
                basePalette: palette
            )]
        )

        let issues = ContentValidator.validate(pack)
        #expect(issues.contains { if case .malformedColor = $0.kind { return true }; return false })
    }

    @Test("A future schema version is reported, not silently accepted")
    func futureSchemaVersionIsReported() {
        let manifest = ContentPackManifest(
            packID: "sunnie.pack.future",
            version: 1,
            schemaVersion: ContentPackManifest.supportedSchemaVersion + 1,
            displayNameKey: "content.pack.future",
            minimumAppVersion: "0.1.0"
        )
        let pack = SunnieMessagePack(
            manifest: manifest,
            messages: FallbackContent.messagePack.messages
        )

        let issues = ContentValidator.validate(pack)
        #expect(issues.contains {
            if case .unsupportedSchemaVersion = $0.kind { return true }
            return false
        })
    }

    @Test("Colour parsing handles both six and eight digit hex")
    func colourParsing() throws {
        let opaque = try #require(ColorValue(hex: "#FF8000").components)
        #expect(abs(opaque.red - 1.0) < 0.001)
        #expect(abs(opaque.alpha - 1.0) < 0.001)

        let translucent = try #require(ColorValue(hex: "FF800080").components)
        #expect(abs(translucent.alpha - 0.502) < 0.005)

        #expect(ColorValue(hex: "#FFF").components == nil)
        #expect(ColorValue(hex: "").components == nil)
    }
}
