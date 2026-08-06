import Foundation

/// The collectibles that ship with the app.
///
/// Defined in Swift for the same reason the game pack is (ADR-022): the
/// cross-references here — a slot that accepts a category, a reward that belongs
/// to a destination, a destination that names its own stamp — are exactly the
/// kind of thing a JSON typo breaks silently. `CollectionPackValidator` checks
/// the rest, including that every placeable reward has somewhere to go.
///
/// Two rules governed what went in and what did not:
///
/// - **Nothing here is behind a wall of grinding.** The level thresholds are low
///   and the milestones are counts of things someone doing this normally would
///   pass anyway. Rewards mark that something happened; they are not the reason
///   to do it.
/// - **Every reward explains itself** (§7). There is no reward whose source is
///   "just because", and the validator has no way to express one.
public enum BuiltInCollectionContent {

    public static let manifest = ContentPackManifest(
        packID: "sunnie.pack.collection.core",
        version: 1,
        schemaVersion: ContentPackManifest.supportedSchemaVersion,
        displayNameKey: "content.pack.collection.core",
        minimumAppVersion: "0.1.0"
    )

    public static let pack = CollectionPack(
        manifest: manifest,
        rewards: rewards,
        slots: slots,
        storyScenes: storyScenes,
        destinations: destinations
    )

    // MARK: - Destinations (§10, TRAVEL_AND_FLIGHT_ATTENDANT.md §13)

    /// The five initial destinations.
    ///
    /// Each one ships a stamp and a postcard template and nothing more for now.
    /// Outfits and scene art wait for the design pass, because §10's warning
    /// about reducing a culture to one caricature is an art problem before it is
    /// a code problem — a placeholder beret is a decision nobody reviewed.
    public static let destinations: [DestinationDefinition] = [
        DestinationDefinition(
            id: "sunnie.destination.paris",
            displayNameKey: "destination.paris",
            regionCode: "FR",
            countryNames: ["France", "Frankreich", "Francia", "França"],
            stampID: "sunnie.reward.stamp.paris",
            postcardID: "sunnie.reward.postcard.paris"
        ),
        DestinationDefinition(
            id: "sunnie.destination.tokyo",
            displayNameKey: "destination.tokyo",
            regionCode: "JP",
            countryNames: ["Japan", "Japón", "Japão", "Japon"],
            stampID: "sunnie.reward.stamp.tokyo",
            postcardID: "sunnie.reward.postcard.tokyo"
        ),
        DestinationDefinition(
            id: "sunnie.destination.vietnam",
            displayNameKey: "destination.vietnam",
            regionCode: "VN",
            countryNames: ["Vietnam", "Viet Nam", "Việt Nam", "Vietname"],
            stampID: "sunnie.reward.stamp.vietnam",
            postcardID: "sunnie.reward.postcard.vietnam"
        ),
        DestinationDefinition(
            id: "sunnie.destination.spain",
            displayNameKey: "destination.spain",
            regionCode: "ES",
            countryNames: ["Spain", "España", "Espanha", "Espagne"],
            stampID: "sunnie.reward.stamp.spain",
            postcardID: "sunnie.reward.postcard.spain"
        ),
        DestinationDefinition(
            id: "sunnie.destination.brazil",
            displayNameKey: "destination.brazil",
            regionCode: "BR",
            countryNames: ["Brazil", "Brasil", "Brésil", "Brasilien"],
            stampID: "sunnie.reward.stamp.brazil",
            postcardID: "sunnie.reward.postcard.brazil"
        )
    ]

    // MARK: - Slots (§8)

