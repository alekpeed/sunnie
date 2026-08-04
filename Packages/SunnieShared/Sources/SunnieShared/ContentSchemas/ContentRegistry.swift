import Foundation

/// Loads and holds validated content packs.
///
/// Decoding happens once at composition time. If built-in content fails to
/// decode the app still launches — it falls back to the minimal built-in set
/// rather than showing an empty screen, and the failure is logged and caught by
/// the content tests.
public final class ContentRegistry: Sendable {

    public let messagePack: SunnieMessagePack
    public let themePack: ThemePack
    public let wellnessPack: WellnessPack

    public init(
        messagePack: SunnieMessagePack,
        themePack: ThemePack,
        wellnessPack: WellnessPack = FallbackContent.wellnessPack
    ) {
        self.messagePack = messagePack
        self.themePack = themePack
        self.wellnessPack = wellnessPack
    }

    /// Loads the packs that ship inside the shared package.
    public static func builtIn() -> ContentRegistry {
        let log = SunnieLog(category: .content)
        let messages = decode(SunnieMessagePack.self, resource: "sunnie.messages.v1")
        let themes = decode(ThemePack.self, resource: "themes.v1")
        let wellness = decode(WellnessPack.self, resource: "wellness.v1")

        if messages == nil {
            log.error("Built-in message pack failed to decode; using fallback content.")
        }
        if themes == nil {
            log.error("Built-in theme pack failed to decode; using fallback content.")
        }
        if wellness == nil {
            log.error("Built-in wellness pack failed to decode; using fallback content.")
        }

        return ContentRegistry(
            messagePack: messages ?? FallbackContent.messagePack,
            themePack: themes ?? FallbackContent.themePack,
            wellnessPack: wellness ?? FallbackContent.wellnessPack
        )
    }

    static func decode<T: Decodable>(_ type: T.Type, resource: String) -> T? {
        guard let url = Bundle.module.url(
            forResource: resource, withExtension: "json", subdirectory: "Content"
        ) ?? Bundle.module.url(forResource: resource, withExtension: "json") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    public func messages(for category: SunnieMessageCategory) -> [SunnieMessageDefinition] {
        messagePack.messages.filter { $0.category == category }
    }

    public func theme(id: ContentID) -> ThemeDefinition? {
        themePack.themes.first { $0.id == id }
    }

    public var allIssues: [ContentIssue] {
        ContentValidator.validate(messagePack)
            + ContentValidator.validate(themePack)
            + ContentValidator.validate(wellnessPack)
    }
}

/// The smallest content set that keeps the app coherent if a pack cannot be read.
///
/// Every message category is represented, because a missing category means a
/// blank card. The tone rules apply here exactly as they do to shipped content.
public enum FallbackContent {

    public static let manifest = ContentPackManifest(
        packID: "sunnie.pack.fallback",
        version: 1,
        schemaVersion: ContentPackManifest.supportedSchemaVersion,
        displayNameKey: "content.pack.fallback",
        minimumAppVersion: "0.1.0"
    )

