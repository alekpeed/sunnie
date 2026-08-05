import Foundation

/// Shorthand for an authored string. Keeps the content below readable.
private func t(_ text: String, _ key: String) -> GameText {
    GameText(text: text, localizationKey: key)
}

/// The game pack that ships inside the app.
///
/// **Defined in Swift rather than JSON, unlike the message, theme, and wellness
/// packs** (ADR-022). Those are flat lists of short strings; a game pack is a
/// tree of clues, options, indexed constraints, and answer keys, where a
/// mistyped index is a puzzle that tells a player their correct answer is wrong.
/// Written as Swift, every index is bounds-checked by the validator and every
/// mismatch between a game's kind and its puzzle's payload is a type error.
/// Added packs still load from JSON through `ContentRegistry` — this is the
/// built-in set, not the only way to ship one.
///
/// Every puzzle here is validated by `GamePackValidator`, which among other
/// things *solves* both deduction puzzles to prove each has exactly one answer.
public enum BuiltInGameContent {

    public static let manifest = ContentPackManifest(
        packID: "sunnie.pack.games.core",
        version: 1,
        schemaVersion: ContentPackManifest.supportedSchemaVersion,
        displayNameKey: "content.pack.games.core",
        minimumAppVersion: "0.1.0"
    )

    public static let pack = GamePack(
        manifest: manifest,
        games: games,
        puzzles: puzzles,
        rewardTable: [
            "sunnie.game.wordLayover": "sunnie.reward.collectible.luggageTag",
            "sunnie.game.postcardCipher": "sunnie.reward.collectible.inkStamp",
            "sunnie.game.jungleLogic": "sunnie.reward.collectible.brassLabel"
        ]
    )

    // MARK: - Games

    public static let games: [GameDefinition] = [
        GameDefinition(
            id: "sunnie.game.wordLayover",
            kind: .answerChain,
            categories: [.wordplay, .language, .travel],
            displayNameKey: "game.wordLayover.name",
            summaryKey: "game.wordLayover.summary",
            rulesKey: "game.wordLayover.rules",
            difficulties: [.gentle, .steady],
            languages: [.english, .spanish, .french, .portuguese]
        ),
        GameDefinition(
            id: "sunnie.game.postcardCipher",
            kind: .revealAndIdentify,
            categories: [.travel, .logic],
            displayNameKey: "game.postcardCipher.name",
            summaryKey: "game.postcardCipher.summary",
            rulesKey: "game.postcardCipher.rules",
            difficulties: [.gentle, .steady],
            // Clues cost score on their own, so a hint on top would charge
            // twice for the same help.
            hintPolicy: HintPolicy(costPerHint: 0, maximumPerStep: 0)
        ),
        GameDefinition(
            id: "sunnie.game.jungleLogic",
            kind: .gridAssignment,
            categories: [.plants, .logic],
            displayNameKey: "game.jungleLogic.name",
            summaryKey: "game.jungleLogic.summary",
            rulesKey: "game.jungleLogic.rules",
            difficulties: [.gentle, .steady]
        ),
        GameDefinition(
            id: "sunnie.game.memoryAtlas",
            kind: .studyThenQuiz,
            categories: [.memory, .travel],
            displayNameKey: "game.memoryAtlas.name",
            summaryKey: "game.memoryAtlas.summary",
            rulesKey: "game.memoryAtlas.rules",
            difficulties: [.steady]
        ),
        GameDefinition(
            id: "sunnie.game.lostInTranslation",
            kind: .answerChain,
            categories: [.language, .wordplay],
            displayNameKey: "game.lostInTranslation.name",
            summaryKey: "game.lostInTranslation.summary",
            rulesKey: "game.lostInTranslation.rules",
            difficulties: [.gentle, .steady],
            languages: [.english, .spanish, .french, .portuguese]
        ),
        GameDefinition(
            id: "sunnie.game.sunniesSuitcase",
            kind: .constrainedSelection,
            categories: [.logic, .travel],
            displayNameKey: "game.sunniesSuitcase.name",
            summaryKey: "game.sunniesSuitcase.summary",
            rulesKey: "game.sunniesSuitcase.rules",
            difficulties: [.steady]
        ),
        GameDefinition(
            id: "sunnie.game.triviaTrail",
            kind: .branchingChoice,
            categories: [.trivia, .travel],
            displayNameKey: "game.triviaTrail.name",
            summaryKey: "game.triviaTrail.summary",
            rulesKey: "game.triviaTrail.rules",
            difficulties: [.gentle]
        )
    ]

    public static let puzzles: [PuzzleDefinition] = [
        wordLayoverSeine,
        wordLayoverWind,
        postcardLisbon,
        postcardQuebec,
        jungleLogicShelf,
        jungleLogicWindowsill,
        memoryAtlasScrapbook,
        translationFalseFriends,
        translationNightChain,
        suitcasePorto,
        triviaTrailIberia
    ]

    // MARK: - G-01 Word Layover

