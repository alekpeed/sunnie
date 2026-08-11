# Sunnie Days — start here

This package contains a complete iPhone and Apple Watch app. Its shared logic
builds and passes 460 tests; the iPhone app and widget compile and the app runs
on a simulator, and the Watch target compiles for the watchOS Simulator.
Hardware-only integrations remain unproven.

There are two halves to this document. **Part 1 is for the app's owner** and
assumes no technical knowledge. **Part 2 is for the developer** and assumes
plenty.

---

# Part 1 — For the owner

## What this is

A private app built for one person. It covers looking after houseplants,
wellbeing check-ins, travel planning, meals, some puzzle games, and a collection
of things you unlock over time — all fronted by a cartoon sloth called Sunnie.

Roughly 64,000 lines of code across 223 files, plus a full written specification
of what the app is meant to do.

## The honest status

**The shared package and iPhone app now build and pass their automated tests.**

The project splits into two halves. The shared half — all the rules and logic,
no screens — has now been compiled and tested properly: **460 tests, all
passing.** Doing that turned up three real bugs, all since fixed, including one
that silently broke every colour theme in the app.

The iPhone app and widget have since been compiled on a macOS CI runner. The app
runs on an iPhone simulator, with **223 app tests and 7 UI tests passing**. The
Watch target also compiles in its on-demand watchOS SDK job. Real-device checks
remain necessary for haptics, camera, audio interruption, Health, and paired
WatchConnectivity behavior.

## What you are hiring someone to do

In order:

1. **Compile the Watch target** with the on-demand watchOS CI job and fix any
   compiler errors it finds.
2. **Exercise the remaining simulator flows** beyond the current seven UI tests.
3. **Put it on a real iPhone** and test the things only real hardware can do —
   vibration, camera, the Apple Watch.

## How long this takes

I can't give you a reliable number, and I'd rather say so than invent one.

What I can tell you: this is **days of work, not hours.** Sixty-four thousand
lines of never-checked code is a lot of surface area, even when most of the
problems turn out to be small ones. Anyone who quotes you a couple of hours has
not understood the job.

A sensible way to hire: ask for **step 1 only, priced separately**, before
committing to the rest. Once it builds, everyone — including you — knows far more
about what the remaining work looks like.

## How to tell it's going well

You don't need to read code to judge progress. Ask for these, in order:

1. **"Does the shared logic build yet?"** There's a self-contained third of the
   project that compiles on its own in seconds. It's the fastest early signal.
2. **"Can I see a screenshot of the app running?"** Even one screen proves the
   whole thing starts.
3. **"How many of the app-side tests pass?"** A number that climbs is real
   progress. (The 460 shared ones already pass — ask them to confirm that still
   holds, which takes one command and no Mac.).
4. **"Is it on a real iPhone yet?"**

If someone can't produce the first of those after a solid day, ask why.

## What's deliberately unfinished

So nobody bills you to "fix" things that aren't broken:

- **Sunnie is a grey blob.** All artwork is a placeholder on purpose. The plan
  was always to get the app working first and draw it properly later.
- **There's no music.** Background sounds like rain and crickets do work — the
  app generates those itself. The actual composed music was never recorded.
- **iCloud sync is switched off.** Deliberate. It can be turned on later.
- **Nothing plays sound when you open the app.** That's a design choice, not a
  fault. Sound happens when you tap something.

## One thing to agree before you send this

This app was built for a specific person. The written specification includes her
name, her dietary requirement, and the design of mood and health tracking
intended for her.

There are no passwords or security keys in here — I checked. But it is personal.
It's worth agreeing with whoever you hire where this gets stored and who else
sees it, before you send it.

## What's in this package

| Folder or file | What it is |
|---|---|
| `START_HERE.md` | This document |
| `REVIEW_PACKET.md` | A deeper orientation, if the developer wants one |
| `Documentation/` | The full written specification — what the app should do and why |
| `Apps/`, `Packages/`, `Tests/` | The code itself |
| `ARCHITECTURE_DECISIONS.md` | Why things were built the way they were |
| everything else | Supporting configuration and tools |

---

# Part 2 — For the developer

## The short version

Native Swift/SwiftUI iPhone app plus a watchOS companion and a widget extension.
Modular monolith, one local SPM package, no third-party dependencies. iOS 18 /
watchOS 11 deployment targets, Swift 5 language mode with
`SWIFT_STRICT_CONCURRENCY = complete`.

**The iPhone app and widget compile in CI; the Watch target remains uncompiled.**