    public static let messagePack = SunnieMessagePack(
        manifest: manifest,
        messages: [
            .init(
                id: "sunnie.message.fallback.greeting",
                category: .greeting,
                template: "Hello, {name}.",
                localizationKey: "sunnie.message.fallback.greeting",
                expression: .gentleWave,
                pose: .waving
            ),
            .init(
                id: "sunnie.message.fallback.celebration",
                category: .celebration,
                template: "That was a good step.",
                localizationKey: "sunnie.message.fallback.celebration",
                expression: .celebratingQuietly,
                pose: .standingNeutral
            ),
            .init(
                id: "sunnie.message.fallback.casualAffirmation",
                category: .casualAffirmation,
                template: "One little thing at a time.",
                localizationKey: "sunnie.message.fallback.casualAffirmation",
                expression: .happyClosedEyed,
                pose: .sittingNeutral
            ),
            .init(
                id: "sunnie.message.fallback.postcard",
                category: .postcard,
                template: "A little note from somewhere lovely.",
                localizationKey: "sunnie.message.fallback.postcard",
                expression: .traveling,
                pose: .holdingPassport
            ),
            .init(
                id: "sunnie.message.fallback.homeScene",
                category: .homeScene,
                template: "It's cozy in here.",
                localizationKey: "sunnie.message.fallback.homeScene",
                expression: .happyClosedEyed,
                pose: .holdingMug
            ),
            .init(
                id: "sunnie.message.fallback.careCompleted",
                category: .careCompleted,
                template: "Your jungle is looking cared for.",
                localizationKey: "sunnie.message.fallback.careCompleted",
                expression: .caringForPlant,
                pose: .holdingWateringCan
            ),
            .init(
                id: "sunnie.message.fallback.gentleReminder",
                category: .gentleReminder,
                template: "This is still waiting when you have a moment.",
                localizationKey: "sunnie.message.fallback.gentleReminder",
                expression: .curious,
                pose: .pointingAtTask
            ),
            .init(
                id: "sunnie.message.fallback.permissionRequest",
                category: .permissionRequest,
                template: "This works better with your permission, and it's fine to say no.",
                localizationKey: "sunnie.message.fallback.permissionRequest",
                expression: .curious,
                pose: .standingNeutral
            ),
            .init(
                id: "sunnie.message.fallback.error",
                category: .error,
                template: "That didn't finish. Everything you entered is still saved here.",
                localizationKey: "sunnie.message.fallback.error",
                expression: .comforting,
                pose: .standingNeutral
            ),
            .init(
                id: "sunnie.message.fallback.privacyNotice",
                category: .privacyNotice,
                template: "Your information stays on your devices and in your private iCloud.",
                localizationKey: "sunnie.message.fallback.privacyNotice",
                expression: .calmBreathing,
                pose: .standingNeutral
            ),
            .init(
                id: "sunnie.message.fallback.healthExplanation",
                category: .healthExplanation,
                template: "This shows what you recorded. It isn't medical advice.",
                localizationKey: "sunnie.message.fallback.healthExplanation",
                expression: .calmBreathing,
                pose: .sittingNeutral
            ),
            .init(
                id: "sunnie.message.fallback.travelDocumentAlert",
                category: .travelDocumentAlert,
                template: "One travel document needs a look before you go.",
                localizationKey: "sunnie.message.fallback.travelDocumentAlert",
                expression: .traveling,
                pose: .pullingSuitcase
            )
        ]
    )

    /// Provisional palette from VISUAL_DESIGN_SYSTEM.md §3.
    public static let warmPalette = SemanticPalette(
        canvas: "#FFF8ED",
        surface: "#FFF1DC",
        surfaceRaised: "#FFFDF8",
        textPrimary: "#493528",
        textSecondary: "#755E4D",
        accentWarm: "#F3A58D",
        accentSunnie: "#F6D47D",
        accentCalm: "#B9A6E1",
        accentPlant: "#A9C5A0",
        accentTravel: "#A8CBE4",
        success: "#91B982",
        attention: "#D7A65A",
        error: "#C97972"
    )

    /// The smallest wellness set that keeps the affirmation card, the breathing
    /// player, and the sound library from rendering empty.
    ///
    /// Every affirmation here suits a harder moment, because the fallback is what
    /// ships when something has already gone wrong and the filtered library must
    /// not come back empty.
    public static let wellnessPack = WellnessPack(
        manifest: manifest,
        affirmations: [
            .init(
                id: "sunnie.affirmation.fallback.01",
                text: "One little thing at a time is enough.",
                localizationKey: "sunnie.affirmation.fallback.01",
                tags: [.gentle, .selfCompassion]
            ),
            .init(
                id: "sunnie.affirmation.fallback.02",
                text: "You're allowed to take this slowly.",
                localizationKey: "sunnie.affirmation.fallback.02",
                tags: [.gentle]
            )
        ],
        breathingPatterns: [
            .init(
                id: "sunnie.breathing.fallback.equal",
                displayNameKey: "breathing.equal.name",
                descriptionKey: "breathing.equal.description",
                inhaleSeconds: 4,
                holdAfterInhaleSeconds: 0,
                exhaleSeconds: 4,
                holdAfterExhaleSeconds: 0,
                defaultCycles: 10
            )
        ],
        meditations: [
            .init(
                id: "sunnie.meditation.fallback.silent",
                displayNameKey: "meditation.silent.name",
                type: .meditation,
                defaultDuration: 300,
                availableDurations: [60, 180, 300]
            )
        ],
        // The recorded ambiences are deliberately absent — without their assets
        // they would be a list of things that do nothing. The generated colours
        // are here because they need no asset at all: noise is computed, so it
        // works even when the content pack failed to load, which is exactly when
        // the sound library must not come back empty.
        calmSounds: NoiseColor.allCases.map { color in
            CalmSoundDefinition(
                id: color.contentID,
                displayNameKey: color.localizationKey,
                category: .noise,
                audioCueID: ContentID(rawValue: "sunnie.audio.noise.\(color.rawValue)"),
                isMixable: false
            )
        }
    )

    public static let themePack = ThemePack(
        manifest: manifest,
        themes: [
            ThemeDefinition(
                id: ThemeCatalog.lushTropicalJungleID,
                version: 1,
                displayNameKey: "theme.lushTropicalJungle",
                basePalette: warmPalette
            )
        ]
    )
}