    /// Paris → Seine → net → red → Red Sea.
    ///
    /// Each link is a real one. A route built on an invented etymology would be
    /// teaching something false, which is worse than teaching nothing.
    static let wordLayoverSeine = PuzzleDefinition(
        id: "sunnie.puzzle.wordLayover.seine",
        gameID: "sunnie.game.wordLayover",
        difficulty: .gentle,
        title: t("A net, a colour, a sea", "puzzle.wordLayover.seine.title"),
        payload: .answerChain(AnswerChainPuzzle(stops: [
            AnswerChainStop(
                prompt: t(
                    "First stop: the capital on the river Seine, with an iron tower that was only ever meant to stand for twenty years.",
                    "puzzle.wordLayover.seine.stop1"
                ),
                answer: "Paris",
                linkExplanation: t(
                    "Paris sits on the Seine. In English, a seine is a long fishing net — carry the net to the next stop.",
                    "puzzle.wordLayover.seine.link1"
                ),
                hints: [
                    t("It is the capital of France.", "puzzle.wordLayover.seine.hint1a"),
                    t("Five letters, beginning with P.", "puzzle.wordLayover.seine.hint1b")
                ]
            ),
            AnswerChainStop(
                prompt: t(
                    "Second stop, in Spanish: the word for that net — the same word Spanish uses for a spider's web, and now for the internet.",
                    "puzzle.wordLayover.seine.stop2"
                ),
                answer: "red",
                alternates: ["la red"],
                language: .spanish,
                linkExplanation: t(
                    "Red is Spanish for net. In English the same three letters are a colour — that is the bridge to the last stop.",
                    "puzzle.wordLayover.seine.link2"
                ),
                hints: [
                    t("Three letters.", "puzzle.wordLayover.seine.hint2a"),
                    t("In English it is a colour.", "puzzle.wordLayover.seine.hint2b")
                ]
            ),
            AnswerChainStop(
                prompt: t(
                    "Last stop: the sea between Africa and Arabia that carries that colour in its name.",
                    "puzzle.wordLayover.seine.stop3"
                ),
                answer: "Red Sea",
                alternates: ["the Red Sea", "Mar Rojo"],
                linkExplanation: t(
                    "The Red Sea. The route ran Paris to Seine to net to red to Red Sea — one meaning at a time.",
                    "puzzle.wordLayover.seine.link3"
                ),
                hints: [
                    t("The Suez Canal opens into it.", "puzzle.wordLayover.seine.hint3a")
                ]
            )
        ])),
        baseScore: 100
    )

    /// One Latin root, four languages.
    static let wordLayoverWind = PuzzleDefinition(
        id: "sunnie.puzzle.wordLayover.wind",
        gameID: "sunnie.game.wordLayover",
        difficulty: .steady,
        title: t("Following the wind", "puzzle.wordLayover.wind.title"),
        payload: .answerChain(AnswerChainPuzzle(stops: [
            AnswerChainStop(
                prompt: t(
                    "First stop: the Portuguese capital on the Tagus, where yellow trams climb the hills.",
                    "puzzle.wordLayover.wind.stop1"
                ),
                answer: "Lisbon",
                alternates: ["Lisboa"],
                language: .portuguese,
                linkExplanation: t(
                    "Lisbon, or Lisboa. Portuguese and Spanish grew from the same Latin, so the next clue is in Spanish.",
                    "puzzle.wordLayover.wind.link1"
                ),
                hints: [t("Its trams are numbered 28.", "puzzle.wordLayover.wind.hint1a")]
            ),
            AnswerChainStop(
                prompt: t(
                    "Second stop, in Spanish: the word for a window — the one you would lean out of on that tram.",
                    "puzzle.wordLayover.wind.stop2"
                ),
                answer: "ventana",
                alternates: ["la ventana"],
                language: .spanish,
                linkExplanation: t(
                    "Ventana comes from the Latin ventus, wind: a window began as the hole the wind came through. Follow the wind.",
                    "puzzle.wordLayover.wind.link2"
                ),
                hints: [
                    t("Seven letters, beginning with V.", "puzzle.wordLayover.wind.hint2a"),
                    t("Hidden inside it is the Spanish word for wind, viento.", "puzzle.wordLayover.wind.hint2b")
                ]
            ),
            AnswerChainStop(
                prompt: t(
                    "Third stop, in French: the word for wind itself.",
                    "puzzle.wordLayover.wind.stop3"
                ),
                answer: "vent",
                alternates: ["le vent"],
                language: .french,
                linkExplanation: t(
                    "Vent — the same Latin ventus. French wore the ending away; Spanish kept it in viento.",
                    "puzzle.wordLayover.wind.link3"
                ),
                hints: [t("Four letters.", "puzzle.wordLayover.wind.hint3a")]
            ),
            AnswerChainStop(
                prompt: t(
                    "Last stop, back in English: the steady winds that blow toward the equator, and gave their name to the sailing routes that used them.",
                    "puzzle.wordLayover.wind.stop4"
                ),
                answer: "trade winds",
                alternates: ["trade wind", "the trades", "trades"],
                linkExplanation: t(
                    "The trade winds. Lisboa, ventana, vent, trade wind — one Latin root carried through four languages.",
                    "puzzle.wordLayover.wind.link4"
                ),
                hints: [
                    t("Two words. The first is what merchants do.", "puzzle.wordLayover.wind.hint4a")
                ]
            )
        ])),
        baseScore: 140
    )

    // MARK: - G-02 Postcard Cipher

