# Architecture Decision Records

This file begins with locked baseline decisions. Add new ADRs using the template below. Do not silently reverse a decision.

## ADR-001: Native Apple implementation

**Status:** Accepted  
**Decision:** Use Swift and SwiftUI for iPhone and Apple Watch.  
**Reason:** Best integration with HealthKit, Watch, SwiftData, CloudKit, notifications, audio, and Apple UX.  
**Rejected:** Web wrapper, React Native, Flutter, Capacitor.

## ADR-002: Modular monolith

**Status:** Accepted  
**Decision:** One Xcode project with feature-first organization and one shared local Swift package initially.  
**Reason:** Strong boundaries without premature package complexity.

## ADR-003: Local-first SwiftData

**Status:** Accepted  
**Decision:** SwiftData behind repositories, local write first, private iCloud sync for eligible data.  
**Reason:** Native persistence, offline operation, Apple ecosystem fit.

## ADR-004: No third-party dependencies by default

**Status:** Accepted  
**Decision:** Apple frameworks and internal code first.  
**Reason:** Private app, long-term maintainability, privacy, reduced supply-chain risk.

## ADR-005: 2D initial renderer

**Status:** Accepted  
**Decision:** Static/layered 2D art and SwiftUI motion for the complete first release.  
**Reason:** Preserve quality and scope while leaving renderer abstraction for future animation/3D.

## ADR-006: Creator-managed audio

**Status:** Accepted  
**Decision:** Source MIDI is creator-side. Rendered audio is preferred; runtime MIDI only for justified adaptive use.  
**Reason:** Vanessa should experience music without managing production files.

## ADR-007: No custom backend initially

**Status:** Accepted  
**Decision:** Use local data and Apple services.  
**Reason:** Android multiplayer, caretaker sharing, and LifeOS contracts are not yet defined.

## ADR-008: Stable branded day-cycle names

**Status:** Accepted  
**Decision:** Sunnie Days, Sunnie Afternoonies, Sunnie Nights.  
**Rejected:** Sunnie Mornings, Sunnie Evenings.

## ADR-009: No generative AI in initial release

**Status:** Accepted  
**Decision:** Plant, meal, game, and companion behavior remains deterministic/content-driven.  
**Reason:** No approved privacy, cost, or behavior specification exists.

## ADR template

```markdown
## ADR-XXX: Title

**Status:** Proposed | Accepted | Superseded | Rejected  
**Date:** YYYY-MM-DD

### Context
What problem or new constraint requires a decision?

### Decision
What will be done?

### Consequences
What becomes easier, harder, or deferred?

### Alternatives considered
What was rejected and why?

### Documents/tests affected
List required updates.
```

---

# Decisions added during implementation

The records above are the locked baseline from the document pack. Everything
below was decided while implementing Phases 0–2 and follows the template.

## ADR-010: Swift 5 language mode with complete concurrency checking

**Status:** Accepted
**Date:** 2026-07-28

### Context

The baseline documents specify Swift concurrency and `Sendable` but do not pin a
language mode. Xcode 16 defaults new projects to Swift 6 language mode, where
data-race violations are errors rather than warnings. The initial codebase mixes
`@MainActor` feature models, actors, and SwiftData model actors, and it was
authored without a compiler available to check it.

### Decision

Build every target in Swift 5 language mode with `SWIFT_STRICT_CONCURRENCY =
complete`. The shared package matches via `.swiftLanguageMode(.v5)`.

### Consequences

Concurrency problems surface as warnings and are visible without blocking the
build, which matters most in Phases 0–2 where the first compile has not happened
yet. The cost is that a genuine data race can ship as a warning. Moving to Swift 6
language mode is a deliberate task for Phase 11, not a drift.

### Alternatives considered

Swift 6 language mode from the start: correct in principle, rejected because
unverified code plus strict errors makes the first build a wall of failures that
obscures real problems.

### Documents/tests affected

`Config/Shared.xcconfig`, `Packages/SunnieShared/Package.swift`, and a Phase 11
entry in the roadmap.

## ADR-011: Idempotency in repositories, not in database constraints

**Status:** Accepted
**Date:** 2026-07-28

### Context

`FIRST_VERTICAL_SLICE.md` requires that a duplicated Watch action create exactly
one care event, and that rewards never be granted twice. The obvious mechanism is
`@Attribute(.unique)` on the action key. But CloudKit's private database does not
support unique constraints, and ADR-003 commits to private iCloud sync for
eligible data. Adopting `.unique` now would mean removing it later — a migration
plus a behaviour change on the exact code path that guarantees correctness.

### Decision

No `@Attribute(.unique)` anywhere in the schema. Uniqueness is enforced by
check-then-insert inside `@ModelActor` repositories, whose serialized executor
makes the check and the insert atomic with respect to each other. Relationships
use plain UUID foreign keys rather than SwiftData relationships, and every stored
property has a default value, both for the same CloudKit compatibility reason.

### Consequences

The guarantee behaves identically whether or not sync is enabled, and enabling
CloudKit later requires no schema change. In exchange, the invariant lives in code
rather than in the store, so it must be preserved by tests — `RepositoryTests`
covers concurrent and repeated saves for care events, progression events, reward
grants, and the Watch queue. A future repository that bypasses the actor would
silently break the guarantee.

### Alternatives considered

Unique constraints with a migration before enabling sync: rejected as scheduled
rework on the correctness-critical path. Application-level locking outside the
repositories: rejected as redundant with the actor model.

### Documents/tests affected

`Apps/iOS/Persistence/`, `RepositoryTests`, `VerticalSliceTests`, and
`DATA_MODEL.md` §11.

## ADR-012: Entitlements ship as inactive placeholders

**Status:** Accepted
**Date:** 2026-07-28

### Context

Phase 0 calls for entitlement placeholders. Active iCloud or HealthKit
entitlements require a real Apple Developer team and matching provisioning, so
wiring them into the build would make a fresh clone fail for anyone who has not
configured signing — including CI.

### Decision

The entitlements files exist and are complete, but `CODE_SIGN_ENTITLEMENTS` is
commented out in `Config/App-iOS.xcconfig`, and `ModelContainerFactory` defaults
to `cloudKit: false`. Each file documents the four steps to switch it on.

### Consequences

The project builds and tests on a clean machine with no account configured, which
is what makes CI possible. The app runs local-only until someone opts in — which
is the documented behaviour anyway, since writes go to local storage first and
synchronise later. The risk is that CloudKit sync stays untested for longer;
Phase 11 owns production CloudKit validation.

### Alternatives considered

Active entitlements with a placeholder team ID: rejected because it fails to build
rather than degrading gracefully.

### Documents/tests affected

`Config/App-iOS.xcconfig`, `Apps/iOS/Resources/SunnieDays.entitlements`,
`ModelContainerFactory`, and the Phase 11 checklist.

## ADR-013: Action keys ignore the source device

**Status:** Accepted
**Date:** 2026-07-28

### Context

A care action can reach storage by several routes: a tap on the phone, a tap on
the Watch, a queued Watch transfer redelivered later, or a notification action.
The slice requires that duplicates collapse to one care event. A key including the
device would distinguish a Watch tap from a phone tap even when they describe the
same watering.