**The shared package has**, on Linux with Swift 6.1.2 — `swift build && swift
test`, 460 passing. Doing that found three real defects, now fixed: `ColorValue`
encoded as an object against content packs written as bare strings (which made
the entire theme pack fall back to a one-theme stub, silently); `CoveragePlanner`
projecting *past* tasks already overdue when an absence began, dropping them
entirely; and `NicknameEligibility.shouldUseNickname` taking `some RandomSource`
where every caller holds `any RandomSource`, making it uncallable.

`os` and the App Group container call are now `canImport`-guarded, which is what
makes the package build off-Apple. That is worth keeping: it means a third of the
codebase is testable in ordinary CI, on any machine.

## Where to start

```bash
cd Packages/SunnieShared && swift build
```

That's a third of the codebase, platform-neutral, no UI, no SwiftData — it builds
in seconds on Linux or macOS and fails on domain logic rather than on a view
hierarchy. Get it green (it already is), then `swift test` — 460 passing — then
use the `SunnieDays` scheme for the iPhone simulator or dispatch the manual Watch
job for the remaining uncompiled target.

Signing is deliberately unconfigured and entitlements ship commented out, so the
Simulator build needs no developer account. `Config/Shared.xcconfig` is where
that changes.

## Read these three, in this order

| Document | Why |
|---|---|
| `Documentation/COMPILE_RISK_REVIEW.md` | Where the first build is most likely to break, ranked by blast radius — **and** what was already checked clean, so you don't re-tread it. Read before touching anything. |
| `Documentation/DEVICE_BRING_UP.md` | Clone → device. Entitlements, App Group identifiers, what only hardware can test, and a table of symptoms that look like bugs but are configuration or deliberate. |
| `ARCHITECTURE_DECISIONS.md` | 31 ADRs. When code looks wrong, the argument for it is usually here. Disagreeing with an argument is a legitimate finding; not knowing it existed is wasted time. |

## Things worth knowing before you start fixing

**Strict concurrency will not block you.** `complete` under Swift 5 language mode
means data-race diagnostics are warnings, not errors. Noisy, not blocking. Drop
to `targeted` while you work if it drowns out real errors — but put it back;
ADR-010 makes the Swift 6 move deliberate.

**Errors will cluster.** ~40 repository protocol methods each have one
implementation and several call sites, so a single wrong signature surfaces as a
dozen errors. Fix by shape, not by scrolling the error list.

**The highest-count single risk** is 34 uses of
`String(localized: .init(runtimeKey))` for content-pack keys. It may not compile;
more subtly, it may compile and return the key instead of the translation, since
`String(localized:)` is built around extractable literals. `COMPILE_RISK_REVIEW.md`
§1 has the drop-in replacement.

**The widget target was hand-written into `project.pbxproj`** rather than added
through Xcode. It audits structurally clean, but if it misbehaves inexplicably,
delete and re-add the target — the source files are fine.

## What has actually been verified

Everything possible without a toolchain, and nothing more:

- Brace balance across all 223 Swift files
- Localization key coverage — 1,111 strings, no missing keys
- All 366 `@Model` properties are SwiftData-native types
- 119 `#Predicate` bodies reviewed; the one risky construct was fixed
- Protocol conformance sweep across every implementer
- `project.pbxproj` structural audit — 89 objects defined and referenced
- Every plist and entitlements file parses
- Permission-gated APIs matched against Info.plist purpose strings
  (`python3 Tools/validate_permissions.py`)
- Independent Python re-implementations of the puzzle solver, the collection
  placement rules, and the entire procedural-audio DSP chain

None of that is a substitute for a compiler. It rules out whole classes of
mistake and rules out nothing about the type system.

## The highest-consequence untested area

Eight SwiftData schema versions, all additive, all lightweight-migrated, **none
ever run**. If the migration chain is wrong, the failure mode is silent data loss
on a real device rather than a crash. ADR-017 also records a schema namespace
freeze that is still owed.

This deserves attention out of proportion to its line count.

## Known-unfinished, do not "fix"

- Artwork is placeholder throughout (`AssetsSource/ASSET_MANIFEST.md`)
- Seven music tracks are declared against files that were never recorded; the
  audio director skips them by design. Synthesised ambience and bells do work.
- CloudKit, HealthKit and WeatherKit entitlements ship inactive (ADR-012) so a
  clean clone builds without a developer account
- Audio autoplay defaults to off — deliberate, per spec

## Repository access

This package is a snapshot. The live repository is private on GitHub and access
can be granted, which gives you full history and somewhere to push. Ask the owner.