    static let postcardLisbon = PuzzleDefinition(
        id: "sunnie.puzzle.postcard.lisbon",
        gameID: "sunnie.game.postcardCipher",
        difficulty: .gentle,
        title: t("A hill, a tram, a castle", "puzzle.postcard.lisbon.title"),
        payload: .revealAndIdentify(IdentifyPuzzle(
            prompt: t("Where was this postcard sent from?", "puzzle.postcard.lisbon.prompt"),
            clues: [
                RevealClue(
                    kind: .textFragment,
                    detail: t(
                        "…the tram climbed so steeply I held on with both hands…",
                        "puzzle.postcard.lisbon.clue1"
                    ),
                    cost: 5
                ),
                RevealClue(
                    kind: .stampMark,
                    detail: t("The postmark reads CORREIOS.", "puzzle.postcard.lisbon.clue2"),
                    cost: 15
                ),
                RevealClue(
                    kind: .weather,
                    detail: t(
                        "Bright and dry, seventeen degrees — in February.",
                        "puzzle.postcard.lisbon.clue3"
                    ),
                    cost: 5
                ),
                RevealClue(
                    kind: .landmark,
                    detail: t(
                        "A castle on the highest hill, with peacocks walking the walls.",
                        "puzzle.postcard.lisbon.clue4"
                    ),
                    cost: 10
                ),
                RevealClue(
                    kind: .localPhrase,
                    detail: t(
                        "The waiter said “obrigado” when I paid.",
                        "puzzle.postcard.lisbon.clue5"
                    ),
                    cost: 15
                )
            ],
            answerIndex: 0,
            options: [
                t("Lisbon", "puzzle.postcard.lisbon.option1"),
                t("Seville", "puzzle.postcard.lisbon.option2"),
                t("Naples", "puzzle.postcard.lisbon.option3"),
                t("Valparaíso", "puzzle.postcard.lisbon.option4")
            ],
            explanation: t(
                "Lisbon. All four cities have hills and steep trams, so the trams alone decide nothing. CORREIOS is the Portuguese post — Spain writes CORREOS — and obrigado is Portuguese, not Spanish or Italian. The castle with peacocks is São Jorge.",
                "puzzle.postcard.lisbon.explanation"
            )
        )),
        baseScore: 100
    )

    static let postcardQuebec = PuzzleDefinition(
        id: "sunnie.puzzle.postcard.quebec",
        gameID: "sunnie.game.postcardCipher",
        difficulty: .steady,
        title: t("French first, English under it", "puzzle.postcard.quebec.title"),
        payload: .revealAndIdentify(IdentifyPuzzle(
            prompt: t("Where was this postcard sent from?", "puzzle.postcard.quebec.prompt"),
            clues: [
                RevealClue(
                    kind: .textFragment,
                    detail: t(
                        "…everyone greeted me in French first, and switched when I answered…",
                        "puzzle.postcard.quebec.clue1"
                    ),
                    cost: 10
                ),
                RevealClue(
                    kind: .stampMark,
                    detail: t(
                        "The stamp shows a fleur-de-lis.",
                        "puzzle.postcard.quebec.clue2"
                    ),
                    cost: 5
                ),
                RevealClue(
                    kind: .weather,
                    detail: t(
                        "Minus two and brilliantly clear — in the middle of April.",
                        "puzzle.postcard.quebec.clue3"
                    ),
                    cost: 15
                ),
                RevealClue(
                    kind: .landmark,
                    detail: t(
                        "A hotel shaped like a castle, standing over a wide grey river.",
                        "puzzle.postcard.quebec.clue4"
                    ),
                    cost: 15
                ),
                RevealClue(
                    kind: .localPhrase,
                    detail: t(
                        "The shop door said OUVERT, and underneath, in smaller letters, OPEN.",
                        "puzzle.postcard.quebec.clue5"
                    ),
                    cost: 20
                )
            ],
            answerIndex: 2,
            options: [
                t("Strasbourg", "puzzle.postcard.quebec.option1"),
                t("Geneva", "puzzle.postcard.quebec.option2"),
                t("Quebec City", "puzzle.postcard.quebec.option3"),
                t("Brussels", "puzzle.postcard.quebec.option4")
            ],
            explanation: t(
                "Quebec City. The fleur-de-lis fits all four, and so does French being spoken first. What decides it is the sign: French above with English beneath is a Quebec arrangement — Strasbourg, Geneva and Brussels have no reason to add English underneath. The castle-shaped hotel is the Château Frontenac above the St Lawrence, and none of the European three sit at minus two in mid-April.",
                "puzzle.postcard.quebec.explanation"
            )
        )),
        baseScore: 140
    )

    // MARK: - G-03 Jungle Logic