### Decision

`ActionKeyFactory.plantCare` derives the key from the plant, the care type, and
the timestamp floored to a one-minute bucket — and from nothing else. The device
and the exact second are excluded. The Watch generates its key at the moment of
the tap and sends it with the payload, so redelivery resolves to the same key.

### Consequences

Two logs of the same care type on the same plant within one minute are treated as
one action regardless of origin, which is almost always what actually happened.
The trade-off is that a genuine double action inside sixty seconds is recorded
once; for plant care, where real intervals are days, this is the right side to err
on. A care type whose real cadence approaches one minute would need a different
granularity.

### Alternatives considered

A UUID generated at the tap: solves redelivery but not the phone-and-Watch double
entry. Including the device in the key: keeps both entries, which is the outcome
the slice explicitly forbids.

### Documents/tests affected

`ActionKeyFactory`, `ActionKeyFactoryTests`, `RepositoryTests`,
`VerticalSliceTests`, and `PLANT_CARE.md` §15.

## ADR-014: Reward plausibility guard is separate from idempotency

**Status:** Accepted
**Date:** 2026-07-28

### Context

`PLANT_CARE.md` §13 requires that repeated care within unrealistic intervals not
be farmable for rewards. It also requires that the user's record of what they
actually did never be refused — which rules out simply rejecting the event.

### Decision

Two independent gates in `ProgressionEngine`. Idempotency collapses the same
action; the plausibility guard withholds only the *reward* when the same care type
recurs sooner than `CareType.minimumPlausibleRepeat`. The care event is stored
either way. Backdated entries are treated as corrections and stay eligible.

### Consequences

Rewards stay meaningful without the app ever telling the user they are wrong about
their own plants. `ProgressionOutcome` carries `skippedAsImplausible` as an
ordinary result rather than an error, so no UI surfaces it as a failure. The
per-care-type intervals are a first estimate and should be revisited once there is
real usage.

### Alternatives considered

Rejecting the duplicate care event: rejected as refusing the user's own record.
No guard at all: rejected as leaving rewards trivially farmable.

### Documents/tests affected

`ProgressionEngine`, `CareScheduleCalculator.isPlausibleRepeat`,
`ProgressionEngineTests`, and `PLANT_CARE.md` §13.

## ADR-015: Additional folders inside the iPhone target

**Status:** Accepted
**Date:** 2026-07-28

### Context

`PROJECT_STRUCTURE_AND_CODING_STANDARDS.md` §1 lists `App`, `Features`,
`Integrations`, `Persistence`, and `Resources` under the iPhone target. Design
tokens and shared components belong to none of them, and neither do app-level
domain services such as the summary provider and the event bus, which wrap no
Apple framework and so are not integrations.

### Decision

Add two folders: `Apps/iOS/DesignSystem/` for tokens and shared components, and
`Apps/iOS/Services/` for app-level domain services. Both are specific, named
concerns — not the generic `Helpers` dumping ground the standards forbid.
Pure, platform-neutral services stay in the shared package; only those needing the
app's composition live here.

### Consequences

The design-token layer has one obvious home, which matters because it is the seam
the visual design pass edits. The structure document should be updated to match.

### Alternatives considered

Putting the design system in `Resources`: rejected, it is code. Putting services
in `Integrations`: rejected, that folder means Apple-framework adapters and
blurring it would weaken a useful boundary.

### Documents/tests affected

`PROJECT_STRUCTURE_AND_CODING_STANDARDS.md` §1.

## ADR-016: The shared package uses the conventional SwiftPM source layout

**Status:** Accepted
**Date:** 2026-07-28

### Context

The structure document shows `Packages/SunnieShared/Sources/{Domain, Protocols,
ContentSchemas, Payloads, Utilities}`. SwiftPM resolves a target's sources from
`Sources/<TargetName>/` by convention; the documented layout would need a custom
`path:`.

### Decision

Use `Sources/SunnieShared/{Domain, Protocols, ContentSchemas, Payloads,
Utilities, Services, Resources}`, keeping the documented subfolders one level
deeper. `Services/` was added for pure domain services — the theme engine, the
message service, the progression engine — which are neither protocols nor
utilities.

### Consequences

Standard tooling works without special configuration. The documented intent is
preserved; only the nesting differs.

### Alternatives considered

A custom `path:` matching the document exactly: rejected as fighting the tool for
no benefit.

### Documents/tests affected

`PROJECT_STRUCTURE_AND_CODING_STANDARDS.md` §1.

---

## ADR-017: Care-event corrections are a separate record, not a field

**Status:** Accepted · **Date:** 2026-08-04 · **Phase:** 4

### Context

The care log is append-only (PLANT_CARE.md §7), and the spec asks that editing a
care event "preserve an audit-friendly modification record or replacement
relationship when practical." Phase 4 needed to implement that.

The obvious design is a `supersededByEventID` field on `SDPlantCareEvent`. It is
one nullable column and reads naturally.

It also breaks something. `SDPlantCareEvent` has existed unchanged since schema
V1, and V1, V2, and V3 all share the same model classes rather than freezing a
copy per version — which is only sound while no existing model changes shape. The
note on `SunnieSchemaV2` says exactly this. Adding a column to the care event
would mean:

- `SunnieSchemaV1.models` would describe a shape V1 never had, so the schema
  declaration would be a lie about what shipped;
- `SchemaMigrationTests` could no longer construct a genuine V1 store to migrate,
  because writing one goes through the same shared class — so the test that
  guards a year of care history against a bad migration would quietly stop
  testing anything;
- the shared-class shortcut would have to be unwound for every model at once:
  V1's and V2's copied into frozen namespaces and the stages made custom.

That last piece of work is real and will eventually be necessary. It is not
justified by adding an edit history.

### Decision

Model the correction as its own record, `SDCareEventSupersession`, holding the
plant, the superseded event, the replacement event, and when the correction was
made. `SDPlantCareEvent` keeps the exact shape it had in V1, and the V2 → V3
migration stays lightweight and purely additive.

`PlantCareEventRepository.replace(eventID:with:)` saves the replacement through
the normal idempotent path and then records the link, once.
`supersededEventIDs(forPlantID:)` gives history screens the set to mark.

### Consequences

- Reading "was this event corrected?" is a second query rather than a column.
  Batched per plant, so a history screen costs one extra fetch, not one per row.
- Both records survive a correction. History shows the original marked as
  superseded rather than replacing it, which is the point of an append-only log.
- Correcting the same event twice with the same replacement is a no-op; the link
  is checked before it is written.
- If recording the link fails, the replacement is still stored. The cost is the
  "superseded" marker, not the correction.
- The shared-model shortcut survives one more schema version. The next change
  that alters an existing model's shape must do the namespace freeze properly,
  and this ADR is the standing note that the work is owed.

### Alternatives considered

**A field on the care event.** Rejected for the reasons above — it would have
made a migration test stop testing migrations, which is the kind of failure that
is silent until it matters.

**Do the namespace freeze now.** Rejected as scope: it touches every model and
every mapping, and nothing in Phase 4 needs it. Better done deliberately, when a
change actually requires it, than as a side effect of an edit history.

**Mutate the event in place.** Rejected outright. An append-only log that can be
rewritten is not an append-only log, and the spec asks for the opposite.

