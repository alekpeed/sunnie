# Feature Specification — Progression, Collections, and Sunnie Home

## 1. Objective

Reward meaningful engagement and make Sunnie’s world evolve without pressure, monetization, or loss aversion.

## 2. Progression vocabulary

Use positive terms such as:

- Level
- Milestone
- Rhythm
- Collection
- Discovery
- Journey
- Garden growth

Avoid “failure,” “broken streak,” “penalty,” or “decay.”

## 3. Progression events

Examples:

- Plant added
- Appropriate care completed
- Growth photo added
- Travel plan completed
- Trip memory saved
- Wellness check-in
- Meditation completed
- Meal prep completed
- Puzzle completed
- New destination visited

Each event has a deterministic key and is evaluated once.

## 4. Experience and levels

- Experience is optional to display prominently.
- Levels unlock content at predictable thresholds.
- No experience is removed.
- Routine actions have diminishing or capped reward rules to prevent farming or harmful repeated plant care.

## 5. Rhythm/streak behavior

The app may celebrate repeated activity, but:

- Missing a day does not erase earned content.
- The interface may say “3 caring days this week” rather than “streak broken.”
- Historical bests remain visible without negative comparison.
- User may hide rhythm metrics.

## 6. Reward categories

- Sunnie outfits
- Home decor
- Decorative plants
- Postcards
- Passport stamps
- Souvenirs
- Music
- Ambient soundscapes
- Story scenes
- Theme variants
- Destination objects
- Game cosmetics

## 7. Reward rules

- Rewards explain their source.
- No random paid loot.
- Random free surprises may exist only if every outcome is positive and no duplicate causes disappointment without compensation.
- Reward grants are idempotent.
- Content-pack removal does not delete ownership records.

## 8. Sunnie Home

### Environment zones

- Cozy room
- Indoor jungle
- Travel nook
- Music corner
- Window/day-cycle background

### Customization

- Equip outfit
- Place approved decor in slots or constrained regions
- Select music/ambience
- Display postcards/stamps/souvenirs
- Select favorite plants

The initial release should use constrained placement rather than a full freeform physics editor.

## 9. Context changes

Sunnie Home may respond to:

- Active theme
- Time phase
- Current destination
- Recent unlock
- Season
- Recent plant or travel milestone

## 10. Destination scenes

Examples:

- Paris: beret, Paris travel objects, skyline art
- Tokyo: destination outfit and city details
- Vietnam: tropical/urban regional art
- Spain: warm plaza/travel objects
- Brazil: tropical/coastal art

Avoid reducing cultures to one caricature. Destination packs require thoughtful art and content review.

## 11. Story scenes

Short illustrated scenes may unlock through milestones. They are optional content and must not block practical features.

## 12. Offline and sync

- Ownership and placement persist locally.
- Cloud sync merges ownership by stable ID.
- Placement conflicts use latest explicit edit or a recoverable conflict record.
- Missing assets show a neutral placeholder while retaining ownership.