    /// Four shelves, three categories.
    ///
    /// Seven clues, and exactly one arrangement satisfies them — proved by
    /// `GridDeductionSolver` in the content tests, not asserted here.
    ///
    /// Solution: Monstera/terracotta/Friday, Fern/blue/Monday,
    /// Pothos/white/Sunday, Calathea/green/Wednesday.
    static let jungleLogicShelf = PuzzleDefinition(
        id: "sunnie.puzzle.jungleLogic.shelf",
        gameID: "sunnie.game.jungleLogic",
        difficulty: .gentle,
        title: t("Four shelves", "puzzle.jungleLogic.shelf.title"),
        payload: .gridAssignment(GridPuzzle(
            positionLabel: t("Shelf", "puzzle.jungleLogic.shelf.positions"),
            categories: [
                GridCategory(
                    name: t("Plant", "puzzle.jungleLogic.shelf.cat.plant"),
                    values: [
                        t("Monstera", "puzzle.jungleLogic.shelf.plant.monstera"),
                        t("Fern", "puzzle.jungleLogic.shelf.plant.fern"),
                        t("Pothos", "puzzle.jungleLogic.shelf.plant.pothos"),
                        t("Calathea", "puzzle.jungleLogic.shelf.plant.calathea")
                    ]
                ),
                GridCategory(
                    name: t("Pot", "puzzle.jungleLogic.shelf.cat.pot"),
                    values: [
                        t("Terracotta", "puzzle.jungleLogic.shelf.pot.terracotta"),
                        t("Blue", "puzzle.jungleLogic.shelf.pot.blue"),
                        t("White", "puzzle.jungleLogic.shelf.pot.white"),
                        t("Green", "puzzle.jungleLogic.shelf.pot.green")
                    ]
                ),
                GridCategory(
                    name: t("Watering day", "puzzle.jungleLogic.shelf.cat.day"),
                    values: [
                        t("Monday", "puzzle.jungleLogic.shelf.day.monday"),
                        t("Wednesday", "puzzle.jungleLogic.shelf.day.wednesday"),
                        t("Friday", "puzzle.jungleLogic.shelf.day.friday"),
                        t("Sunday", "puzzle.jungleLogic.shelf.day.sunday")
                    ]
                )
            ],
            constraints: [
                // The Monstera is on the first shelf.
                .atPosition(category: 0, value: 0, position: 0),
                // The Fern is in the blue pot.
                .same(categoryA: 0, valueA: 1, categoryB: 1, valueB: 1),
                // The Calathea is watered on Wednesday.
                .same(categoryA: 0, valueA: 3, categoryB: 2, valueB: 1),
                // The Sunday plant is somewhere left of the green pot.
                .before(categoryA: 2, valueA: 3, categoryB: 1, valueB: 3),
                // The Monstera is watered on Friday.
                .same(categoryA: 0, valueA: 0, categoryB: 2, valueB: 2),
                // The white pot is watered on Sunday.
                .same(categoryA: 1, valueA: 2, categoryB: 2, valueB: 3),
                // The Fern is somewhere left of the Pothos.
                .before(categoryA: 0, valueA: 1, categoryB: 0, valueB: 2)
            ],
            explanation: t(
                "Start with the two fixed pairs: the Monstera is on shelf one and watered Friday, and the white pot is watered Sunday. The Calathea's Wednesday and the Sunday-before-green clue push green to the far right, which leaves the Calathea there. The Fern is left of the Pothos, so the Fern takes shelf two and the Pothos shelf three — and the blue pot follows the Fern.",
                "puzzle.jungleLogic.shelf.explanation"
            )
        )),
        baseScore: 120
    )

    /// Five windowsills, three categories, nine clues. Also proved unique.
    ///
    /// Solution: Monstera/green/Tuesday, Calathea/terracotta/Friday,
    /// Snake plant/white/Monday, Fern/amber/Wednesday, Pothos/blue/Thursday.
    static let jungleLogicWindowsill = PuzzleDefinition(
        id: "sunnie.puzzle.jungleLogic.windowsill",
        gameID: "sunnie.game.jungleLogic",
        difficulty: .steady,
        title: t("Five windowsills", "puzzle.jungleLogic.windowsill.title"),
        payload: .gridAssignment(GridPuzzle(
            positionLabel: t("Windowsill", "puzzle.jungleLogic.windowsill.positions"),
            categories: [
                GridCategory(
                    name: t("Plant", "puzzle.jungleLogic.windowsill.cat.plant"),
                    values: [
                        t("Calathea", "puzzle.jungleLogic.windowsill.plant.calathea"),
                        t("Fern", "puzzle.jungleLogic.windowsill.plant.fern"),
                        t("Monstera", "puzzle.jungleLogic.windowsill.plant.monstera"),
                        t("Pothos", "puzzle.jungleLogic.windowsill.plant.pothos"),
                        t("Snake plant", "puzzle.jungleLogic.windowsill.plant.snake")
                    ]
                ),
                GridCategory(
                    name: t("Pot", "puzzle.jungleLogic.windowsill.cat.pot"),
                    values: [
                        t("Terracotta", "puzzle.jungleLogic.windowsill.pot.terracotta"),
                        t("Blue", "puzzle.jungleLogic.windowsill.pot.blue"),
                        t("White", "puzzle.jungleLogic.windowsill.pot.white"),
                        t("Green", "puzzle.jungleLogic.windowsill.pot.green"),
                        t("Amber", "puzzle.jungleLogic.windowsill.pot.amber")
                    ]
                ),
                GridCategory(
                    name: t("Watering day", "puzzle.jungleLogic.windowsill.cat.day"),
                    values: [
                        t("Monday", "puzzle.jungleLogic.windowsill.day.monday"),
                        t("Tuesday", "puzzle.jungleLogic.windowsill.day.tuesday"),
                        t("Wednesday", "puzzle.jungleLogic.windowsill.day.wednesday"),
                        t("Thursday", "puzzle.jungleLogic.windowsill.day.thursday"),
                        t("Friday", "puzzle.jungleLogic.windowsill.day.friday")
                    ]
                )
            ],
            constraints: [
                // Monday's plant is somewhere left of Wednesday's.
                .before(categoryA: 2, valueA: 0, categoryB: 2, valueB: 2),
                // The snake plant is next to the Wednesday plant.
                .adjacent(categoryA: 0, valueA: 4, categoryB: 2, valueB: 2),
                // The green pot is somewhere left of the Monday plant.
                .before(categoryA: 1, valueA: 3, categoryB: 2, valueB: 0),
                // The Calathea is in the terracotta pot.
                .same(categoryA: 0, valueA: 0, categoryB: 1, valueB: 0),
                // The Monstera is watered on Tuesday.
                .same(categoryA: 0, valueA: 2, categoryB: 2, valueB: 1),
                // The white pot is next to the Friday plant.
                .adjacent(categoryA: 1, valueA: 2, categoryB: 2, valueB: 4),
                // The terracotta pot is somewhere left of the Monday plant.
                .before(categoryA: 1, valueA: 0, categoryB: 2, valueB: 0),
                // The Fern is somewhere left of the blue pot.
                .before(categoryA: 0, valueA: 1, categoryB: 1, valueB: 1),
                // The snake plant is somewhere left of the Thursday plant.
                .before(categoryA: 0, valueA: 4, categoryB: 2, valueB: 3)
            ],
            explanation: t(
                "The green pot and the terracotta pot both sit left of Monday, so Monday cannot be on the first two sills. The Calathea travels with the terracotta pot, and the Monstera with Tuesday. Once Monday lands on the third sill, the snake plant has to be there too — it is left of Thursday and beside Wednesday. The Fern before the blue pot then fixes the last two.",
                "puzzle.jungleLogic.windowsill.explanation"
            )
        )),
        baseScore: 180
    )