### Documents/tests affected

`PLANT_CARE.md` §7. `JungleFlowTests.correctionsAreAppendOnly` and
`correctionsAreIdempotent`. The note on `SunnieSchemaV3`.

---

## ADR-018: Generated noise uses a different audio session from the rest of the app

**Status:** Accepted · **Date:** 2026-08-04 · **Phase:** 3 (calm sounds), extending Phase 10

### Context

Sunnie Days added white, pink, and brown noise generators
(`NOISE_IMPLEMENTATION.md`). They are DSP, not assets: samples are computed as
they are needed, so this is the first calm sound that actually makes sound —
the recorded ambiences wait on Phase 10.

That created a conflict. `AudioService` configures `AVAudioSession` as
`.ambient`, deliberately: Sunnie's cues and ambience must never interrupt the
user's music, and must respect the ring/silent switch. Under `.ambient` audio
also stops when the screen locks.

For a sleep sound, every one of those is wrong in a different way. Someone
running brown noise to fall asleep has the phone on silent and the screen off.
A sleep sound that dies at lock is not a sleep sound, and one that stops because
the ringer switch is flipped is broken in a way the user will read as a bug.

There is one `AVAudioSession` per process. Whichever category is set last wins,
so this could not be left implicit.

### Decision

Two policies, stated and owned:

- **Sunnie's cues and ambience** keep `.ambient`. Unchanged.
- **Generated noise** uses `.playback` with `.mixWithOthers`, set by
  `NoiseEngine` when it starts, and the app declares `UIBackgroundModes = audio`.

`.mixWithOthers` is what keeps `.playback` from being a regression: noise plays
underneath other apps' audio rather than taking over, so it still never silences
the user's own music. Phone calls still interrupt it, and it resumes on
`.shouldResume`.

The calm-sound library treats the two players as mutually exclusive. Starting
either stops the other, and leaving the screen stops both — noise that kept
playing after navigating away, with no visible control, would leave the user
hunting for the off switch.

### Consequences

- Noise keeps playing with the screen locked and the ringer off, which is the
  entire point.
- Whichever player ran most recently has set the category. That is acceptable
  because they are mutually exclusive by construction, but it is a real
  invariant: a future feature that plays a cue *while* noise is running must
  decide the policy explicitly rather than inheriting whatever is current.
- `UIBackgroundModes = audio` is now declared. App Review expects a real
  background-audio feature behind it, and there is one.
- Noise ships with no assets and works offline forever. It is also in the
  fallback content pack, so it survives a failed content load — the one calm
  sound that cannot be missing.

### Alternatives considered

**Use `.playback` for everything.** Rejected: Sunnie's care confirmation chirp
interrupting a podcast, or sounding when the phone is on silent, is exactly the
behaviour the tone rules rule out.

**Keep noise on `.ambient`.** Rejected: it would stop at screen lock, which
makes the sleep timer meaningless and reads as a bug.

**Route noise through `AudioService`.** Rejected: the service is built around
resolving a content ID to a bundled file, and noise has no file. Merging them
would mean one type with two unrelated playback paths and two session policies,
which is harder to reason about than two types with one each.

### Documents/tests affected

`NOISE_IMPLEMENTATION.md` §9, §10. `AUDIO_MIDI_AND_SOUNDSCAPES.md`.
`NoiseDSPTests`. `Info.plist`.

---

## ADR-019: Trip status is derived, and lived in the destination's day

**Status:** Accepted · **Date:** 2026-08-04 · **Phase:** 5

### Context

A trip has a status — planning, upcoming, active, returning, completed,
archived (TRAVEL_AND_FLIGHT_ATTENDANT.md §3). The obvious implementation stores
it and changes it when the user says so, or when a background task notices a
date has passed.

Both go wrong. A stored status that the user maintains is wrong the moment they
forget; a stored status that a background task maintains is wrong whenever the
task did not run — which on iOS is often, and always on the launch that matters.
Either way the travel dashboard shows a trip as "upcoming" while the user is
standing in the destination.

There is a second question underneath it: *whose* day decides. A trip ending on
the 15th is over at midnight — but midnight where? Someone in Tokyo at 01:00 on
the 16th is home in nine hours; it is still the 15th in New York.

### Decision

**Status is computed, never stored**, by `TripStatusCalculator.status(for:now:calendar:)`
from the trip's dates and the current instant. The only persisted status is an
explicit archive, which is a user decision rather than a fact about time.

**Days are counted in the destination's zone** where the trip has one, falling
back to home. Comparison is by calendar day, not by instant, so a trip starting
at 06:00 is already active at 09:00 that morning, and one ending today is still
`returning` at 23:00 rather than becoming history at some unrelated midnight.

The last day is `returning` rather than `active` — that is the day the return
checklist matters — except on a single-day trip, where there is no separate
return day and calling it `returning` all day would be wrong.

### Consequences

- A status can never be stale. There is no background job to miss, no migration
  that has to fix up statuses, and no "refresh" the user has to know about.
- `statusOverride` exists but is honoured only for `.archived`. Any other stored
  value is ignored while dates exist, which is deliberate: it means a status set
  once and forgotten cannot outlive its truth.
- A past trip is always `completed` whatever its dates say. It was added for the
  record, and a past trip dated next year must not appear as upcoming.
- Every boundary is a pure function of stated inputs, so all of it is tested
  against arrays and fixed dates — including a trip spanning a daylight-saving
  change and two zones that switch on different dates.
- The absence window used for plant coverage runs to the *end* of the last day.
  Care due on the afternoon someone flies home is inside the absence.

### Alternatives considered

**Store the status and update it on launch.** Rejected: correct only if the app
is opened, which is exactly the assumption that fails.

**Compare instants rather than days.** Simpler, and wrong in a way users notice:
a trip would end at an arbitrary moment mid-morning rather than at the end of
its last day.

**Always use the home zone.** Rejected: it makes the app disagree with the
traveller about what day it is, which is the one thing a travel app must get
right.

### Documents/tests affected

`TRAVEL_AND_FLIGHT_ATTENDANT.md` §3, §8. `TravelTests` — the status, boundary,
and time-zone suites.

---

## ADR-020: Weather and calendar failures are silent

**Status:** Accepted · **Date:** 2026-08-04 · **Phase:** 5

### Context

Phase 5 added two optional integrations. WeatherKit needs an entitlement, a
network, and a coordinate. EventKit needs permission the user may never grant.
Both fail routinely and for reasons that are nobody's fault.

The house style elsewhere in this app is that a failure the user can act on gets
surfaced kindly, and one they cannot gets logged. These are firmly the second
kind — but they sit on a screen where an error message would be prominent.

### Decision

`WeatherProviding.summary` and every `CalendarProviding` read return **nil or an
empty array rather than throwing**, for offline, unauthorised, unentitled, and
missing-coordinate alike. The trip screen renders without a weather line or a
calendar link, and says nothing.

Two things are still surfaced, because the user *can* act on them: a denied
calendar permission is stated where the toggle is, with a note that everything
else works without it; and weather older than an hour is labelled as such,
because stale weather presented as current is worse than none.

