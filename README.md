# Sunnie Days

A private, fully native iPhone and Apple Watch companion app built around Sunnie,
a young, baby-faced, plush-looking sloth who is sometimes sleepy and always kind.

The complete product definition lives in [`Documentation/`](Documentation). Start
with [`Documentation/README_FIRST.md`](Documentation/README_FIRST.md) and
[`Documentation/MASTER_SOURCE_OF_TRUTH.md`](Documentation/MASTER_SOURCE_OF_TRUTH.md);
[`CLAUDE.md`](CLAUDE.md) holds the operating rules for working in this repository.

## Status

Phases 0 through 10 of
[the roadmap](Documentation/06_Delivery/IMPLEMENTATION_ROADMAP.md) are written —
foundation, app shell, the first vertical slice, plant care, wellness, travel,
meals, games, collections and Sunnie's Home, the Health/Watch/widget/intent
integrations, and the audio layer. Phase 11 — accessibility, CloudKit, export,
and release — is not started.

> **Every target now has compiler evidence from CI.** The iPhone app and widget
> build in the regular macOS job; the manual Watch job downloads the watchOS SDK
> on demand and has completed successfully.

**Verification status, precisely.**

- **The shared package (`SunnieShared`) compiles and its 460 tests pass**, on
  Linux with Swift 6.1.2. That is roughly a third of the codebase — all the
  domain logic, content schemas, and pure algorithms — and it is genuinely
  verified, not argued for.
- **The iPhone app and widget extension compile on a macOS runner.** The app runs
  on an iPhone simulator, with 223 app tests and 7 UI tests passing.
- **The Watch app compiles for the watchOS Simulator.** Its manual CI job installs
  the watchOS SDK before building; physical-device behavior remains a release check.

Getting the shared package building found three real defects that no amount of
static checking had caught: a `ColorValue` that encoded as an object while every
content pack wrote a bare string (so the whole theme pack silently fell back to a
one-theme stub), travel coverage that dropped tasks already overdue when a trip
began, and a nickname helper that was uncallable by its only callers.

Reviewing this from outside? [`REVIEW_PACKET.md`](REVIEW_PACKET.md) is the
orientation document: what is real, what is verified, and where the risk is.

## Getting started

Requires a Mac with Xcode 16 or later.

```bash
git clone <this repository>
cd sunnie
open SunnieDays.xcodeproj
```

See [`Documentation/DEVICE_BRING_UP.md`](Documentation/DEVICE_BRING_UP.md) for the
full path onto a real device, and
[`Documentation/COMPILE_RISK_REVIEW.md`](Documentation/COMPILE_RISK_REVIEW.md) for
where the first build is most likely to need attention.

Select the **SunnieDays** scheme and run on an iPhone simulator. The app seeds a
small sample jungle on first launch so the plant-care flow has something to act on.

Signing is not configured, which is deliberate: the project builds for the
Simulator out of the box. To run on a device, set `SUNNIE_DEVELOPMENT_TEAM` in
[`Config/Shared.xcconfig`](Config/Shared.xcconfig).

## Running the tests

```bash
# Domain rules — fastest, no simulator needed
cd Packages/SunnieShared && swift test

# Content packs — no toolchain needed at all
./Scripts/validate-content.sh

# Everything, including repository, integration, and UI tests
xcodebuild test -project SunnieDays.xcodeproj -scheme SunnieDays \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## What is written

Every feature area has screens, a use-case layer, repositories, and content:
plant care with schedules and QR identity, wellness with check-ins, breathing,
meditation and a journal, travel with trips, packing and a flight-attendant
brief, meals with dietary filtering, seven games across six shapes, collections
and Sunnie's Home, HealthKit, an Apple Watch companion, widgets, App Intents,
and an audio layer that synthesises its own ambience and bells.

Eight SwiftData schema versions, all additive. 32 architecture decision records.
1,111 localized strings. 460 shared-package tests, 223 app tests, and 7 UI tests
passing in CI.

## What is deliberately not built

**Artwork is a placeholder throughout** — the character is drawn as a stand-in
shape, and [`AssetsSource/ASSET_MANIFEST.md`](AssetsSource/ASSET_MANIFEST.md)
records what the real layered art must supply. This is a choice, not an
oversight: the priority was getting the whole app working end to end first.

The creator's rendered soundtrack does not exist yet either — seven music tracks
are declared in the audio manifest against filenames not yet recorded, and are
skipped until the files appear. The synthesised ambiences and bells do work.

iCloud sync and HealthKit ship with entitlement placeholders that are switched
off (ADR-012), so a clean clone builds and the app runs local-only.

## Repository layout

```
Apps/iOS/            iPhone app: App, DesignSystem, Features, Services,
                     Integrations, Persistence, Resources
Apps/Watch/          Apple Watch companion
Apps/Widgets/        Widget extension
Packages/SunnieShared/
                     Platform-neutral domain, protocols, content schemas,
                     Watch payloads, pure utilities
Tests/               App-target unit and UI tests
Config/              xcconfig files — all placeholders live here
Documentation/       The source-of-truth document pack
AssetsSource/        Non-runtime art source and the asset manifest
CreatorAudioSource/  Non-runtime audio source (never shipped)
Scripts/             Content validation
Tools/               Creator-side validators that need no build
```

## Ground rules

A few decisions are locked and should not be quietly reversed. Swift and SwiftUI
only, no third-party packages without an ADR, and no cross-platform UI framework.
The day-cycle names are exactly **Sunnie Days**, **Sunnie Afternoonies**, and
**Sunnie Nights** — "Sunnie Mornings" and "Sunnie Evenings" do not exist. The app
never uses sarcasm, shame, guilt, or punitive streak language, and a machine check
in `ContentValidator` fails the tests if any does. Nothing earned is ever taken
away.

See [`ARCHITECTURE_DECISIONS.md`](ARCHITECTURE_DECISIONS.md) for the full list and
the reasoning.