    // MARK: - G-04 Memory Atlas

    static let memoryAtlasScrapbook = PuzzleDefinition(
        id: "sunnie.puzzle.memoryAtlas.scrapbook",
        gameID: "sunnie.game.memoryAtlas",
        difficulty: .steady,
        title: t("A page from the scrapbook", "puzzle.memoryAtlas.scrapbook.title"),
        payload: .studyThenQuiz(StudyPuzzle(
            rows: 3,
            columns: 3,
            items: [
                StudyItem(
                    label: t("Ferry ticket", "puzzle.memoryAtlas.scrapbook.item1"),
                    detail: t("Blue, punched twice", "puzzle.memoryAtlas.scrapbook.item1.detail"),
                    row: 0, column: 0
                ),
                StudyItem(
                    label: t("Pressed fern", "puzzle.memoryAtlas.scrapbook.item2"),
                    detail: t("Taped at the stem", "puzzle.memoryAtlas.scrapbook.item2.detail"),
                    row: 0, column: 2
                ),
                StudyItem(
                    label: t("Café receipt", "puzzle.memoryAtlas.scrapbook.item3"),
                    detail: t("Two coffees, one pastry", "puzzle.memoryAtlas.scrapbook.item3.detail"),
                    row: 1, column: 1
                ),
                StudyItem(
                    label: t("Postage stamp", "puzzle.memoryAtlas.scrapbook.item4"),
                    detail: t("A green lighthouse", "puzzle.memoryAtlas.scrapbook.item4.detail"),
                    row: 1, column: 2
                ),
                StudyItem(
                    label: t("Train map", "puzzle.memoryAtlas.scrapbook.item5"),
                    detail: t("Folded to one corner", "puzzle.memoryAtlas.scrapbook.item5.detail"),
                    row: 2, column: 0
                ),
                StudyItem(
                    label: t("Shell", "puzzle.memoryAtlas.scrapbook.item6"),
                    detail: t("Small, ridged, sandy", "puzzle.memoryAtlas.scrapbook.item6.detail"),
                    row: 2, column: 2
                )
            ],
            questions: [
                StudyQuestion(
                    prompt: t(
                        "What was in the top-left corner of the page?",
                        "puzzle.memoryAtlas.scrapbook.q1"
                    ),
                    options: [
                        t("The ferry ticket", "puzzle.memoryAtlas.scrapbook.q1.a"),
                        t("The train map", "puzzle.memoryAtlas.scrapbook.q1.b"),
                        t("The pressed fern", "puzzle.memoryAtlas.scrapbook.q1.c"),
                        t("The shell", "puzzle.memoryAtlas.scrapbook.q1.d")
                    ],
                    answerIndex: 0,
                    explanation: t(
                        "The ferry ticket. The train map was in the bottom-left, which is the easiest pair to swap.",
                        "puzzle.memoryAtlas.scrapbook.q1.explanation"
                    )
                ),
                StudyQuestion(
                    prompt: t(
                        "What was on the postage stamp?",
                        "puzzle.memoryAtlas.scrapbook.q2"
                    ),
                    options: [
                        t("A green lighthouse", "puzzle.memoryAtlas.scrapbook.q2.a"),
                        t("A blue lighthouse", "puzzle.memoryAtlas.scrapbook.q2.b"),
                        t("A green sailing boat", "puzzle.memoryAtlas.scrapbook.q2.c"),
                        t("A green bridge", "puzzle.memoryAtlas.scrapbook.q2.d")
                    ],
                    answerIndex: 0,
                    explanation: t(
                        "A green lighthouse. Blue belonged to the ferry ticket — the colour and the object come from different corners of the page.",
                        "puzzle.memoryAtlas.scrapbook.q2.explanation"
                    )
                ),
                StudyQuestion(
                    prompt: t(
                        "How many things were in the middle column?",
                        "puzzle.memoryAtlas.scrapbook.q3"
                    ),
                    options: [
                        t("None", "puzzle.memoryAtlas.scrapbook.q3.a"),
                        t("One", "puzzle.memoryAtlas.scrapbook.q3.b"),
                        t("Two", "puzzle.memoryAtlas.scrapbook.q3.c"),
                        t("Three", "puzzle.memoryAtlas.scrapbook.q3.d")
                    ],
                    answerIndex: 1,
                    explanation: t(
                        "One — the café receipt. The page leaned to its edges, which is what makes the middle easy to lose.",
                        "puzzle.memoryAtlas.scrapbook.q3.explanation"
                    )
                ),
                StudyQuestion(
                    prompt: t(
                        "What did the café receipt list?",
                        "puzzle.memoryAtlas.scrapbook.q4"
                    ),
                    options: [
                        t("One coffee, two pastries", "puzzle.memoryAtlas.scrapbook.q4.a"),
                        t("Two coffees, one pastry", "puzzle.memoryAtlas.scrapbook.q4.b"),
                        t("Two coffees, two pastries", "puzzle.memoryAtlas.scrapbook.q4.c"),
                        t("One coffee, one pastry", "puzzle.memoryAtlas.scrapbook.q4.d")
                    ],
                    answerIndex: 1,
                    explanation: t(
                        "Two coffees, one pastry. Swapping the two numbers is the interference this question is built on.",
                        "puzzle.memoryAtlas.scrapbook.q4.explanation"
                    )
                )
            ],
            defaultStudySeconds: 20
        )),
        baseScore: 140,
        reportsTime: true
    )