Weather never modifies a record. A weather-driven packing suggestion carries its
reason and is added only on confirmation (TRAVEL_AND_FLIGHT_ATTENDANT.md §9).

A linked calendar event that has moved is **reported, never applied**. The trip
is the source of truth for Sunnie Days-specific content (§10), and silently
rewriting someone's dates because a calendar entry changed would be exactly the
unrequested edit the spec rules out. The screen offers the new dates; the user
taps.

### Consequences

- The trip screen has no weather error state and no calendar error state, which
  is fewer states to design and fewer to get wrong.
- Both entitlement and permission can be absent forever and the feature is whole.
  WeatherKit is declared inactive in the entitlements file alongside CloudKit and
  HealthKit, for the same reason those are.
- Weather is cached for fifteen minutes per rounded coordinate, so reopening a
  trip screen does not burn quota.
- A test cannot distinguish "offline" from "denied" through the protocol. That is
  intentional — nothing in the app should branch on the difference.

### Documents/tests affected

`TRAVEL_AND_FLIGHT_ATTENDANT.md` §9, §10, §16. `Info.plist`,
`SunnieDays.entitlements`.

---

## ADR-021: Dietary filtering is text matching, and the app says so

**Status:** Accepted · **Date:** 2026-08-04 · **Phase:** 6

### Context

Vanessa's locked rule is no eggs (MASTER_SOURCE_OF_TRUTH.md). Phase 6 had to
implement it, and the spec is unusually precise about the limit:

> Ingredient matching should account for obvious egg forms and user-defined
> exclusions. It must not claim allergen safety unless all ingredient data is
> verified and the product is intentionally built for that purpose.
> — MEALS_AND_PREP.md §2

This app has no ingredient database, no product data, and no knowledge of
manufacturing. It has the words someone typed into a recipe. Those two facts sit
uncomfortably close together: a filter that reliably catches eggs *feels* like a
guarantee, and a user who turns on "no eggs" and sees a filtered list will
reasonably infer one unless told otherwise.

The failure mode is not theoretical. Two strings written in earlier phases —
*"Planning and prep, always egg-free"* and *"Everything will be egg-free"* —
made exactly that claim, and were caught by a tone gate during this phase.

### Decision

**The filter is honest about being text matching, in the code and in the copy.**

- `DietaryFilter.Verdict.isClear` means "the ingredient text did not contain
  anything the rules look for". It is deliberately **not** called `isSafe` or
  `isEggFree`. There is no property anywhere with a name that could be quoted as
  a guarantee.
- Every user-facing string says what was matched, never what is safe. The
  Settings footer states outright: *"Sunnie matches the words you typed — it has
  no ingredient database and can't tell you anything is safe to eat."*
- Matched recipes are **set aside, not hidden**. They stay in the list behind a
  disclosure, labelled with the ingredients that matched. A filter that silently
  shrinks a list leaves the user hunting for a recipe they know they saved, and
  it also hides the filter's own fallibility.
- The term list covers the obvious forms — the word, its plurals, the named
  preparations (mayonnaise, hollandaise, meringue), and the derivatives that
  appear on labels (albumen, ovalbumin). It is not exhaustive and does not
  pretend to be.
- Whole-word matching plus an explicit allowance list, so "eggplant",
  "aubergine", and "egg noodles" are not caught. These have to be enumerated;
  there is no general rule that derives them.

The no-eggs rule uses the same code path as any user-defined exclusion. It has
no special case that could quietly diverge.

### Consequences

- The user gets a filter that works and a clear statement of what it is. Those
  are compatible; pretending the second away to make the first feel stronger is
  what would not be.
- New egg forms can be added to the term list without touching logic, and the
  tests name the categories they cover so a gap is visible.
- The `attention` tone marks a flagged ingredient in the recipe editor — amber,
  never red. It is information, not an alarm.
- A tone gate now checks user-facing strings for food-safety and allergen claims
  alongside the existing shame/urgency checks. It flags negations too, which is
  a false positive worth keeping over a missed real one.

### Alternatives considered

**Hide matched recipes entirely.** Rejected: it makes the filter look
infallible, and it makes recipes the user saved appear to have vanished.

**Ship an ingredient database.** Rejected as scope, and it would not close the
gap anyway — the app would still have no data on what is in a given branded
product, which is where allergen risk actually lives.

**Call the flag `isEggFree`.** Rejected. Names leak into UI, into logs, and into
how the next person reasons about the code. A name that overstates is the same
mistake as copy that overstates, one layer down.

### Documents/tests affected

`MEALS_AND_PREP.md` §2. `MealsTests` — the egg-rule suite, including the
eggplant and whole-word cases. Two corrected strings in `Localizable.strings`.

## ADR-022: Built-in game content is Swift, not JSON

**Status:** accepted (Phase 7)

### Context

Messages, themes, and the wellness pack ship as JSON in the shared package's
resources, decoded once at composition time with a Swift fallback if decoding
fails. Games arrived expecting the same treatment.

They are not the same kind of content. A message pack is a flat list of short
strings. A game pack is a tree: clues that point at option indices, deduction
constraints expressed as `(category, value)` pairs, answer keys that index into
option arrays. Every one of those indices is a place where a typo produces a
puzzle that tells a player their correct answer is wrong — silently, at runtime,
with nothing to catch it but someone playing that exact puzzle.

### Decision

The built-in game pack is defined in Swift (`BuiltInGameContent`), not JSON.

`ContentRegistry` still looks for `games.v1.json` first and falls back to the
built-in pack, so an *added* pack is a JSON file exactly as the content-pack
architecture describes. The change is only about where the initial set lives.

Two things follow:

- A game whose `kind` disagrees with its puzzle's payload is a type error, not a
  validation finding.
- `GamePackValidator` runs over the built-in pack in the tests like any other,
  including the check that *solves* every deduction puzzle.

### Consequences

- Adding a puzzle to the built-in set requires a build. Adding one via a pack
  does not, which is the case the pack architecture exists for.
- The pack is still a `GamePack` value with a real manifest, so nothing
  downstream knows or cares which way it arrived.
- `GamePack` round-trips through JSON in the tests, so the built-in set is proof
  that the on-disk format works rather than a way of avoiding it.

### Alternatives considered

**Author the JSON by hand.** Rejected: roughly fifteen hundred lines of nested
arrays where an off-by-one in an `answerIndex` is invisible until someone plays
that puzzle and is told they are wrong.

**Generate the JSON from Swift at build time.** Rejected as a build step that
buys nothing — the decoded value is identical either way, and the generator
would be one more thing that can be out of date.

### Documents/tests affected

`CONTENT_PACK_AND_EXPANSION_ARCHITECTURE.md`. `GameContentTests` — pack
validity, the JSON round trip, and the initial-set completeness check.

## ADR-023: A saved game is its move log, not its board

**Status:** accepted (Phase 7)

### Context

Save and resume is required for every game (GAMES_AND_FUTURE_MULTIPLAYER.md §2),
and the obvious implementation is to serialize the board: which values are in
which cells, which clues are open, which questions are answered.

That works until the board changes. A later build that adds a column, reorders
options, or splits a step has to migrate every saved board or discard it — and
discarding a half-finished puzzle is exactly the small betrayal this app should
not commit.

### Decision

