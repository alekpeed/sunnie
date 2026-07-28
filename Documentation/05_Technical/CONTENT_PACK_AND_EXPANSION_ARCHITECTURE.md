# Content Pack and Expansion Architecture

## 1. Purpose

Allow new themes, destinations, games, affirmations, messages, audio, meditations, collectibles, and story scenes without rewriting unrelated features.

## 2. Pack types

- Theme pack
- Destination pack
- Game pack
- Puzzle/content pack
- Sunnie message pack
- Affirmation pack
- Meditation pack
- Audio pack
- Collectible pack
- Story-scene pack

## 3. Manifest requirements

Every pack defines:

- Stable ID
- Semantic version
- Pack type
- Display name
- Minimum app version
- Dependencies
- Localization list
- Content file list
- Asset list
- Checksums
- Unlock rules
- Migration notes
- Private/public distribution status

## 4. Example manifest

```json
{
  "id": "destination.paris.core",
  "version": "1.0.0",
  "type": "destination",
  "minimumAppVersion": "1.0.0",
  "dependencies": ["outfit.paris.beret"],
  "locales": ["en"],
  "assets": ["paris_bg_day", "paris_stamp_01"],
  "content": ["paris_trivia.json", "paris_postcards.json"],
  "privateUseOnly": true
}
```

## 5. Registry

`ContentRegistry`:

- Discovers bundled/installed packs
- Validates schema and version
- Resolves dependencies
- Rejects duplicate IDs
- Provides typed queries
- Records install state
- Supports safe fallback when assets are missing

## 6. Content IDs

Use stable dot-delimited IDs:

```text
theme.jungle.core
message.today.greeting.day.001
reward.outfit.flight.navy.001
game.jungleLogic.core
meditation.travelReset.001
```

Never use display names as database keys.

## 7. Validation

Build/test scripts validate:

- JSON/schema shape
- Duplicate IDs
- Missing assets
- Missing localization
- Invalid reward references
- Unsupported minimum app version
- Cyclic dependencies
- Prohibited tone phrases
- Missing accessibility descriptions

## 8. User data separation

Content definitions are immutable/versioned. User state stores references and ownership separately. Updating a pack must not overwrite user progress.

## 9. Download behavior

The initial app may bundle core content. Later downloadable packs require:

- Signed/trusted source
- Atomic installation
- Resume/retry
- Storage display
- Removal option
- Offline use after installation
- Version rollback or safe failure

Do not build a public marketplace.

## 10. Game rules

Rule-engine code is versioned with the app or approved module. Puzzle data can be pack-driven. Do not execute arbitrary downloaded code.

## 11. Theme rules

Theme packs provide semantic tokens and approved assets. Feature views request semantic values; they do not branch on theme IDs.

## 12. Audio rules

Audio packs register runtime assets and cue assignments. Source MIDI remains creator-side unless runtime MIDI is explicitly needed.
