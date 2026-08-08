# Device bring-up

Getting Sunnie Days from a fresh clone onto a real iPhone, in the order that
fails fastest and wastes least.

Written for someone with a **paid Apple Developer account**, which unlocks
HealthKit, App Groups, CloudKit, and WeatherKit. Without one, steps 5 onward are
mostly unavailable and the app runs local-only — which is still a complete app,
just without Health, widgets, or sync.

> **The build is green.** It compiles, the tests pass, and CI proves it on every
> push — which was not true when this document was written, and the steps below
> were shaped by the expectation that step 1 would be a fight. It is not one
> any more. What remains genuinely unverified is everything that needs hardware:
> haptics, camera, audio interruptions, Health, and the Watch.

---

## 0. What you need

| | |
|---|---|
| **A Mac** | For *this* route. Without one, `TESTFLIGHT_SETUP.md` builds on a CI runner and installs through TestFlight instead. |
| **Xcode 16 or later** | The project pins Swift 5 language mode with complete concurrency checking. |
| **iPhone on iOS 18+** | `IPHONEOS_DEPLOYMENT_TARGET = 18.0`. An older phone will not install it. |
| **Apple Watch on watchOS 11+** | Only for the Watch app. Optional. |
| **A cable** | Wireless debugging works, but first pairing over cable is less fiddly. |

The iPhone is **not** needed for steps 1–3. The Simulator covers most of the app,
and it is a far faster loop than a device for anything that does not need one.

---

## 1. Confirm it still compiles

It does — but confirm it locally before blaming your setup for anything later.
Start with the shared package. It is a third of the codebase, has no UI, no
SwiftData, and no Apple framework beyond Foundation — so it builds in seconds and
fails on the domain logic rather than on a view hierarchy.

```bash
cd Packages/SunnieShared
swift build
```

Then:

```bash
swift test        # 441 tests, all passing
```

Only then open the project:

```bash
open SunnieDays.xcodeproj      # scheme: SunnieDays, destination: any iPhone 16 simulator
```

This built clean in CI, so errors here mean your toolchain rather than the code:
the project needs Xcode 16 or later. `Documentation/COMPILE_RISK_REVIEW.md` was
written when none of this had met a type checker and is kept as a record of what
was predicted against what actually broke.

Two settings worth knowing while you work:

- `SWIFT_STRICT_CONCURRENCY = complete` in `Config/Shared.xcconfig`. If data-race
  warnings are drowning out real errors, set it to `targeted` temporarily. Put it
  back — ADR-010 is explicit that this is a deliberate stepping stone to Swift 6.
- Signing is **off** by default (`SUNNIE_DEVELOPMENT_TEAM` is empty and
  entitlements are commented out), so the Simulator build needs no account at
  all. Leave it that way until step 4.

## 2. Look at it in the Simulator

First launch seeds a sample jungle — a living room and a bedroom with plants —
so there is something real to act on immediately.

Worth walking before touching a device, because none of it needs hardware:

- Today, and the plant care loop end to end
- The three branded day cycles. Settings → *Time of day* → hold it at each of
  **Sunnie Days**, **Sunnie Afternoonies**, **Sunnie Nights**
- Wellness: check-in, breathing, meditation, journal
- Travel, meals, all seven games, collections, Sunnie's Home
- Calm sounds — the eight ambiences and both bells are synthesised, so they work
  with no assets and no account
- Accessibility: VoiceOver, Dynamic Type at its largest, Reduce Motion

## 3. Run the tests