    /// Where things go.
    ///
    /// Deliberately few. Constrained placement means the scene stays composed no
    /// matter what is in it, and a scene with forty slots is a freeform editor
    /// wearing a costume.
    public static let slots: [DecorSlot] = [
        DecorSlot(
            id: "sunnie.slot.cozy.shelf",
            zone: .cozyRoom,
            displayNameKey: "home.slot.cozy.shelf",
            accepts: [.decor, .souvenir],
            order: 0
        ),
        DecorSlot(
            id: "sunnie.slot.cozy.wall",
            zone: .cozyRoom,
            displayNameKey: "home.slot.cozy.wall",
            accepts: [.decor, .postcard],
            order: 1
        ),
        DecorSlot(
            id: "sunnie.slot.cozy.rug",
            zone: .cozyRoom,
            displayNameKey: "home.slot.cozy.rug",
            accepts: [.decor],
            order: 2
        ),
        DecorSlot(
            id: "sunnie.slot.jungle.stand",
            zone: .indoorJungle,
            displayNameKey: "home.slot.jungle.stand",
            accepts: [.decorativePlant],
            order: 0
        ),
        DecorSlot(
            id: "sunnie.slot.jungle.hanger",
            zone: .indoorJungle,
            displayNameKey: "home.slot.jungle.hanger",
            accepts: [.decorativePlant],
            order: 1
        ),
        DecorSlot(
            id: "sunnie.slot.jungle.bench",
            zone: .indoorJungle,
            displayNameKey: "home.slot.jungle.bench",
            accepts: [.decor, .souvenir],
            order: 2
        ),
        DecorSlot(
            id: "sunnie.slot.travel.shelf",
            zone: .travelNook,
            displayNameKey: "home.slot.travel.shelf",
            accepts: [.souvenir, .destinationObject],
            order: 0
        ),
        DecorSlot(
            id: "sunnie.slot.travel.board",
            zone: .travelNook,
            displayNameKey: "home.slot.travel.board",
            accepts: [.postcard, .passportStamp],
            order: 1
        ),
        DecorSlot(
            id: "sunnie.slot.music.stand",
            zone: .musicCorner,
            displayNameKey: "home.slot.music.stand",
            accepts: [.decor, .destinationObject],
            order: 0
        )
    ]

    // MARK: - Rewards (§6)

    public static let rewards: [RewardDefinition] =
        starterRewards + inheritedRewards + outfits + decor + plants
            + sounds + travelRewards + destinationRewards

    /// Owned from the first launch.
    ///
    /// A collection that starts completely empty reads as a locked door. These
    /// three say what the screen is for.
    static let starterRewards: [RewardDefinition] = [
        RewardDefinition(
            id: "sunnie.reward.outfit.everyday",
            category: .outfit,
            displayNameKey: "reward.outfit.everyday.name",
            descriptionKey: "reward.outfit.everyday.description",
            unlockSource: .fromTheStart
        ),
        RewardDefinition(
            id: "sunnie.reward.decor.woodenStool",
            category: .decor,
            displayNameKey: "reward.decor.woodenStool.name",
            descriptionKey: "reward.decor.woodenStool.description",
            unlockSource: .fromTheStart,
            zones: [.cozyRoom]
        ),
        RewardDefinition(
            id: "sunnie.reward.ambience.roomTone",
            category: .ambience,
            displayNameKey: "reward.ambience.roomTone.name",
            descriptionKey: "reward.ambience.roomTone.description",
            unlockSource: .fromTheStart,
            soundID: "sunnie.calm.noise.brown"
        )
    ]

    static let outfits: [RewardDefinition] = [
        RewardDefinition(
            id: "sunnie.reward.outfit.gardening",
            category: .outfit,
            displayNameKey: "reward.outfit.gardening.name",
            descriptionKey: "reward.outfit.gardening.description",
            unlockSource: .milestone(.plantCareCompleted, count: 10)
        ),
        RewardDefinition(
            id: "sunnie.reward.outfit.cozyPajamas",
            category: .outfit,
            displayNameKey: "reward.outfit.cozyPajamas.name",
            descriptionKey: "reward.outfit.cozyPajamas.description",
            unlockSource: .level(3)
        ),
        RewardDefinition(
            id: "sunnie.reward.outfit.travelUniform",
            category: .outfit,
            displayNameKey: "reward.outfit.travelUniform.name",
            descriptionKey: "reward.outfit.travelUniform.description",
            unlockSource: .firstTime(.travelCoverageCompleted)
        )
    ]