    // MARK: - G-05 Lost in Translation

    static let translationFalseFriends = PuzzleDefinition(
        id: "sunnie.puzzle.translation.falseFriends",
        gameID: "sunnie.game.lostInTranslation",
        difficulty: .gentle,
        title: t("Three false friends", "puzzle.translation.falseFriends.title"),
        payload: .answerChain(AnswerChainPuzzle(stops: [
            AnswerChainStop(
                prompt: t(
                    "Spanish embarazada looks like an English word and means something else entirely. In English, what does it actually mean?",
                    "puzzle.translation.falseFriends.stop1"
                ),
                answer: "pregnant",
                alternates: ["expecting"],
                language: .spanish,
                linkExplanation: t(
                    "Embarazada means pregnant. The English word it resembles is embarrassed, which in Spanish is avergonzada — a false friend is a word that looks borrowed and is not.",
                    "puzzle.translation.falseFriends.link1"
                ),
                hints: [
                    t("It has nothing to do with feeling awkward.", "puzzle.translation.falseFriends.hint1a")
                ]
            ),
            AnswerChainStop(
                prompt: t(
                    "French librairie is a false friend too. What is sold there?",
                    "puzzle.translation.falseFriends.stop2"
                ),
                answer: "books",
                alternates: ["book", "bookshop", "bookstore", "book shop"],
                language: .french,
                linkExplanation: t(
                    "A librairie is a bookshop — you buy there. The French for library is bibliothèque, where you borrow.",
                    "puzzle.translation.falseFriends.link2"
                ),
                hints: [
                    t("You pay for what you take home.", "puzzle.translation.falseFriends.hint2a")
                ]
            ),
            AnswerChainStop(
                prompt: t(
                    "Portuguese doors are printed with puxe, which looks like push. Which way does the door go?",
                    "puzzle.translation.falseFriends.stop3"
                ),
                answer: "pull",
                alternates: ["you pull", "pull it", "puxar"],
                language: .portuguese,
                linkExplanation: t(
                    "Puxe means pull — the opposite of what it looks like. Push is empurre. Three words in a row that borrow a shape and keep their own meaning.",
                    "puzzle.translation.falseFriends.link3"
                ),
                hints: [
                    t("It is the opposite of what the shape suggests.", "puzzle.translation.falseFriends.hint3a")
                ]
            )
        ])),
        baseScore: 100
    )

    static let translationNightChain = PuzzleDefinition(
        id: "sunnie.puzzle.translation.night",
        gameID: "sunnie.game.lostInTranslation",
        difficulty: .steady,
        title: t("One word, four descendants", "puzzle.translation.night.title"),
        payload: .answerChain(AnswerChainPuzzle(stops: [
            AnswerChainStop(
                prompt: t(
                    "English night, German Nacht, Dutch nacht. What is the Spanish?",
                    "puzzle.translation.night.stop1"
                ),
                answer: "noche",
                alternates: ["la noche"],
                language: .spanish,
                linkExplanation: t(
                    "Noche. It came from Latin noctem, where the -ct- softened into the Spanish -ch-.",
                    "puzzle.translation.night.link1"
                ),
                hints: [t("Five letters.", "puzzle.translation.night.hint1a")]
            ),
            AnswerChainStop(
                prompt: t(
                    "The same Latin word, in Portuguese.",
                    "puzzle.translation.night.stop2"
                ),
                answer: "noite",
                alternates: ["a noite"],
                language: .portuguese,
                linkExplanation: t(
                    "Noite. Portuguese turned the same -ct- into -it-, which it does consistently: oito for eight, leite for milk.",
                    "puzzle.translation.night.link2"
                ),
                hints: [
                    t("Compare oito and leite — the same change.", "puzzle.translation.night.hint2a")
                ]
            ),
            AnswerChainStop(
                prompt: t(
                    "And in French.",
                    "puzzle.translation.night.stop3"
                ),
                answer: "nuit",
                alternates: ["la nuit"],
                language: .french,
                linkExplanation: t(
                    "Nuit. French compressed it furthest of the three, and stopped pronouncing the ending altogether.",
                    "puzzle.translation.night.link3"
                ),
                hints: [t("Four letters.", "puzzle.translation.night.hint3a")]
            ),
            AnswerChainStop(
                prompt: t(
                    "Last: the Latin word all three grew from, in its dictionary form.",
                    "puzzle.translation.night.stop4"
                ),
                answer: "nox",
                alternates: ["noctem", "nox noctis"],
                linkExplanation: t(
                    "Nox, whose accusative noctem is the form the daughters actually inherited. Noche, noite, nuit — one word, three routes, and none of them a borrowing from the others.",
                    "puzzle.translation.night.link4"
                ),
                hints: [
                    t("Three letters, ending in x.", "puzzle.translation.night.hint4a")
                ]
            )
        ])),
        baseScore: 160
    )