A session stores its ordered `[GameMove]` and nothing about the board's layout.
The board is recomputed by replaying those moves through the engine on every
read.

The seed is stored alongside, so the puzzle a session was drawn from is fixed at
the moment it started rather than re-derived later.

### Consequences

- A build that changes how a board is laid out still resumes old sessions
  correctly, because it replays the same moves through the same rules.
- Moves from a mismatched save are ignored per-move rather than failing the
  whole session, so a partial mismatch loses a move rather than an afternoon.
- Replay is cheap: a session is tens of moves, and the engines are pure.
- The move log is also the groundwork §9 asks for. `GameMove` is `Codable`,
  carries its own ordinal, and contains no CloudKit or platform types, so two
  devices applying the same ordinals reach the same board — which is what
  asynchronous turn-based play needs and what a serialized board could not
  provide.
- One cost: a bug in an engine changes the meaning of every stored session
  retroactively. That is the same trade a ledger makes against a balance, and
  the engines are the most thoroughly tested part of the feature because of it.

### Alternatives considered

**Serialize the board.** Rejected for the migration problem above.

**Store both, board as a cache.** Rejected: two representations that can
disagree, and the one that gets trusted is whichever the next person happened
to read first.

### Documents/tests affected

`GAMES_AND_FUTURE_MULTIPLAYER.md` §2 and §9. `GamesTests` — replay determinism,
the reversed-array test, the foreign-move test, and the session round trip.
`GameFlowTests` — resume through a real store.

## ADR-024: Ownership is a grant, not membership in an installed pack

**Status:** accepted (Phase 8)

### Context

Collectibles are described by a content pack. The obvious model is that the
collection *is* the pack: iterate the installed rewards, mark the earned ones.

That model quietly makes ownership a function of what is installed. Uninstall a
destination pack and the stamp someone earned by actually going there stops
existing — not hidden, gone, with nothing left to restore it from.
PROGRESSION_COLLECTIONS_AND_SUNNIE_HOME.md §12 forbids exactly this, and the
forbidding is not incidental: a collection is a record of things that happened
to a person, and content management must not be able to edit their past.

### Decision

Ownership is an `SDRewardGrant` row, keyed by content ID and by a deterministic
key derived from what earned it. It has existed since schema V1 and Phase 8
added no model for it.

Consequences that follow directly:

- The collection is built by joining *definitions* against *grants*. A grant
  with no matching definition still appears, as an orphan row that says plainly
  that the pack describing it is not installed and that the item is still theirs.
- No code path deletes a grant. There is no revoke, no expiry, and no
  `deleteGrant` on the repository — the absence is the guarantee.
- `RewardUnlockPlanner` only ever *adds*. It takes what is true now and returns
  what is missing, so a corrupted profile that reports a lower level grants
  nothing new and takes nothing away.
- The unlock key derives from the reward and its unlock source, never from the
  moment or the device. Two devices noticing the same level being reached
  produce the same key, and the second collapses into the first.

### Consequences

- Renaming a reward's content ID orphans every grant already in a store. The
  five identifiers Phases 1 and 7 already grant are therefore kept exactly as
  written, in a section of the pack that says why.
- The collection screen must handle an item it cannot describe. It does, and the
  copy for that case is written rather than generic.

### Alternatives considered

**Store the pack version alongside the grant.** Rejected: it makes ownership
look conditional on a pack, which invites exactly the cascade this avoids.

**Hide orphaned grants.** Rejected. From the user's side that is
indistinguishable from having lost the thing.

### Documents/tests affected

`PROGRESSION_COLLECTIONS_AND_SUNNIE_HOME.md` §7, §12.
`CollectionsTests.ownershipOutlivesTheContentPack`,
`CollectionsTests.nothingIsEverRevoked`,
`CollectionFlowTests.loweringALevelRevokesNothing`.

## ADR-025: The home has named slots, not freeform placement

**Status:** accepted (Phase 8)

### Context

§8 says the initial release "should use constrained placement rather than a full
freeform physics editor". That reads as a scope decision. It is also an
accessibility one, and the accessibility half is the reason it should stay true
after the scope argument stops applying.

A drag-and-drop scene needs a second, parallel interaction path for VoiceOver,
Switch Control, and anyone who cannot hold a precise drag — and that second path
is invariably built later, tested less, and drifts. The result is an app where
the accessible way to decorate is worse than the real way.

### Decision

Every placement is a `DecorSlot` — a named, content-defined position that holds
exactly one thing and declares which categories it accepts. Choosing what goes
in one is a list and a tap.

There is no drag path. Not "a drag path plus an accessible alternative" — one
path, which happens to work with every input method because a list does.

### Consequences

- The scene stays composed whatever is in it, because the composition is
  authored rather than emergent.
- A destination pack can add a shelf as content, with no code change.
- `CollectionPackValidator` can prove that every placeable reward has a slot
  that accepts it. A freeform scene has no equivalent check, because "somewhere
  on the canvas" is always true and never useful.
- The scene will look less like a dollhouse than a freeform editor would. That
  is the cost, and it is worth it.

### Alternatives considered

**Freeform drag with an accessible alternative.** Rejected for the reasons
above: two paths, one of which is a second-class citizen by construction.

**Freeform drag with snapping.** Rejected — it is the same two-path problem with
extra geometry, and the snap targets are just slots that the user cannot see.

### Documents/tests affected

`PROGRESSION_COLLECTIONS_AND_SUNNIE_HOME.md` §8. `SCREEN_SPECIFICATIONS.md`
S-22. `CollectionsTests.placementRulesRefuseSpecifically`,
`CollectionContentTests.everythingPlaceableHasASlot`,
`CollectionFlowTests.slotsHoldOneThing`.

## ADR-026: Health is asked for one type at a time, and read denial is never claimed

**Status:** accepted (Phase 9)

### Context

HEALTH_WATCH_WIDGETS_AND_INTENTS.md §1 says request the minimum necessary and
§2 ends with "do not request every type merely because it exists". The path of
least resistance is one "Enable Health" switch that asks for everything the app
might ever want, which is the opposite of both.

There is also an asymmetry in HealthKit that shapes the whole design: **the
system does not report read denial.** A denied read returns no data, exactly
like a day with no data. There is no API that distinguishes them, by design —
telling an app that a read was refused would itself leak that the user has that
data type.

### Decision

Two rules, both structural rather than conventional.

**Per type.** `HealthDataType` is granular and `requestAuthorization(read:write:)`
passes exactly the sets it is given. There is no call anywhere that asks for
everything, and Settings shows one switch per type with its own reason beside it.
The app writes only two types — mindful sessions and dietary water — and both
only after a completed user action.

**Read authorization is not exposed.** `HealthProviding.authorization(for:)`
returns `.notDetermined` for every read-only type, and the doc comment says why.
No screen can claim "denied" for a read, because nothing can know it. The
Settings footer says plainly that a type showing nothing may mean a declined
read, and that the real switch is in the Health app.

The app's own preference records *what it asked for*, not what it was granted.
Those are different facts and only one of them is knowable.

### Consequences

- A user can have mindful minutes written without handing over their heart rate.
- Turning a switch off changes only the app's preference. The copy says so
  rather than implying the app can hand a permission back, because it cannot.
