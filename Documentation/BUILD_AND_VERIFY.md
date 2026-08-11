# Build and Verify

## Read this first

**Every target is compiled in CI; the regularly triggered checks are green.**

- `Packages/SunnieShared` **builds and passes 460 tests** on Linux with Swift
  6.1.2 (ADR-032). Run it anywhere: `cd Packages/SunnieShared && swift test`.
- The iPhone app and the widget extension **compile**, and the app **runs on a
  simulator**. 223 tests across 13 suites pass, and 7 UI tests drive the real
  app: five tabs, the plant card, and Today → plant → log care end to end.
- The **Watch app compiles for the watchOS Simulator.** Its job is manual-only,
  because the runner ships no watchOS SDK and fetching one costs several
  gigabytes per run. The first successful build completed on 2026-08-11.
- No screen has been rendered on a **device**. Haptics, camera, audio
  interruption, and Health are all still unobserved.

The gap between "compiles" and "works" is where this project has lost most of
its ground, and it is worth being precise about which one a claim rests on.
Every defect listed below type-checked.

Getting the shared package to compile found three defects that no amount of
static checking had caught: `ColorValue` encoding as an object against content
packs written as bare strings (which silently reduced the app to one theme),
travel coverage dropping tasks already overdue at departure, and a nickname
helper that was uncallable by its only callers. All three are fixed and have
regression tests.

Running the app found four more, and three of them share a shape worth naming:
a `#Predicate` that is valid Swift, reads exactly as intended, and means
something else once translated to SQL. Journal search used `??`, which becomes a
ternary with no SQL behind it and threw on every query. The trip list compared a
null column with `!=`, which SQL answers NULL rather than true, so it returned
nothing at all — emptying the travel list, the Watch context, the widget
snapshot, and Sunnie's Home from one line. The hydration catch-up queue asked
`.isEmpty`, a Swift property with no column operator, and silently matched
nothing, so water logged while Health was off would never have been written once
it was turned on. The fourth was ordering: Today built its summary before
first-launch seeding finished and was never told to look again, so a new user
saw "No plants yet" above five plants that existed.

None of the four was findable without executing the code. Two of them would have
looked like features quietly doing nothing, with no error to explain why. That is
the standing argument for running things over reasoning about them, and for
`CLAUDE.md`'s rule against calling anything complete on an untested happy path.

What *has* been verified, because it needs no Swift toolchain:

- Every `.plist`, `.json`, `.xcscheme`, and `.xcworkspacedata` file parses.
- `project.pbxproj` is brace-balanced, has no dangling object references, no
  orphaned objects, and paired section markers. That is structural validity, not
  semantic correctness — Xcode may still reject it.
- `Scripts/validate-content.sh` passes on the shipped content, and was confirmed
  to fail on deliberately introduced violations (a shaming phrase, a nickname
  placeholder in a privacy notice, and a forbidden day-cycle name).
- Brace balance across every Swift file, `Localizable.strings` key coverage, a
  tone gate over authored copy, duplicate top-level type detection, and a
  protocol-conformance sweep.
- Independent Python re-implementations of three pieces of logic the Swift is
  supposed to match: the Jungle Logic solver (proving puzzle uniqueness and clue
  minimality), the collection placement rules, and the whole procedural-audio
  signal chain (which is where the ambience calibration figures came from). The
  ports are not in the repository — only their conclusions are, so those numbers
  are claims to re-derive rather than measurements to trust.

None of that is a substitute for a compiler. It rules out whole classes of
mistake and rules out nothing about the type system.

## Bring-up order

Work outward from what has fewest dependencies. Each step is independently
useful, so a failure early does not block understanding the rest.

### 1. The shared package alone

```bash
cd Packages/SunnieShared
swift build
swift test
```

This is pure Swift with no UI, no SwiftData, and no Apple framework beyond
Foundation and `os`. If anything is wrong with the domain types, protocol
signatures, or the pure logic in `Utilities/`, it surfaces here fastest. The
tests cover schedule calculation, action keys, the time engine, nickname rules,
content validation, theme resolution, progression idempotency, and Watch payload
round trips.

### 2. Open the project

```bash
open SunnieDays.xcodeproj
```

The project uses `objectVersion = 77` and file-system-synchronized groups, so
Xcode 16 or later is required. Targets pick up sources by folder rather than by
enumerated file references, which means adding a Swift file needs no project
edit.