```bash
xcodebuild test -project SunnieDays.xcodeproj -scheme SunnieDays \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

`.github/workflows/ci.yml` runs the same jobs on every push and is green: 223
tests across 13 suites, 7 UI tests on a simulator, and the shared package on both
Linux and macOS. A local run should agree with it, and a disagreement is worth
understanding before you go near hardware.

Note what the UI tests do *not* prove. They run against a fresh in-memory store,
so nothing there exercises data surviving a relaunch — that is still a by-hand
check, and it is on the list in §2.

## 4. Put it on the phone, unsigned features only

The smallest step that proves the device path works. No entitlements yet.

1. `Config/Shared.xcconfig` → set `SUNNIE_DEVELOPMENT_TEAM` to your 10-character
   Team ID. Xcode → Settings → Accounts → your account → *Manage Certificates*,
   or the membership page on developer.apple.com.
2. Optionally change `SUNNIE_BUNDLE_ID_PREFIX` from `com.sunniedays` to your own
   reverse-DNS prefix. Every target derives from it; nothing hardcodes a bundle
   id.
3. Plug the phone in, trust the Mac, select it as the destination, run.
4. On the phone: Settings → General → VPN & Device Management → trust the
   developer certificate. First install only.

**Now check the things a Simulator cannot show you:**

- Haptics — they are silent on the Simulator, so this is the first time you hear
  them
- Camera and QR plant tags
- Audio interruptions. The twelve checks in `Apps/iOS/README-Audio.md`, none of
  which has ever been run. Start with: play an ambience, ring the phone from
  another device, confirm it pauses and resumes; then pull the headphones and
  confirm it **stops** rather than switching to the speaker.

## 5. Turn on the entitlements

This is the step that needs the paid account, and the step where mismatched
identifiers cost the most time. Do it in this order.

### 5a. On developer.apple.com

Under *Certificates, Identifiers & Profiles*:

1. Register an **App Group**: `group.com.sunniedays.app` (or your prefix). It
   must match `WidgetSnapshotStore.appGroupIdentifier` **exactly** — that string
   is in `Packages/SunnieShared/Sources/SunnieShared/Payloads/WidgetSnapshot.swift`.
2. Register an **iCloud container**: `iCloud.com.sunniedays.app`.
3. On the app identifier, enable: HealthKit, App Groups, iCloud (CloudKit),
   WeatherKit.
4. Do the same App Group on the **widget extension's** identifier. The app writes
   the snapshot and the extension reads it; if only one side has the group, the
   write silently no-ops and the widgets show their empty state. That failure
   looks exactly like a bug in the widget code and is not one.

### 5b. In the repository

1. `Apps/iOS/Resources/SunnieDays.entitlements` — replace the container
   identifier with yours, and flip the two `<false/>` values:
   ```xml
   <key>com.apple.developer.weatherkit</key><true/>
   <key>com.apple.developer.healthkit</key><true/>
   ```
2. `Config/App-iOS.xcconfig` — uncomment:
   ```
   CODE_SIGN_ENTITLEMENTS = Apps/iOS/Resources/SunnieDays.entitlements
   ```
3. `Config/Extension-Widgets.xcconfig` — uncomment the same line for
   `Apps/Widgets/Resources/SunnieWidgets.entitlements`.
4. For sync, pass `cloudKit: true` to `ModelContainerFactory.make`.

ADR-012 explains why these ship inactive: a clean clone has to build for someone
who has not configured signing, and an entitlement referencing a team they are
not in fails at the signing step with a message that does not say so.

### 5c. Then check

```bash
python3 Tools/validate_permissions.py
```

Every permission the code requests must have a purpose string, or **iOS kills the
process** — not a denied prompt, a termination. This catches it before the device
does.

**Health is the one to test carefully**, because it is the one that would have
crashed: Settings → Health → enable a type. The permission sheet should appear
with the purpose string, one type at a time (ADR-026). Note that HealthKit never
reports a *denied read* — the app deliberately never claims to know whether a read
was granted, so an empty figure and a refused permission look the same on purpose.

## 6. The Watch

Genuinely last, because it is the fiddliest and the least essential — the phone
app is complete without it.

1. Pair the Watch to the iPhone.
2. Build the `SunnieDaysWatch` scheme to the Watch. First install over cable to
   the phone is the reliable route; wireless works afterwards.
3. Run the four-step test plan in `Apps/Watch/README.md`.

**This is the one thing that cannot be validated any other way.** Queued
`WatchConnectivity` background transfers do not behave on the Simulator: the
whole point is what happens when the phone is *unreachable*, and a paired
simulator is always reachable. The scenario to force is — put the phone in
Airplane Mode, log care on the wrist, confirm it queues; bring the phone back,
confirm exactly one record appears, not two. That single-record property is
ADR-013 and ADR-028, and it has never been observed.

---

## Known traps

Things that will look like bugs and are either known, deliberate, or
configuration.

| Symptom | Cause |
|---|---|
| No music anywhere | Correct. Seven music tracks are declared against files the creator has not recorded; the director skips them. The synthesised ambiences and bells do play. |
| Sunnie is a grey blob | Correct. Artwork is a deliberate placeholder — see `AssetsSource/ASSET_MANIFEST.md`. |
| Nothing plays on launch | Correct, and deliberate. Autoplay defaults to off; sound happens when you tap it. Settings → *When sound plays*. |
| Widgets stuck on "open Sunnie Days" | The App Group is missing on one of the two targets, or the ids differ by a character. |
| App is terminated on enabling Health | A missing purpose string. Run `Tools/validate_permissions.py`. |
| Weather line missing from a trip | WeatherKit entitlement off, or offline. Deliberate: it fails silently (ADR-020). |
| Ambience stops when the screen locks | Correct by default. Settings → *Keep playing when the screen locks*. |
| Everything resets after 7 days | Free provisioning expiry. Not applicable with a paid account. |

## What still cannot be tested

Honest limits, so nobody goes looking:

- **The rendered soundtrack** does not exist. Nothing to test.
- **CloudKit sync across two devices** needs a second device signed into the same
  iCloud account.
- **Schema migration from a real prior install** cannot be exercised on a fresh
  install — there is no V1 database in the wild to migrate from. The eight
  versions are additive and untested against real data, and ADR-017's namespace
  freeze is still owed. This is the highest-consequence untested area in the
  project.
