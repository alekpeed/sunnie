# Sunnie Days OS Revamp — World Layer

Status: implemented on `chatgpt/os-world-layer` for review.

This layer continues the personal-OS architecture established by the Unified Context Engine, Tell Sunnie, and Flight Mode. It does not create another feature silo or persistence system.

## Shared Sunnie world snapshot

`SunnieWorldSnapshot` is a read-only derived view of the user's existing Sunnie Days history and progression. `AppState` owns the current snapshot alongside `CurrentContext`, and both refresh together.

The snapshot currently contains:

- an ambient `WorldEnvironment`;
- permanent Curio Cabinet unlocks;
- Memory Book travel chapters.

The source features remain authoritative. World state does not write back into Travel, Jungle, Progression, or any other repository.

## Dynamic Sunnie Home

Sunnie Home now reacts to cross-feature context rather than being only a static decorated room.

Initial environmental states include:

- ordinary home state;
- plant-care day;
- preparing for a work trip;
- away on a work trip;
- returning from a work trip.

Active destination names flow into the home state when Flight Mode supplies them.

The Home assistant container also exposes a concise count of permanent curios and memory chapters while preserving Tell Sunnie and Flight Mode entry points.

## Curio Cabinet behavior

The initial `CurioCatalog` establishes monotonic permanent unlocks tied to durable progression level. A higher level can add objects but can never remove an object earned at a lower level.

The first catalog includes plant, travel, keepsake, and game objects. These are presentation rewards, not currencies and not consumables.

This contract deliberately prevents:

- reward decay;
- inactivity loss;
- streak-based removal;
- temporary ownership intended to pressure return visits.

Future destination-specific and achievement-specific curios should plug into the same snapshot rather than introduce a parallel inventory.

## Memory Book behavior

The first executable Memory Book slice turns existing travel records whose start date has arrived into read-only chapters. Chapters are sorted newest first and use stable trip-derived identities.

This is intentionally conservative. It does not automatically ingest journal, wellness, or photo material. Those sources remain opt-in future expansions because their cross-feature presentation has stronger privacy implications.

Future Memory Book sources can add typed chapter builders while preserving the same rule: the original feature owns the data; the Memory Book only composes it.

## Tests

`SunnieWorldTests` verifies:

- Curio unlocks are monotonic;
- higher durable progression unlocks additional curios;
- Memory Book chapters sort newest first.

## Next extensions

The contracts in this layer are intended to support richer room-scene reactions, destination keepsakes, visual Memory Book layouts, Curio inspection/placement, explicit favorites intelligence, and opt-in photo/language moments without changing the underlying OS architecture.
