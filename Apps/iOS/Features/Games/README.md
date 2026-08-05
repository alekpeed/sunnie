# Games

Built in Phase 7 (`Documentation/06_Delivery/IMPLEMENTATION_ROADMAP.md`).

```
Games/
├── Screens/
│   ├── GamesHomeScreen.swift     S-18 — daily puzzle, continue, categories, results
│   ├── GameSessionScreen.swift   S-19 — the host frame, plus the session model
│   └── GameResultView.swift      S-20 — result, explanation, reward, Sunnie's reaction
├── Components/
│   └── GameBoardViews.swift      one view per interaction shape
└── UseCases/
    └── PlayGame.swift            start, save, resume, finish, award
```

The rules live in `SunnieShared/Games/` and the content in
`SunnieShared/ContentSchemas/BuiltInGameContent.swift`. Nothing in this folder
knows what a postcard or a shelf is.

## Seven games, six shapes

The spec names seven games. They reduce to six interaction shapes, and two games
sharing a shape share the board, the accessibility path, and the save format
while keeping entirely separate rules and content.

| Shape | Games |
|---|---|
| `answerChain` | Word Layover, Lost in Translation |
| `revealAndIdentify` | Postcard Cipher |
| `gridAssignment` | Jungle Logic |
| `studyThenQuiz` | Memory Atlas |
| `constrainedSelection` | Sunnie's Suitcase |
| `branchingChoice` | Trivia Trail |

Adding a **shape** is real work: an engine, a board, a save encoding, and an
accessibility path. Adding a **game** to an existing shape is content.

## Two decisions worth knowing before changing anything here

- **A saved game is its move log, not its board** (ADR-023). The board is
  replayed from `[GameMove]` on every read. Do not persist a board snapshot —
  it would need migrating every time a layout changes, and the alternative to
  migrating it is discarding someone's half-finished puzzle.
- **The built-in pack is Swift, not JSON** (ADR-022). Added packs still load
  from JSON; the initial set is Swift so that a mistyped answer index is a
  compile error rather than a puzzle that tells a player they are wrong.

## What this feature must never grow

From GAMES_AND_FUTURE_MULTIPLAYER.md §7, and enforced in code rather than left
to review:

- **No streak.** There is no counter, no "days in a row", and no state that a
  missed day could break — the daily puzzle is a pure function of the date.
- **No reward for starting and abandoning.** Only a finished session awards, and
  the award is keyed on the puzzle, so replaying is free and earns nothing.
- **No purchased energy, lives, or hints.** A hint costs score and nothing else.
- **No difficulty tied to how anyone is doing.** Difficulty is a choice, named
  after the puzzle rather than the player.

## Accessibility (§10)

No board is drag-driven — every one is taps, menus, or a text field, which is
the alternative interaction rather than a substitute bolted on beside it. No
state is carried by colour alone. The memory game's timer can be removed
entirely at no cost to the score. Nothing is solvable only by sound.
