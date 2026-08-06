# Collections

Built in Phase 8 (`Documentation/06_Delivery/IMPLEMENTATION_ROADMAP.md`).

```
Collections/
├── Screens/
│   └── CollectionsScreen.swift   S-21 — owned/locked, source of unlock, detail
└── UseCases/
    └── ManageCollection.swift    the unlock sweep, ownership, rhythm, keepsakes
```

The rules live in `SunnieShared/Domain/Collectibles.swift` and
`SunnieShared/Utilities/RewardUnlocking.swift`; the content in
`SunnieShared/ContentSchemas/BuiltInCollectionContent.swift`.

## Ownership is a grant, not a pack membership (ADR-024)

A reward is owned because there is an `SDRewardGrant` row with its content ID —
a table that has existed since schema V1. Phase 8 added no model for ownership
at all.

That is what makes §12 true by construction: uninstalling a pack cannot cascade
a grant away, because the grant does not reference the pack. An owned reward
nothing describes shows up as an orphan row that says so, rather than vanishing.

**There is no revoke path anywhere in this feature.** No `deleteGrant`, no
expiry, no decay. `RewardUnlockPlanner` only adds — a profile reporting a lower
level than before grants nothing new and takes nothing away.

## The sweep

`ManageCollection.sweep()` gathers what is true (level, event counts, places
visited, games finished, whether a memory exists), asks the planner what is
earned and not yet owned, and grants it.

It runs on launch and on every visit to the screen. That is safe because the
grant key derives from the reward and its unlock source and nothing else — not
the moment, not the device — so a repeated sweep is a no-op and a sweep after a
restore fills in whatever the restore is missing.

## Rhythm, not streaks

`RhythmSummary` counts *days on which something happened*. It never counts days
on which nothing did, so there is no run to break and a gap changes a number
rather than resetting one. `bestWeek` is kept because a personal best is a thing
that happened; there is deliberately no `isBelowBest`. The whole thing can be
turned off in Settings (§5).

If you are adding to this feature: there is no correct way to add a streak here.