    static let decor: [RewardDefinition] = [
        RewardDefinition(
            id: "sunnie.reward.decor.readingLamp",
            category: .decor,
            displayNameKey: "reward.decor.readingLamp.name",
            descriptionKey: "reward.decor.readingLamp.description",
            unlockSource: .level(2),
            zones: [.cozyRoom]
        ),
        RewardDefinition(
            id: "sunnie.reward.decor.wovenRug",
            category: .decor,
            displayNameKey: "reward.decor.wovenRug.name",
            descriptionKey: "reward.decor.wovenRug.description",
            unlockSource: .level(5),
            zones: [.cozyRoom]
        ),
        RewardDefinition(
            id: "sunnie.reward.decor.recordPlayer",
            category: .decor,
            displayNameKey: "reward.decor.recordPlayer.name",
            descriptionKey: "reward.decor.recordPlayer.description",
            unlockSource: .level(4),
            zones: [.musicCorner]
        ),
        RewardDefinition(
            id: "sunnie.reward.souvenir.brassBell",
            category: .souvenir,
            displayNameKey: "reward.souvenir.brassBell.name",
            descriptionKey: "reward.souvenir.brassBell.description",
            unlockSource: .travelMemory,
            zones: [.cozyRoom, .travelNook]
        ),
    ]

    /// The five rewards earlier phases already grant.
    ///
    /// Their identifiers are kept exactly as Phases 1 and 7 wrote them. Renaming
    /// them into this pack's naming scheme would be tidier and would orphan every
    /// grant already in someone's store — ownership is keyed on the content ID,
    /// so the ID is not ours to tidy (§12).
    static let inheritedRewards: [RewardDefinition] = [
        RewardDefinition(
            id: "sunnie.reward.collectible.firstSprout",
            category: .decorativePlant,
            displayNameKey: "reward.collectible.firstSprout.name",
            descriptionKey: "reward.collectible.firstSprout.description",
            unlockSource: .firstTime(.firstPlantAdded),
            zones: [.indoorJungle]
        ),
        RewardDefinition(
            id: "sunnie.reward.collectible.wateringCan",
            category: .decor,
            displayNameKey: "reward.collectible.wateringCan.name",
            descriptionKey: "reward.collectible.wateringCan.description",
            unlockSource: .firstTime(.plantCareCompleted),
            zones: [.indoorJungle, .cozyRoom]
        ),
        RewardDefinition(
            id: "sunnie.reward.collectible.luggageTag",
            category: .souvenir,
            displayNameKey: "reward.collectible.luggageTag.name",
            descriptionKey: "reward.collectible.luggageTag.description",
            unlockSource: .firstTime(.puzzleCompleted),
            zones: [.travelNook]
        ),
        RewardDefinition(
            id: "sunnie.reward.collectible.inkStamp",
            category: .souvenir,
            displayNameKey: "reward.collectible.inkStamp.name",
            descriptionKey: "reward.collectible.inkStamp.description",
            unlockSource: .game("sunnie.game.postcardCipher"),
            zones: [.travelNook, .cozyRoom]
        ),
        RewardDefinition(
            id: "sunnie.reward.collectible.brassLabel",
            category: .souvenir,
            displayNameKey: "reward.collectible.brassLabel.name",
            descriptionKey: "reward.collectible.brassLabel.description",
            unlockSource: .game("sunnie.game.jungleLogic"),
            zones: [.indoorJungle, .cozyRoom]
        )
    ]

    static let plants: [RewardDefinition] = [
        RewardDefinition(
            id: "sunnie.reward.plant.littleFern",
            category: .decorativePlant,
            displayNameKey: "reward.plant.littleFern.name",
            descriptionKey: "reward.plant.littleFern.description",
            unlockSource: .firstTime(.firstPlantAdded),
            zones: [.indoorJungle]
        ),
        RewardDefinition(
            id: "sunnie.reward.plant.trailingPothos",
            category: .decorativePlant,
            displayNameKey: "reward.plant.trailingPothos.name",
            descriptionKey: "reward.plant.trailingPothos.description",
            unlockSource: .milestone(.plantCareCompleted, count: 25),
            zones: [.indoorJungle]
        ),
        RewardDefinition(
            id: "sunnie.reward.plant.paperFlower",
            category: .decorativePlant,
            displayNameKey: "reward.plant.paperFlower.name",
            descriptionKey: "reward.plant.paperFlower.description",
            unlockSource: .firstTime(.growthPhotoMilestone),
            zones: [.indoorJungle]
        )
    ]

