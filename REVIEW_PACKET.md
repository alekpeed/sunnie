# Third-party code review — orientation

Sunnie Days is a private, single-user iPhone and Apple Watch app: plant care,
wellness, travel, meals, games, and a collection, all fronted by a cartoon sloth.
Swift and SwiftUI, no third-party dependencies, offline-first.

This document is for a reviewer who has not seen the repository before. It says
what the code is, what state it is genuinely in, what has and has not been
verified, and where the review time is best spent.

---

## 1. Read this before anything else

**The iPhone app, widget, and Watch target now compile in CI.**

**Verification status, precisely.**

- **The shared package (`SunnieShared`) compiles and its 460 tests pass**, on
  Linux with Swift 6.1.2. That is roughly a third of the codebase — all the
  domain logic, content schemas, and pure algorithms — and it is genuinely
  verified, not argued for.
- **The iPhone app and widget compile on macOS CI.** The app runs on an iPhone
  simulator, with 223 app tests and 7 UI tests passing.
- **The Watch app compiles for the watchOS Simulator.** Its manual CI job
  downloads the watchOS SDK on demand; paired-device behavior cannot be proven
  in CI.

Getting the shared package building found three real defects that no amount of
static checking had caught: a `ColorValue` that encoded as an object while every
content pack wrote a bare string (so the whole theme pack silently fell back to a
one-theme stub), travel coverage that dropped tasks already overdue when a trip
began, and a nickname helper that was uncallable by its only callers.

That is not a caveat buried in a footnote — it is the single most important fact
about the codebase, and it should shape how the review is scoped. Concretely:

- Expect compiler work in the Watch target; the iPhone and widget targets are
  already compiler-verified.
- Test counts are executed results: 460 shared-package tests, 223 app tests, and
  7 UI tests pass in CI.
- Anything that depends on runtime behaviour — SwiftData migration actually
  running, SwiftUI actually laying out, WatchConnectivity actually delivering — is
  unproven.

The most valuable next build is the manual Watch workflow. After that, review
time is best spent on migration and physical-device behavior that simulator CI
cannot prove.

`Documentation/BUILD_AND_VERIFY.md` has the recommended bring-up order —
shared package first, then the iPhone target, then the Watch and widget
extensions — chosen so a failure early does not block understanding the rest.

## 2. What *has* been verified, and how

Before native CI, verification was static and offline. Those checks remain useful
and narrow; native CI now adds compiler, simulator, repository, integration, and
UI-test evidence for the iPhone app and widget.

| Check | Covers | Does **not** cover |
|---|---|---|
| Brace/paren/bracket balance over all 222 Swift files | gross structural damage | anything the type checker would catch |
| `Localizable.strings` parse, duplicate keys, and key coverage | a `Text("key")` with no matching entry | whether the copy reads well in context |
| Tone gate over strings, `defaultValue:` literals, and authored content | shaming/urgency phrasing, forbidden day-cycle names, medical and allergen claims | tone in dynamically composed strings |
| Duplicate top-level type detection | two `Season` enums in different files | ambiguity within a file |
| Protocol-conformance sweep | a conformer missing a requirement | signature mismatches |
| `project.pbxproj` structural audit | dangling refs, unpaired sections, duplicate ids | whether Xcode accepts the file |
| Independent Python re-implementations | the Jungle Logic solver's uniqueness and clue minimality; the collection placement rules; the whole procedural-audio DSP chain | the Swift versions actually matching the Python ones |

The last row is the strongest of these and the one most worth spot-checking: for
Phase 10 the entire audio signal chain was ported to Python and measured, which
is how the calibration headroom was set and how a real defect (peaks drifting to
0.89 against a 0.80 ceiling on unmeasured seeds) was found and fixed. The port is
not in the repository — only its conclusions are, in
`AmbienceCalibration.peakSafetyFactor`. **A reviewer should treat those numbers as
claims to re-derive, not as measurements to trust.**

`Scripts/validate-content.sh` runs the content validator and does pass. It was
also confirmed to fail on deliberately introduced violations, so it is not
vacuous.

`.github/workflows/ci.yml` is the canonical build: shared-package tests, content
validation, syntax checks, and an iPhone simulator build and test run on every
push. Its Watch job is deliberately manual because it must first download the
watchOS SDK.

