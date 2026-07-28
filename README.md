# Sunnie Days

A private, fully native iPhone and Apple Watch companion app built around Sunnie,
a young, baby-faced, plush-looking sloth who is sometimes sleepy and always kind.

The complete product definition lives in [`Documentation/`](Documentation). Start
with [`Documentation/README_FIRST.md`](Documentation/README_FIRST.md) and
[`Documentation/MASTER_SOURCE_OF_TRUTH.md`](Documentation/MASTER_SOURCE_OF_TRUTH.md);
[`CLAUDE.md`](CLAUDE.md) holds the operating rules for working in this repository.

## Status

Phases 0, 1, and 2 of
[the roadmap](Documentation/06_Delivery/IMPLEMENTATION_ROADMAP.md) are written:
project foundation, shared engines and app shell, and the first vertical slice.

> **This code has never been compiled.** It was authored in a Linux environment
> with no Swift toolchain and no Xcode, so nothing here has been built, run, or
> tested on a device or simulator. Read
> [`Documentation/BUILD_AND_VERIFY.md`](Documentation/BUILD_AND_VERIFY.md) before
> assuming any of it works.

## Getting started

Requires a Mac with Xcode 16 or later.

```bash
git clone <this repository>
cd sunnie
open SunnieDays.xcodeproj
```

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

## What works in this slice

The path `FIRST_VERTICAL_SLICE.md` asks for, end to end:

```
Today plant card → Jungle due list → Plant detail → log watering
  → persist event → recalculate schedule → progression event
  → Sunnie response → update Today → Watch payload
```

Alongside it: the five-tab shell with per-tab navigation stacks, typed routing
and `sunniedays://` deep links, the universal time engine and its three branded
presentations, three data-driven themes with per-phase variants, the SwiftData V1
schema with a migration plan, repositories behind protocols, the progression
engine with idempotency and reward-farming guards, and a minimal Watch app that
can complete care offline.

## What is deliberately not built

Travel, Wellness, Meals, Games, Journal, Collections, and Sunnie's Home are
labelled placeholders. So is every piece of Sunnie artwork — the character is
drawn as a stand-in shape, and
[`AssetsSource/ASSET_MANIFEST.md`](AssetsSource/ASSET_MANIFEST.md) records what the
real layered art must supply. Audio has a working service but no assets.
iCloud sync and HealthKit have entitlement placeholders that are switched off.

## Repository layout

```
Apps/iOS/            iPhone app: App, DesignSystem, Features, Services,
                     Integrations, Persistence, Resources
Apps/Watch/          Apple Watch companion
Apps/Widgets/        Reserved for Phase 9
Packages/SunnieShared/
                     Platform-neutral domain, protocols, content schemas,
                     Watch payloads, pure utilities
Tests/               App-target unit and UI tests
Config/              xcconfig files — all placeholders live here
Documentation/       The source-of-truth document pack
AssetsSource/        Non-runtime art source and the asset manifest
CreatorAudioSource/  Non-runtime audio source (never shipped)
Scripts/             Content validation
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
