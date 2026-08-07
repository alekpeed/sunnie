# Sunnie Days — start here

This package contains a complete iPhone and Apple Watch app, written but never
built. It needs a developer with a Mac to turn it into something that runs.

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

**The code is written. It has never been run.**

Every line was written in an environment with no Apple software available, so no
computer has ever checked it for mistakes, and no screen has ever been displayed.

A fair comparison: imagine a 600-page manuscript, carefully written and
self-edited, that has never been through a proofreader or a printing press. The
writing is done. Whether it prints cleanly is genuinely unknown.

## What you are hiring someone to do

In order:

1. **Make it build.** Fix the mistakes a computer finds the first time it checks
   the code. This is the bulk of the work.
2. **Run it on a simulated iPhone** (a Mac can pretend to be an iPhone) and check
   the screens actually appear and work.
3. **Run the automated tests.** There are 659 of them already written. None has
   ever been run.
4. **Put it on a real iPhone** and test the things only real hardware can do —
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
3. **"How many of the 659 tests pass?"** A number that climbs is real progress.
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

**It has never been compiled.** Not once. Budget accordingly.

## Where to start

```bash
cd Packages/SunnieShared && swift build
```

That's a third of the codebase, platform-neutral, no UI, no SwiftData — it builds
in seconds and fails on domain logic rather than on a view hierarchy. Get it
green, then `swift test` (659 tests, first run ever), then open the Xcode project.

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