If Xcode reports the project is damaged, the pbxproj is the thing to suspect
first — it was hand-authored. The fastest recovery is to create a fresh project
with the same four targets and point them at the existing folders; all the source
is independent of the project file.

### 3. Build the iPhone app

```bash
xcodebuild build -project SunnieDays.xcodeproj -scheme SunnieDays \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO
```

Expect to fix things here. The most likely categories, in rough order of
probability:

- **SwiftData `#Predicate` expressions.** These are macro-checked and fussy about
  what they can capture. The predicates in `Apps/iOS/Persistence/` compare
  captured `String` and `UUID` locals, which is the supported shape, but this is
  the area with the least margin for error.
- **`@ModelActor` usage.** The macro generates `init(modelContainer:)` and a
  `modelContext` property; the repositories assume both.
- **Concurrency diagnostics.** Strict checking is on. These should be warnings,
  not errors, under Swift 5 language mode (ADR-010).
- **Localized string keys.** `Text("some.key", bundle: .main)` shows the raw key
  if the entry is missing from `Localizable.strings`.
- **The `@Entry` macro** in `DesignTokens.swift` requires Xcode 16.

### 4. Build the Watch app

```bash
xcodebuild build -project SunnieDays.xcodeproj -scheme SunnieDaysWatch \
  -destination 'generic/platform=watchOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

The Watch app links the same shared package. If the embed step misbehaves, check
the `Embed Watch Content` copy phase on the iPhone target — `dstSubfolderSpec` and
`dstPath` are the usual culprits.

### 5. Run the tests

```bash
xcodebuild test -project SunnieDays.xcodeproj -scheme SunnieDays \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO
```

Unit tests use Swift Testing; the UI tests use XCTest because XCUITest requires
it. The UI tests are written against accessibility labels rather than layout, so
they should survive the visual design pass — but they are the least likely part of
this repository to pass first time, since they assert on exact label text.

### 6. Walk the vertical slice by hand

Automated tests cannot confirm this reads well. On a simulator:

1. Today shows a greeting from Sunnie and a plant card with a waiting task.
2. Tap through to the due list, then into a plant.
3. Tap **Log care**, save, and watch the task leave Today.
4. Force-quit and relaunch — the care event should still be there.
5. In More → Themes, step through every phase and check all three branded
   presentations render legibly, especially at night.
6. Turn on Reduce Motion and Increase Contrast and repeat.
7. Raise Dynamic Type to an accessibility size and confirm nothing clips.

### 7. Watch, on real hardware

`FIRST_VERTICAL_SLICE.md` is explicit that Simulator validation is insufficient
for queued background transfers, and that is the one thing most likely to behave
differently in practice. On a physically paired iPhone and Watch:

- Complete a care action on the Watch with the phone app closed.
- Confirm the phone applies it once when next opened.
- Put the Watch in Airplane Mode, complete an action, restore connectivity, and
  confirm the action arrives exactly once.
- Complete the same care on both devices within a minute and confirm one care
  event exists.

## Exit criteria

From `IMPLEMENTATION_ROADMAP.md` and `FIRST_VERTICAL_SLICE.md`. Met means a
machine checked it and CI keeps checking it on every push.

- [x] The iPhone scheme compiles
- [x] Tests run and pass — 223 across 13 suites, plus 7 UI tests on a simulator
- [x] The flow works on Simulator — Today → plant → log care, end to end
- [ ] The Watch scheme compiles. The job exists but is `workflow_dispatch` only,
      because the runner ships no watchOS SDK and downloading it costs several
      gigabytes per run. Never yet executed.
- [ ] Flow works on a physical iPhone
- [ ] Queued Watch transfer verified on physically paired devices
- [ ] Local data survives relaunch. **Not** covered by the UI tests despite
      appearances: they launch with a fresh in-memory store precisely so a run
      cannot depend on the last one, which is the opposite of what this asks.
      By hand, or with a test that does not use `-SunnieUITesting`.
- [~] All three branded presentations render coherently. A UI test walks every
      phase and asserts the Sunnie Nights presentation appears, so the plumbing
      is checked; whether it *reads* well is a judgement no test makes.
- [~] Accessibility. Two automated: the primary action stays hittable at
      accessibility text sizes, and every interactive element carries a label.
      VoiceOver in use, Reduce Motion, and contrast remain by-hand checks.

Already satisfied by construction, and worth re-checking during review:

- [x] No direct SwiftData access from feature views
- [x] No duplicate rewards or care events, by design and by test
- [x] Content validated at test and script time