- Nothing re-prompts. iOS will not show the sheet twice, so a button that
  appeared to ask again would silently do nothing — which is worse than no
  button (§12).
- Hydration is stored locally *and* mirrored to Health rather than living in
  Health, so the feature works for someone who declined (§1). A catch-up pass
  mirrors earlier entries if the permission arrives later, keyed so nothing is
  written twice.

### Alternatives considered

**One Health switch.** Rejected: it is precisely what §2's last line forbids.

**Track granted-vs-requested per type.** Rejected because the granted set is
unknowable for reads. A field claiming to hold it would be wrong, and every
screen reading that field would be wrong with it.

### Documents/tests affected

`HEALTH_WATCH_WIDGETS_AND_INTENTS.md` §1–§4, §12.
`HealthAndIntegrationTests` — the absence-is-not-zero, in-progress-caveat, and
unavailable-service suites. `IntegrationFlowTests` — hydration without Health,
and the mindful-write guards.

## ADR-027: Widgets read a snapshot file, never the store

**Status:** accepted (Phase 9)

### Context

A widget extension needs the app's data. The obvious approach is to open the
same SwiftData store from the extension through a shared App Group container.

Three problems with that, in increasing order of seriousness. An extension has a
small memory budget and a large `ModelContainer` is a real fraction of it. A
migration could run in the extension, at an arbitrary moment, with no UI and no
way to report failure. And a widget that crashes is a blank rectangle on
someone's home screen that gives no indication anything is wrong.

There is also a privacy question the store cannot answer: §8 requires widgets to
show only privacy-appropriate content, and a widget with the whole store in
scope has every journal entry and every check-in in reach.

### Decision

The app builds a `WidgetSnapshot` — a small, already-filtered `Codable` value —
and writes it as JSON to the App Group container. The extension reads that file
and nothing else. It never opens SwiftData, never runs a migration, and never
resolves a content pack.

`WidgetSnapshotPublisher` is the single place that decides what a widget may
show, which makes the §8 privacy rule one reviewable function rather than a
property of six timeline providers.

### Consequences

- What is in a widget is auditable by reading one file. The test asserts a
  plant's private note does not appear in the encoded snapshot.
- The App Group is an entitlement, and entitlements are inactive by default
  (ADR-012). With none configured `WidgetSnapshotStore` resolves no container,
  the write is a no-op, and every widget shows an "open Sunnie Days" state —
  degraded honestly rather than blank.
- A snapshot written by a newer app is ignored rather than half-read, because
  the two halves are not always updated in the same instant.
- The snapshot is one refresh stale between publishes. Acceptable: the app
  republishes on meaningful change, and a plant count that is a minute old has
  never hurt anyone.

### Alternatives considered

**Open the store from the extension.** Rejected for the migration and memory
risks, and because it puts everything in scope.

**`UserDefaults` in the App Group.** Rejected: the snapshot is a document,
defaults is not a database, and a corrupt defaults plist is a far worse failure
than a file that can simply be ignored.

### Documents/tests affected

`HEALTH_WATCH_WIDGETS_AND_INTENTS.md` §8, §10.
`HealthAndIntegrationTests` — the store round trip, the no-container case, and
the newer-payload case. `IntegrationFlowTests` — the snapshot privacy assertion.

## ADR-028: Every Watch action travels in one envelope

**Status:** accepted (Phase 9)

### Context

Phase 2 shipped one Watch action — plant care — as a bare `WatchCareActionPayload`
under its own message key. Phase 9 adds four more: check-ins, finished practices,
ticked checklist items, and hydration.

Five keys and five decode attempts per delivery would mean the phone cannot tell
"a payload I do not recognise" from "a payload that failed to decode", and a
Watch running a newer build than the phone produces exactly the first case.

### Decision

Everything the wrist sends is wrapped in a `WatchActionEnvelope` carrying the
five fields §7 requires — stable action ID, kind, timestamp, source device, and
payload version — with the body as opaque `Data`.

The phone routes on `kind` without decoding the body. An unknown kind is
recognisably unknown and is logged rather than treated as corruption.

The Phase 2 key is still handled on arrival. A Watch on the older build may have
a queued transfer that arrives after the phone updated, and that watering must
still be recorded.

### Consequences

- Every action's key is generated on the wrist at the moment of the tap and
  travels with it, which is what makes §7's "phone processing is idempotent"
  true: a redelivered transfer resolves to the record that already exists.
- The wrist's own key must survive the trip. `logWater` and the check-in use
  case both accept an explicit key and source for this reason — regenerating one
  from the phone's clock would produce a different key and a duplicate entry.
- The envelope's coder is declared once in the shared package, because it is
  encoded on one device and decoded on another, and two independently configured
  coders that disagree about dates would produce transfers that arrive and cannot
  be read.

### Alternatives considered

**A key per action kind.** Rejected for the reason above.

**One `enum` payload with associated values.** Rejected: it would fail to decode
entirely when a newer build adds a case, which is precisely the case the
envelope exists to survive.

### Documents/tests affected

`HEALTH_WATCH_WIDGETS_AND_INTENTS.md` §6, §7, §11.
`HealthAndIntegrationTests` — the envelope round trip, the unknown-kind case, and
the lenient context decode. `IntegrationFlowTests` — idempotency for all four
new actions through a real store.

## ADR-029: Ambience is synthesised, and rendered audio stays the preferred path

**Status:** Accepted
**Date:** Phase 10

### Context

`AUDIO_MIDI_AND_SOUNDSCAPES.md` §3 is unambiguous about which runtime strategy
wins: rendered audio is preferred, runtime MIDI is optional and only for adaptive
arrangement, and "do not use runtime MIDI merely because source music was composed
as MIDI."

But the app had been shipping a sound library that listed eleven ambiences and
played three of them. The eight recorded ones had definitions, localized names,
and cue ids since Phase 3, and no files — the screen said so, in as kind a way as
possible, and that did not stop it being a list of things that do nothing. Rendered
assets need a creator with a microphone and time, and Phase 10's job was to finish
the audio layer, not to wait on one.

### Decision

Ambience and meditation bells are **synthesised at runtime** from a tuning table
in `SunnieShared/Audio/ProceduralAmbience.swift`: a coloured noise bed, one slow
amplitude swell, and sparse decaying events (droplets, calls, chirps, clinks).
Bells are inharmonic partial stacks with per-partial decay.

This does **not** displace §3's preference. Rendered audio remains the preferred
form and the manifest is where the switch happens: a rendered ambience taking the
same content id, with a `runtimeAsset`, replaces the synthesised one with no code
change and no caller edit. The seven music tracks are already declared against the
filenames the creator will render — the entry, the contexts, and the level are
written, and dropping the file into the bundle is the whole remaining step.

Runtime MIDI stays unused, and the manifest validator rejects a track that claims
it. That is not a rule against MIDI; it is a rule against arriving at MIDI by
accident, which is exactly what §3 warns about.

### Reason

- **It works on a clean clone.** Nothing to license, nothing to download, nothing
  that can ship out of sync with a manifest entry.