## 3. What the code is

A modular monolith. One Xcode project, one local Swift package, five build
targets.

```
Packages/SunnieShared/   platform-neutral domain, content schemas, pure logic
Apps/iOS/                the iPhone app — features, persistence, integrations
Apps/Watch/              the Watch companion
Apps/Widgets/            the widget extension
Tests/                   app-level tests (SwiftData in memory) and UI tests
Documentation/           the product definition this was built from
CreatorAudioSource/      creator-side audio workflow; ships nothing
Tools/, Scripts/         validators that run without a build
```

### Line counts by area

| Area | Files | Lines |
|---|---:|---:|
| `SunnieShared / Domain` | 28 | 5,970 |
| `SunnieShared / ContentSchemas` | 12 | 4,173 |
| `SunnieShared / Utilities` | 14 | 2,896 |
| `SunnieShared / Audio` | 4 | 1,329 |
| `SunnieShared / Games` | 5 | 1,315 |
| `SunnieShared / Protocols` | 3 | 1,014 |
| `SunnieShared / Payloads` | 3 | 875 |
| `SunnieShared / Services` | 4 | 445 |
| `SunnieShared / tests` | 20 | 7,769 |
| `iOS / Features` | 52 | 19,093 |
| `iOS / Persistence` | 29 | 6,606 |
| `iOS / Integrations` | 9 | 2,819 |
| `iOS / App` | 5 | 1,031 |
| `iOS / Services` | 8 | 1,026 |
| `iOS / DesignSystem` | 6 | 941 |
| `iOS / AppIntents` | 1 | 344 |
| `Watch` | 5 | 771 |
| `Widgets` | 2 | 452 |
| `App tests` | 11 | 4,774 |
| `UI tests` | 1 | 128 |
| **Total** | **222** | **63,771** |

### The architectural rule that matters most

Anything that can be got wrong quietly is pushed into a **pure value type in the
shared package**, so it can be tested with no store, no screen, no device, and no
network. The app target is left with adapters that translate between those values
and Apple's frameworks, and are supposed to contain no decisions at all.

That pattern repeats across every feature — care scheduling, reminder cadence,
trip status, reward unlocking, game grading, health phrasing, audio session
policy, interruption handling. If the reviewer only checks one property, checking
that the adapters really are decision-free is the highest-leverage one, because
every place a decision leaked back into an adapter is a place with no test
covering it.

### Decisions are written down

`ARCHITECTURE_DECISIONS.md` holds 31 ADRs. Each has context, decision, reason,
consequences, alternatives rejected, and the documents and tests it affects. When
a piece of code looks wrong, the ADR is usually where the argument for it is —
and disagreeing with the argument is a legitimate and useful review finding.

The ones most likely to provoke disagreement:

- **ADR-011** — no `@Attribute(.unique)` and no SwiftData relationships anywhere,
  because both are CloudKit-incompatible. Idempotency is instead check-then-insert
  inside a serialized `@ModelActor`. This is the load-bearing correctness
  assumption in the whole persistence layer, and it deserves the hardest look in
  the review.
- **ADR-029** — the ambience beds are synthesised at runtime rather than being
  recorded audio.
- **ADR-023** — a saved game is its move log, not its board.
- **ADR-027** — widgets read a snapshot file and never touch the store.

## 4. Where to spend review time

Ranked by consequence-if-wrong, not by size.

1. **Persistence and migration** — `Apps/iOS/Persistence/`. Eight schema
   versions, all claimed additive, all lightweight-migrated. No migration has ever
   run. If `SunnieSchemaV1…V8` and the migration plan are wrong, the failure mode
   is silent data loss on a real device. ADR-017 also records a **schema namespace
   freeze that is still owed** — the versioned models are not yet frozen into
   per-version namespaces, which is a latent trap the first time a model's shape
   must change.
2. **Concurrency** — `SWIFT_STRICT_CONCURRENCY = complete` under Swift 5 language
   mode (ADR-010). Actors, `@MainActor`, `@ModelActor`, and two audio render
   blocks with hand-managed `@unchecked Sendable` boxes
   (`Apps/iOS/Integrations/NoiseEngine.swift`,
   `ProceduralAudioEngine.swift`). The render-block discipline — no allocation, no
   locking — is asserted in comments and has never been measured.