    /// Sounds that can be played in the home.
    ///
    /// All three point at the generated noise from Phase 4, because that is what
    /// actually makes sound today. Recorded ambience arrives in Phase 10, and
    /// listing tracks now that play silence would be the app claiming content it
    /// does not have.
    static let sounds: [RewardDefinition] = [
        RewardDefinition(
            id: "sunnie.reward.ambience.softRain",
            category: .ambience,
            displayNameKey: "reward.ambience.softRain.name",
            descriptionKey: "reward.ambience.softRain.description",
            unlockSource: .level(2),
            soundID: "sunnie.calm.noise.pink"
        ),
        RewardDefinition(
            id: "sunnie.reward.ambience.openWindow",
            category: .ambience,
            displayNameKey: "reward.ambience.openWindow.name",
            descriptionKey: "reward.ambience.openWindow.description",
            unlockSource: .milestone(.wellnessCheckInRecorded, count: 5),
            soundID: "sunnie.calm.noise.white"
        )
    ]

    /// Earned by travelling.
    static let travelRewards: [RewardDefinition] = [
        RewardDefinition(
            id: "sunnie.reward.decor.worldMapPrint",
            category: .decor,
            displayNameKey: "reward.decor.worldMapPrint.name",
            descriptionKey: "reward.decor.worldMapPrint.description",
            unlockSource: .milestone(.destinationVisited, count: 2),
            zones: [.travelNook, .cozyRoom]
        )
    ]

    /// The stamps and postcard templates for the five destinations.
    ///
    /// Generated rather than written out ten times: they differ only in which
    /// place they name, and ten hand-written near-duplicates is ten chances to
    /// paste the wrong identifier.
    static let destinationRewards: [RewardDefinition] = destinations.flatMap { destination in
        let slug = destination.id.rawValue.split(separator: ".").last.map(String.init) ?? ""
        var built: [RewardDefinition] = []

        if let stampID = destination.stampID {
            built.append(RewardDefinition(
                id: stampID,
                category: .passportStamp,
                displayNameKey: "reward.stamp.\(slug).name",
                descriptionKey: "reward.stamp.\(slug).description",
                unlockSource: .destination(destination.id),
                destinationID: destination.id,
                zones: [.travelNook]
            ))
        }
        if let postcardID = destination.postcardID {
            built.append(RewardDefinition(
                id: postcardID,
                category: .postcard,
                displayNameKey: "reward.postcard.\(slug).name",
                descriptionKey: "reward.postcard.\(slug).description",
                unlockSource: .destination(destination.id),
                destinationID: destination.id,
                zones: [.travelNook, .cozyRoom]
            ))
        }
        return built
    }

    // MARK: - Story scenes (§11)

    /// Optional content, and nothing depends on it.
    ///
    /// Text panels for now; illustration comes with the art pass. A scene that
    /// unlocks and has nothing to show would be worse than one that waits.
    public static let storyScenes: [StoryScene] = [
        StoryScene(
            id: "sunnie.story.firstMorning",
            titleKey: "story.firstMorning.title",
            panelKeys: [
                "story.firstMorning.panel1",
                "story.firstMorning.panel2",
                "story.firstMorning.panel3"
            ],
            unlockSource: .firstTime(.firstPlantAdded)
        ),
        StoryScene(
            id: "sunnie.story.packingNight",
            titleKey: "story.packingNight.title",
            panelKeys: [
                "story.packingNight.panel1",
                "story.packingNight.panel2",
                "story.packingNight.panel3"
            ],
            unlockSource: .firstTime(.travelCoverageCompleted)
        )
    ]
}
