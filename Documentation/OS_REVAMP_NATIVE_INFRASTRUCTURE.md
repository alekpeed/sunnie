# Sunnie Days OS Revamp — Native Infrastructure

Status: implemented on `main` for review.

This slice extends the existing personal-OS architecture without introducing a
new persistence layer or product silo.

## Capability and permission broker

`CapabilityBroker` is the sole translation point from native authorization APIs
to the platform-neutral `SunnieCapability`, `CapabilityState`, and
`CapabilitySnapshot` contracts. Reading the snapshot never prompts. Individual
features continue to request access only after a user chooses an action that
needs it, and unavailable enhancements do not disable core behavior.

## Background maintenance

`BackgroundMaintenanceCoordinator` schedules one best-effort app-refresh task.
Its plan only rebuilds derived context, world, widget, reward, search, favorites,
and housekeeping state. Every operation is idempotent; no deadline, reminder,
Flight Mode decision, or safety-sensitive behavior depends on iOS running it.

## Unified private search

`SearchEntity` is the shared vocabulary for plants, trips, places, travel
memories, recipes, games, and Curios. `UnifiedSearchService` reconstructs these
projections from authoritative repositories, powers the in-app search surface,
and mirrors the same entities into Core Spotlight with typed Sunnie Days deep
links. The index is disposable and contains no journal or wellness content.

## App Intents

The existing App Intents layer now exposes Tell Sunnie capture, a read-only
current-context summary, and safe Flight Mode packing. Packing still passes
through `ManagePacking`, refuses to guess without an active explicit work trip,
and refreshes derived system surfaces after mutation.

## Personal favorites intelligence

`PersonalFavoritesService` derives explicit favorite places and recipes plus
conservative repeated-destination signals. Explicit choices always override
inference. Inferred signals only affect ranking and recall, are never written
back to feature repositories, and can be disabled from Settings.

## Shared tests

`SystemIntegrationTests` covers capability fallback, private-search matching,
explicit-over-inferred preference ordering, the repeated-evidence threshold, and
idempotent maintenance-plan ordering.