    // MARK: - G-06 Sunnie's Suitcase

    static let suitcasePorto = PuzzleDefinition(
        id: "sunnie.puzzle.suitcase.porto",
        gameID: "sunnie.game.sunniesSuitcase",
        difficulty: .steady,
        title: t("Four days in Porto", "puzzle.suitcase.porto.title"),
        payload: .constrainedSelection(SelectionPuzzle(
            brief: t(
                "Four days in Porto in November. Two long days of walking, one dinner out, and a small bag with a strict weight limit.",
                "puzzle.suitcase.porto.brief"
            ),
            candidates: [
                SelectionCandidate(
                    name: t("Rain jacket", "puzzle.suitcase.porto.item1"),
                    tags: ["rain", "outer"], weight: 3
                ),
                SelectionCandidate(
                    name: t("Wool jumper", "puzzle.suitcase.porto.item2"),
                    tags: ["warm"], weight: 3
                ),
                SelectionCandidate(
                    name: t("Linen shirt", "puzzle.suitcase.porto.item3"),
                    tags: ["formal"], weight: 1
                ),
                SelectionCandidate(
                    name: t("Walking shoes", "puzzle.suitcase.porto.item4"),
                    tags: ["walking", "shoes"], weight: 4
                ),
                SelectionCandidate(
                    name: t("Smart shoes", "puzzle.suitcase.porto.item5"),
                    tags: ["formal", "shoes"], weight: 3
                ),
                SelectionCandidate(
                    name: t("Umbrella", "puzzle.suitcase.porto.item6"),
                    tags: ["rain"], weight: 2
                ),
                SelectionCandidate(
                    name: t("Swimsuit", "puzzle.suitcase.porto.item7"),
                    tags: ["swim"], weight: 1
                ),
                SelectionCandidate(
                    name: t("Camera", "puzzle.suitcase.porto.item8"),
                    tags: ["gear"], weight: 3
                ),
                SelectionCandidate(
                    name: t("Paperback", "puzzle.suitcase.porto.item9"),
                    tags: ["gear"], weight: 2
                ),
                SelectionCandidate(
                    name: t("Scarf", "puzzle.suitcase.porto.item10"),
                    tags: ["warm"], weight: 1
                )
            ],
            rules: [
                SelectionRule(
                    requirement: .atLeast(tag: "rain", count: 1),
                    explanation: t(
                        "Porto in November: something for rain.",
                        "puzzle.suitcase.porto.rule1"
                    )
                ),
                SelectionRule(
                    requirement: .atLeast(tag: "warm", count: 1),
                    explanation: t(
                        "Evenings by the river are cold. Something warm.",
                        "puzzle.suitcase.porto.rule2"
                    )
                ),
                SelectionRule(
                    requirement: .atLeast(tag: "formal", count: 2),
                    explanation: t(
                        "One dinner out wants both a shirt and shoes to go with it.",
                        "puzzle.suitcase.porto.rule3"
                    )
                ),
                SelectionRule(
                    requirement: .atLeast(tag: "walking", count: 1),
                    explanation: t(
                        "Two days on the hills need shoes made for it.",
                        "puzzle.suitcase.porto.rule4"
                    )
                ),
                SelectionRule(
                    requirement: .forbid(tag: "swim"),
                    explanation: t(
                        "The hotel pool is closed for the season, so a swimsuit is weight with nothing to do.",
                        "puzzle.suitcase.porto.rule5"
                    )
                ),
                SelectionRule(
                    requirement: .weightLimit(12),
                    explanation: t(
                        "The bag holds twelve units and no more.",
                        "puzzle.suitcase.porto.rule6"
                    )
                ),
                SelectionRule(
                    requirement: .itemLimit(6),
                    explanation: t(
                        "Six things, so everything can be found without unpacking.",
                        "puzzle.suitcase.porto.rule7"
                    )
                )
            ],
            explanation: t(
                "The weight limit is what makes this a puzzle rather than a list. The wool jumper and the walking shoes together leave too little for two formal items, so the scarf does the warm job at a third of the weight. The rain jacket beats the umbrella because it is also the outer layer. The swimsuit is the trap: it is light, it looks harmless, and the pool is shut.",
                "puzzle.suitcase.porto.explanation"
            )
        )),
        baseScore: 150
    )

    // MARK: - G-07 Trivia Trail