- **It is verifiable offline.** The whole chain is `Foundation` arithmetic, so
  level, headroom, spectral balance, and determinism are unit tests rather than a
  listening session — the same argument `NoiseDSP.swift` already makes, and the
  same reason there is no Swift toolchain in this environment yet the DSP is
  still checked.
- **It never repeats.** A four-minute loop is recognisable by the third pass; an
  event stream with exponential spacing has no period to notice.
- **It costs nothing in the bundle.** Eight ambiences at file quality would be
  tens of megabytes.

### Consequences

- These are impressions, not recordings, and the code says so. `cafeQuiet` is a
  murmur and some crockery, not a room with conversations in it — synthesised
  speech babble would be uncanny, and the alternative is honest abstraction.
- Every recipe constant is taste, so they live in one table rather than scattered
  through the synth. Retuning is editing a literal.
- The render block must not allocate or lock, which shapes the whole design:
  event voices are a fixed-size array sized in `init`, the oscillators are
  two-multiply recurrences rather than `sin` calls, and an event that finds no
  free voice is dropped rather than stealing one mid-decay.
- `CalmSoundCategory.isGenerated` now means "played by the *noise* engine",
  not "is synthesised". Almost everything is synthesised; the distinction that
  still matters is which engine and which session policy (ADR-018).

### Alternatives considered

**Ship silence until the creator delivers.** Rejected: it leaves a list of dead
rows on a screen whose whole purpose is to make a sound, and it makes the
crossfade, session, and interruption work untestable end to end.

**Licence a sample pack.** Rejected: a third-party dependency needs its own ADR
and explicit approval (CLAUDE.md), it costs bundle size, and it puts a licence
obligation on a private app for one person.

**Runtime MIDI with a soft synth.** Rejected on §3's own terms. Nothing here
needs adaptive arrangement or tempo change, and choosing MIDI because the beds
are generated is the substitution §3 explicitly warns against.

### Documents/tests affected

`AUDIO_MIDI_AND_SOUNDSCAPES.md` §2, §3, §4, §8, §10.
`CreatorAudioSource/README.md` — the workflow, and what replacing a synthesised
track with a rendered one takes.
`AudioTests` — determinism, channel decorrelation, headroom, bell decay, spectral
sanity per voice, and manifest validation.

## ADR-030: One owner for the audio session, and it is a table

**Status:** Accepted
**Date:** Phase 10

### Context

§7 asks for exactly this — "centralize category changes in one service rather
than feature code" — and by Phase 9 the app had three places setting a category:
`AudioService` (`.ambient`), `NoiseEngine` (`.playback` with `.mixWithOthers`,
per ADR-018), and `VoiceNoteRecorder` (`.playAndRecord`, then `.ambient` again
on stop). Each was individually correct. Together they were a race: whichever
feature touched audio last decided whether the ring/silent switch still worked.

### Decision

`AudioSessionPolicy.plan(for:backgroundPlaybackEnabled:)` is the only thing that
decides a category, and it returns plain values — `AudioSessionCategory`,
`AudioSessionMode`, `AudioSessionOptions` — rather than AVFAudio types. Every
engine translates that plan into AVFAudio and does nothing else.

The table:

| Use case | Category | Options | Survives lock |
|---|---|---|---|
| cue, ambience, music | ambient | — | no |
| generated noise | playback | mixWithOthers | yes |
| meditation | playback *if the user enabled background playback*, else ambient | mixWithOthers | if enabled |
| voice note | playAndRecord (spoken audio) | duckOthers | no |

### Reason

Plain values mean the table is a thing that can be asserted on. The category is
the setting most likely to be wrong in a way nobody notices until someone is on a
plane with headphones in, and the only way to catch that without a device is to
make the decision a value and test the value.

`.duckOthers` appears on exactly one row, and it is the recording one. Quietening
someone's own music so Sunnie can be heard over it is a small hostility and no cue
here earns it — but a voice note with a playlist bleeding into it is a recording
that cannot be used, so the microphone gets the exception.

Meditation is the only conditional row. A practice with a timer should survive the
screen locking, but making that unconditional means the ring switch silently stops
working for someone who never asked — which is why it follows an explicit setting
that defaults to off.

### Consequences

- ADR-018 is unchanged and now lives in the table rather than in one engine's
  comments.
- `requiresReconfiguration(from:to:)` exists so an engine holds the last plan
  rather than an `isConfigured` flag: setting the category is not free and can
  glitch playback, so it happens only when the plan actually differs.
- A new use case is a new row, not a new `setCategory` call site.

### Alternatives considered

**Return `AVAudioSession.Category` directly.** Rejected: it drags AVFAudio into
the shared package, which is what stops the Watch and the tests from compiling it.

**One session for everything.** Rejected: a sleep sound and a decorative bed
genuinely need different answers about the ring switch, and collapsing them would
break one of the two.

### Documents/tests affected

`AUDIO_MIDI_AND_SOUNDSCAPES.md` §7.
`AudioTests` — the full table, and the reconfiguration check.

## ADR-031: Interruption handling is a state machine, not a notification handler

**Status:** Accepted
**Date:** Phase 10

### Context

§12's test list is: phone call, Siri, Bluetooth disconnect, headphone
insertion and removal, route change, background and foreground, simultaneous
timer and audio, loop gap, volume persistence, and other audio playing.

Written as branches inside `NotificationCenter` observers, none of that is
reachable from a test. It needs a device, two pairs of headphones, and someone
willing to ring you at the right moment — which in practice means it is verified
once, by hand, and then never again.

### Decision

`AudioInterruptionMachine` in `SunnieShared` holds the playback state and maps an
`AudioEvent` to an `AudioAction`. The app target's observers do one thing each:
turn an `AVAudioSession` notification into an event. No decisions live in a
handler.

The rules it encodes:

- Pause on interruption; resume **only** when the system's `shouldResume` says so.
- A private route disappearing stops playback — headphones out means the sound
  stops, not that it moves to the speaker.
- A route appearing starts nothing. Plugging headphones in is not consent.
- Backgrounding pauses only what was never meant to survive it; a sleep sound or
  a running practice keeps going.
- Media services resetting invalidates every player, so the only correct response
  is to rebuild — and to resume only what was genuinely sounding.
- Other audio starting ducks *ours*, never theirs.

### Reason

Every one of §12's scenarios becomes a unit test, including the sequences that
matter most and are hardest to stage by hand: a phone call that arrives while
backgrounded and ends after returning, headphones pulled during an interruption,
a reset in the middle of a fade. The part that genuinely needs a device — that
iOS posts the notification we think it does — is reduced to a handful of lines
per observer.

### Consequences

- The machine is a `struct` with a `mutating` handler rather than a static
  function, because half the rules depend on *how* playback stopped. "Resume"
  means different things after a phone call and after a trip to the home screen,
  and an implementation that cannot tell them apart resumes at the wrong times in
  both directions.
- `isInterrupted` and `isPausedForBackground` are separate flags for exactly that
  reason, and both can be set at once.
- Device verification is still owed for the notification mapping itself; it is
  recorded in `Apps/iOS/README-Audio.md` alongside the Watch's own device plan.

### Alternatives considered

**Handle each notification where the player lives.** Rejected — that is the
status quo this replaces, and it is why the rules had never been tested.

