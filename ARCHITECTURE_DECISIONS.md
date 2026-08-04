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
