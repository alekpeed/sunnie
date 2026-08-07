# Widgets

The WidgetKit extension, built in Phase 9
(`Documentation/06_Delivery/IMPLEMENTATION_ROADMAP.md`).

```
Widgets/
├── SunnieWidgetBundle.swift   the bundle and the one shared timeline provider
├── SunnieWidgets.swift        six widgets, plus their accessory families
└── Resources/
    ├── Info.plist
    └── SunnieWidgets.entitlements   the App Group — inactive by default
```

## The extension reads a file, never the store (ADR-027)

The app builds a `WidgetSnapshot` and writes it to the App Group container. The
extension reads that and nothing else — no SwiftData, no migrations, no content
packs.

That is a memory and a reliability decision (an extension has a small budget and
no way to report a crash), and a privacy one: `WidgetSnapshotPublisher` is the
single place that decides what a widget may show, so §8's privacy rule is one
reviewable function rather than a property of six timeline providers.

**Do not add a store to this target.** If a widget needs something new, add it
to the snapshot.

## Without an App Group, widgets say so

The App Group is an entitlement, and entitlements are inactive by default
(ADR-012). With none configured:

- `WidgetSnapshotStore` resolves no container.
- The app's write is a no-op.
- Every widget shows its "open Sunnie Days" state.

That is the honest degraded behaviour, not a bug. To turn it on, see the four
steps in `Config/Extension-Widgets.xcconfig`. The group identifier must match in
three places — both entitlements files and
`WidgetSnapshotStore.appGroupIdentifier` — and a mismatch is invisible and looks
exactly like "the widget never updates".

## The six widgets

| Widget | Families | Shows |
|---|---|---|
| Today | small, medium | Day cycle, anything waiting |
| Plants | small, medium, circular, inline | Due count, next plant's name |
| Trip | small, medium, rectangular, inline | Countdown, destination clock |
| Affirmation | small, medium, rectangular | One line from Sunnie |
| Daily puzzle | small, inline | The day's puzzle, played or not |
| Calm | small, circular, inline | A shortcut, and nothing about the user |

The accessory families are what make four of these Smart Stack and complication
surfaces (§10).

## Lock-screen sensitivity

A plant's name and a trip's title are the only user content these carry, and both
are withheld when `redactionReasons` contains `.privacy`. Counts, day cycles, and
affirmations stay — a number of plants tells a passer-by nothing, and an
affirmation is content the app wrote.

The Calm widget shows nothing about the user at all, which is why it is the right
one for a lock screen: starting a breathing practice should not require unlocking
a phone first.