**A general-purpose reactive state library.** Rejected: a third-party dependency
needs its own ADR, and the whole machine is sixty lines.

### Documents/tests affected

`AUDIO_MIDI_AND_SOUNDSCAPES.md` §6, §12.
`AudioTests` — every event, and the multi-event sequences.

## ADR-032: The shared package builds off Apple, and that is a feature

**Status:** Accepted
**Date:** Post-Phase-10 audit

### Context

`SunnieShared` ships only to iOS and watchOS, so nothing *required* it to compile
anywhere else. It had two Apple-only touch points — `import os` in `SunnieLog`
and `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` in
`WidgetSnapshotStore` — and both were unguarded.

The consequence was not a bug on Apple. It was that a third of the codebase could
not be compiled by anyone without a Mac, which for this project meant it had
never been compiled at all. Sixty-four thousand lines were written, reviewed
statically, and shipped to a review packet without a type checker ever seeing
them.

### Decision

Both touch points are guarded — `#if canImport(os)` and `#if canImport(Darwin)`
— so the package builds and tests on Linux with an ordinary Swift toolchain. Off
Apple, logging is a no-op and the App Group container is nil, which is the same
path the entitlement-less build already takes (ADR-012).

CI gains a Linux job that builds and tests the package on every push, alongside
the existing macOS one. Linux proves the logic; macOS proves the guards did not
change behaviour on the platform that ships.

### Reason

The first Linux compile found three defects that months of static analysis had
not:

1. **`ColorValue` encoded as `{"hex": …}`** while every content pack wrote
   `"#FFF8ED"`. `themes.v1.json` therefore failed to decode, `ContentRegistry`
   silently substituted the one-theme `FallbackContent`, and every phase variant,
   outfit, and alternate theme vanished at runtime. Nothing crashed and nothing
   logged; it simply looked like the theme feature did not work.
2. **`CoveragePlanner` projected *past* tasks already overdue** when an absence
   began, so a monthly watering two days late was reported as needing nothing
   across a one-week trip — the one plant that actually needed water on day one.
   The code's own comment described the correct behaviour; the loop did the
   opposite.
3. **`NicknameEligibility.shouldUseNickname` took `some RandomSource`** where
   every caller stores `any RandomSource`, making it uncallable by the only code
   that called it.

None of those is exotic. All three are the kind of thing a compiler finds in
seconds and a careful reader does not find at all. That is the argument.

### Consequences

- Anyone can run a third of the test suite on any machine:
  `cd Packages/SunnieShared && swift test`.
- New code in the shared package must stay platform-neutral. Reaching for an
  Apple-only API there now breaks CI rather than passing unnoticed — which is the
  point, and is why the guard is not merely defensive.
- The app, Watch, and widget targets are unaffected and remain uncompiled. This
  ADR makes no claim about them.
- `SunnieLog` does nothing off Apple rather than printing to stdout. Printing
  would be worse: the redaction rules exist so personal content never reaches a
  log, and a test run that dumped journal text to a terminal would violate the
  spirit of that while satisfying its letter.

### Alternatives considered

**Leave it Apple-only and wait for a Mac.** Rejected on evidence: that was the
status quo, and it produced three real defects surviving to a review packet.

**Extract the pure logic into a second, platform-free package.** Rejected as
churn. Two guards achieve the same thing without splitting a package that is
already coherent, and a split would need its own migration and ADR.

**Print logs off Apple instead of no-op.** Rejected — see consequences above.

### Documents/tests affected

`README.md`, `START_HERE.md`, `REVIEW_PACKET.md`, `Documentation/BUILD_AND_VERIFY.md`
— all previously said the code had never been compiled, which is now true only of
the app targets.
`.github/workflows/ci.yml` — the Linux job.
`ContentValidationTests.ShippedContentLoadsTests` — asserts the shipped packs
load rather than falling back, which is the check that would have caught the
`ColorValue` defect.
`JungleSupportTests` — overdue coverage, including the no-double-count case.

## ADR-033: There is no erase-everything button, and no deletion is silent

**Status:** Accepted
**Date:** Post-audit, at the owner's direction

### Context

`PRIVACY_SECURITY_AND_DATA_LIFECYCLE.md` §7 and
`ONBOARDING_SETTINGS_AND_PERMISSIONS.md` both listed "delete all app data" as a
required control, and neither was ever built. An independent audit flagged the
gap as a release blocker, reasoning — reasonably, on the face of it — that an app
holding journal, wellness, travel, plant, photo, and voice data owes its owner a
way to erase all of it.

The owner's answer was the opposite: **do not build it.**

### Decision

There is no "delete all app data" control, and there must not be one. Deleting
the app from the device removes everything the app owns; that is the
erase-everything path, and it belongs to the operating system.

Separately and equally binding: **no deletion is silent.** Two consequences —

1. A delete that fails must say so. A screen that looks successful while the
   record survives is a lie the user acts on.
2. Nothing is destroyed on the user's behalf without their knowledge.

### Reason

The specification treated erase-all as a privacy feature. For this app it is
closer to a hazard.

Sunnie Days is a companion built around wellbeing, mood, and a journal, for one
person, on a bad-day-tolerant premise that runs through every other decision
here: nothing earned is ever taken away, no streak is ever punished, no message
is ever disappointed. A single control that destroys years of journal entries,
plant history, and travel memories is exactly the wrong thing to put one
confirmation dialog away from someone having a bad night. The feature's
worst-case user is the same person as its intended user.

The privacy argument it was meant to serve is already answered without it.
Deleting the app removes the store, the media directory, and everything in the
App Group. That is a complete erase, it is a familiar gesture, it lives outside
the app's own emotional context, and it cannot be reached by tapping through a
settings screen at 2am.

The "no silent deletes" half comes from the same place. An app that quietly
removes things — or quietly fails to — is not trustworthy with a journal,
whichever direction the error runs.

### Consequences

- Per-record and per-category deletion stay. Those are deliberate, scoped, and
  reversible in the ways that matter.
- The audit's release blocker RB-4 is **rejected as a product decision**, not
  deferred. It should not reappear in a later review as an open item.
- The ten-plus `try? await …delete(…)` call sites in feature screens now violate
  a locked decision rather than merely being untidy. They must surface failure.
  Tracked as open work; they cannot be verified until the app target compiles.
- Journal deletion keeps its thirty-day restore window, but the app must **say
  so** — the current screens do not, which is its own quiet form of the same
  problem.

### Alternatives considered

**Build it with a strong confirmation.** Rejected. Confirmation dialogs are
friction, not protection, and friction is what someone in a bad moment pushes
through. The failure mode is not accidental taps.

**Build it, but require typing a phrase.** Rejected for the same reason, plus it
imports a hostile pattern from services that use it to discourage cancellation.

**Leave the promise in the docs and never build it.** Rejected outright — a
specification that promises a control the product has decided against is worse
than either honest answer.

### Documents/tests affected

`PRIVACY_SECURITY_AND_DATA_LIFECYCLE.md` §7 — promise removed, rule stated.
`ONBOARDING_SETTINGS_AND_PERMISSIONS.md` — same.
`Documentation/Claude_Audit_Package/CLAUDE_RESPONSE.md` — RB-4 re-marked as
rejected on product grounds rather than deferred.