3. **Idempotency** — the property everything with a Watch, a notification action,
   or an App Intent depends on. Keys are generated from what happened, never from
   the device (ADR-013). One real bug of exactly this kind was caught during
   authorship: the Watch's hydration key was being regenerated from the phone's
   clock, so a redelivered transfer would have created a second entry. Assume
   there are more.
4. **The audio layer** — the newest and least settled code.
   `Packages/SunnieShared/Audio/` plus `Apps/iOS/Integrations/AudioService.swift`.
   `Apps/iOS/README-Audio.md` lists twelve device checks, none of which has been
   run.
5. **Privacy surfaces** — HealthKit, EventKit, MapKit, WeatherKit, PhotosUI, and
   the media store. `Documentation/05_Technical/PRIVACY_SECURITY_AND_DATA_LIFECYCLE.md`
   is the specification. Entitlements ship as inactive placeholders (ADR-012), so
   CloudKit is off and the app is local-only today.
6. **Accessibility** — claimed to be built in per screen rather than retrofitted.
   Never verified with VoiceOver, Dynamic Type, or a contrast checker, because
   nothing has been rendered.

## 5. Known open items

Stated plainly so the review does not spend time rediscovering them.

- The Watch target compiles for the watchOS Simulator, but physical-device-only
  behavior remains untested. (§1)
- Phase 11 — accessibility pass, CloudKit validation, migration suite,
  performance, onboarding, export and delete, release — is not started.
- The schema namespace freeze owed by ADR-017 has not been done.
- Physical-device Watch testing has never been run; queued background transfers
  cannot be validated on a simulator. The plan is in `Apps/Watch/README.md`.
- The rendered soundtrack does not exist. Seven music tracks are declared in the
  manifest against filenames that have not been recorded; the director skips them
  until the files appear.
- Graphics are placeholders throughout, deliberately. The owner's stated
  preference was to progress the project and get it running, with artwork second.
- Reference images are excluded from this package — 13 MB of character art that a
  code review does not need. They are in `Documentation/Reference_Images/` in the
  repository.

## 6. Notes for whoever receives this

This is a personal application built for one named individual. The documentation
and content include her name, her dietary rule, and the design of health and mood
tracking intended for her. None of it is credentials or secrets — a scan found
none, and every `token` in the code is a domain concept, not a secret — but it is
personal, and it is worth agreeing with the owner where this package may be
stored and who may open it before it is forwarded.

Nothing in the package needs network access to review, and nothing phones home.

## 7. Working with the code

```bash
# Fastest signal: the shared package alone. Pure Swift, no UI, no SwiftData.
cd Packages/SunnieShared && swift build && swift test

# The whole thing, on a Mac with Xcode 16+
open SunnieDays.xcodeproj      # scheme SunnieDays, any iPhone simulator

# Checks that need no build
./Scripts/validate-content.sh
python3 Tools/validate_audio_manifest.py CreatorAudioSource/audio.manifest.json
```

Signing is deliberately unconfigured so the project builds for the Simulator out
of the box. To run on a device, set `SUNNIE_DEVELOPMENT_TEAM` in
`Config/Shared.xcconfig`.

## 8. Where to read next

| If you want | Read |
|---|---|
| What the product is | `Documentation/MASTER_SOURCE_OF_TRUTH.md` |
| What is deliberately out of scope | `Documentation/01_Product/RELEASE_SCOPE_AND_NON_GOALS.md` |
| How it is meant to be built | `Documentation/05_Technical/TECHNICAL_ARCHITECTURE.md` |
| Why a given piece of code is the way it is | `ARCHITECTURE_DECISIONS.md` |
| What has and has not been verified | `Documentation/BUILD_AND_VERIFY.md` |
| Where the first build is likely to break | `Documentation/COMPILE_RISK_REVIEW.md` |
| Getting it onto a real iPhone | `Documentation/DEVICE_BRING_UP.md` |
| What was planned per phase | `Documentation/06_Delivery/IMPLEMENTATION_ROADMAP.md` |
| The rules the code was written under | `CLAUDE.md` |