    static let triviaTrailIberia = PuzzleDefinition(
        id: "sunnie.puzzle.triviaTrail.iberia",
        gameID: "sunnie.game.triviaTrail",
        difficulty: .gentle,
        title: t("Down the Atlantic coast", "puzzle.triviaTrail.iberia.title"),
        payload: .branchingChoice(BranchingPuzzle(
            startNodeID: "arrival",
            nodes: [
                TrailNode(
                    id: "arrival",
                    prompt: t(
                        "Your flight lands at an airport with the code LIS. Which country are you in?",
                        "puzzle.triviaTrail.iberia.arrival"
                    ),
                    options: [
                        TrailOption(
                            text: t("Portugal", "puzzle.triviaTrail.iberia.arrival.a"),
                            nextNodeID: "coast",
                            isEfficient: true,
                            explanation: t(
                                "Portugal. LIS is Lisbon, and the airport sits inside the city — one of the few in Europe that does.",
                                "puzzle.triviaTrail.iberia.arrival.a.why"
                            )
                        ),
                        TrailOption(
                            text: t("Spain", "puzzle.triviaTrail.iberia.arrival.b"),
                            nextNodeID: "detour",
                            isEfficient: false,
                            explanation: t(
                                "Spain's capital airport is MAD. LIS is Lisbon — a short detour, and the trail carries on.",
                                "puzzle.triviaTrail.iberia.arrival.b.why"
                            )
                        ),
                        TrailOption(
                            text: t("Italy", "puzzle.triviaTrail.iberia.arrival.c"),
                            nextNodeID: "detour",
                            isEfficient: false,
                            explanation: t(
                                "Italy's codes begin elsewhere — FCO for Rome. LIS is Lisbon.",
                                "puzzle.triviaTrail.iberia.arrival.c.why"
                            )
                        )
                    ]
                ),
                TrailNode(
                    id: "detour",
                    prompt: t(
                        "The scenic way round. Which river does Lisbon stand on?",
                        "puzzle.triviaTrail.iberia.detour"
                    ),
                    options: [
                        TrailOption(
                            text: t("The Tagus", "puzzle.triviaTrail.iberia.detour.a"),
                            nextNodeID: "coast",
                            isEfficient: true,
                            explanation: t(
                                "The Tagus — Tejo in Portuguese. It is the longest river on the peninsula.",
                                "puzzle.triviaTrail.iberia.detour.a.why"
                            )
                        ),
                        TrailOption(
                            text: t("The Douro", "puzzle.triviaTrail.iberia.detour.b"),
                            nextNodeID: "coast",
                            isEfficient: false,
                            explanation: t(
                                "The Douro reaches the sea at Porto, further north. Lisbon's river is the Tagus.",
                                "puzzle.triviaTrail.iberia.detour.b.why"
                            )
                        )
                    ]
                ),
                TrailNode(
                    id: "coast",
                    prompt: t(
                        "You take the train south to the Algarve and look out to sea. Which ocean is in front of you?",
                        "puzzle.triviaTrail.iberia.coast"
                    ),
                    options: [
                        TrailOption(
                            text: t("The Atlantic", "puzzle.triviaTrail.iberia.coast.a"),
                            nextNodeID: "market",
                            isEfficient: true,
                            explanation: t(
                                "The Atlantic. Portugal has no Mediterranean coast at all — the sea begins east of Gibraltar.",
                                "puzzle.triviaTrail.iberia.coast.a.why"
                            )
                        ),
                        TrailOption(
                            text: t("The Mediterranean", "puzzle.triviaTrail.iberia.coast.b"),
                            nextNodeID: "market",
                            isEfficient: false,
                            explanation: t(
                                "The Mediterranean starts east of the Strait of Gibraltar, so the Algarve looks out on the Atlantic.",
                                "puzzle.triviaTrail.iberia.coast.b.why"
                            )
                        )
                    ]
                ),
                TrailNode(
                    id: "market",
                    prompt: t(
                        "At the market, a stall sells piri-piri. Where did the chilli in it originally come from?",
                        "puzzle.triviaTrail.iberia.market"
                    ),
                    options: [
                        TrailOption(
                            text: t("The Americas", "puzzle.triviaTrail.iberia.market.a"),
                            nextNodeID: "finish",
                            isEfficient: true,
                            explanation: t(
                                "The Americas. Chillies reached Africa and Asia on Portuguese ships, which is why piri-piri is a Mozambican name for an American plant.",
                                "puzzle.triviaTrail.iberia.market.a.why"
                            )
                        ),
                        TrailOption(
                            text: t("East Africa", "puzzle.triviaTrail.iberia.market.b"),
                            nextNodeID: "finish",
                            isEfficient: false,
                            explanation: t(
                                "The name is East African, and that is the confusion the question is built on — but the plant itself is American.",
                                "puzzle.triviaTrail.iberia.market.b.why"
                            )
                        ),
                        TrailOption(
                            text: t("India", "puzzle.triviaTrail.iberia.market.c"),
                            nextNodeID: "finish",
                            isEfficient: false,
                            explanation: t(
                                "India grows more chillies than anywhere, but it received them from Portuguese traders in the sixteenth century.",
                                "puzzle.triviaTrail.iberia.market.c.why"
                            )
                        )
                    ]
                ),
                TrailNode(
                    id: "finish",
                    prompt: t(
                        "Last stop. Cabo de São Vicente was once thought to be the end of the world. Which direction are you facing at sunset?",
                        "puzzle.triviaTrail.iberia.finish"
                    ),
                    options: [
                        TrailOption(
                            text: t("West", "puzzle.triviaTrail.iberia.finish.a"),
                            nextNodeID: nil,
                            isEfficient: true,
                            explanation: t(
                                "West. It is the south-westernmost point of mainland Europe, and for a long time nobody knew what lay beyond it.",
                                "puzzle.triviaTrail.iberia.finish.a.why"
                            )
                        ),
                        TrailOption(
                            text: t("South", "puzzle.triviaTrail.iberia.finish.b"),
                            nextNodeID: nil,
                            isEfficient: false,
                            explanation: t(
                                "The cape does look south over the Algarve coast, but the sun sets to the west — out over the open Atlantic.",
                                "puzzle.triviaTrail.iberia.finish.b.why"
                            )
                        )
                    ]
                )
            ]
        )),
        baseScore: 120
    )
}
