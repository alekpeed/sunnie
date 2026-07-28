# Widgets

Reserved for the WidgetKit extension and App Intents, delivered in Phase 9
(`IMPLEMENTATION_ROADMAP.md`).

No target exists yet. Phase 0 calls for iPhone, Watch, and test targets only, and
the roadmap adds the widget extension "when implemented" — an empty extension
target would be scaffolding with nothing behind it.

## What is already in place

The foundation widgets need is built and tested:

- `WatchDueTask` and `WatchApplicationContext` in the shared package are
  platform-neutral `Codable` payload types. A widget timeline provider can use
  them unchanged.
- `AppRoute` and `DeepLinkParser` already resolve `sunniedays://` links, so a
  widget tap resolves into the same typed route system as a notification or a
  Watch handoff.
- `PlantSummaryProvider` produces `PlantTodaySummary`, which is the shape a
  plant-care widget would display.

## When adding the target

- Widgets read through a repository or summary provider; they never query
  SwiftData directly.
- Sharing the store with the app needs an App Group, which means an entitlement
  and an ADR update (see ADR-012 on why entitlements are currently inactive).
- Every widget needs a placeholder and a redacted state.
- Timeline entries respect the same time engine, so a widget shows the same
  branded presentation as the app.
