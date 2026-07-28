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
