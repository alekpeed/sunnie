# Feature Specification — Games and Future Multiplayer

## 1. Objective

Create clever, replayable games that feel native to Sunnie Days. Games should draw on wordplay, languages, travel, plants, memory, trivia, and logic. They must not be reskinned copies of common app-store templates.

## 2. Shared game host

The host provides:

- Session creation
- Deterministic seed
- Save/resume
- Pause and exit
- Rules/help
- Hints
- Audio and haptics
- Accessibility settings
- Results
- Reward event
- Daily challenge handling

Individual games implement their own rule engine and presentation.

## 3. Initial game set

### G-01: Word Layover

A route-based word game. Each stop presents a clue whose answer becomes a constrained bridge to the next destination. Some rounds use a language shift between English, Spanish, Portuguese, or French. The mechanic is semantic connection and route construction, not simple anagrams.

Example structure:

- Solve clue A.
- Use one meaning, translation, or sound link to unlock clue B.
- Complete the route with the fewest hints.

### G-02: Postcard Cipher

The player reconstructs a destination from partial postcard elements: text fragments, stamp marks, weather clues, landmarks, and local-language phrases. Clues can be revealed in different orders, changing score and difficulty.

### G-03: Jungle Logic

A deduction puzzle about plant placement and care. The player uses constraints such as room, light, watering day, pot color, and species to determine a valid arrangement. Puzzle generation must guarantee a unique solution.

### G-04: Memory Atlas

The player briefly studies a scrapbook page containing places, objects, colors, and route positions. The page disappears, then the player answers spatial and detail questions. Difficulty changes exposure time, item count, and interference.

### G-05: Lost in Translation

The player reconstructs a phrase through a chain of multilingual clues. Some steps use direct meaning; others use cognates, false friends, idioms, or context. Explanations teach the language connection after each round.

### G-06: Sunnie’s Suitcase

A constrained packing deduction game. The player must choose items that satisfy destination, weather, duration, work, weight, and compatibility rules. Multiple valid-looking options require reasoning; it is not a checklist simulator.

### G-07: Trivia Trail

A branching travel/trivia journey. Correct answers choose the most efficient route; explanations and postcards reveal context. Categories can include geography, culture, language, plants, music, and general knowledge.

## 4. Daily puzzle

- One deterministic puzzle per local calendar day
- Available offline after content is installed
- Save/resume
- No penalty for missing a day
- Archive access may unlock later
- Daily puzzle rotates among compatible games

## 5. Difficulty

Each game defines:

- Difficulty levels
- Tutorial mode
- Hint cost in score only, never paid currency
- Accessibility adjustments
- Content-language requirements

Difficulty should respond to explicit choice and performance history without hiding rules.

## 6. Results and explanations

Every knowledge or logic game provides an explanation. Results include:

- Completion state
- Score or efficiency
- Time, only if relevant
- Hints used
- Explanation
- Reward progress
- Sunnie response

## 7. Progression safeguards

- No reward for repeatedly starting/abandoning sessions.
- Deterministic event IDs prevent duplicate rewards.
- No purchased energy or lives.
- No punitive daily streak.
- Difficulty is not tied to wellness or self-worth language.

## 8. Content packs

A game pack includes:

- Stable pack ID/version
- Game definitions
- Puzzle content or generator configuration
- Localization
- Difficulty metadata
- Assets
- Audio cues
- Reward table
- Minimum app version

## 9. Future turn-based multiplayer

The initial iOS app prepares by using:

- Serializable game state
- Deterministic actions
- Stable player/turn IDs
- No CloudKit-specific types in game domain models
- Replaceable `MultiplayerService` protocol

Future modes may include:

- Clue Exchange: each player holds partial clues
- Cooperative route puzzle
- Asynchronous word challenge
- Shared trivia trail

Do not implement network multiplayer or Android now.

## 10. Accessibility

- VoiceOver-readable board state
- Non-color identifiers
- Adjustable text
- Reduced motion
- Extended timers or no timer
- Alternative interaction for drag-heavy mechanics
- Audio cues never required to solve a puzzle
