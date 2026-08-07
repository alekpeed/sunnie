# Build and Verify

## Read this first

**The shared package is compiled and tested. The app targets are not.**

- `Packages/SunnieShared` **builds and passes 441 tests** on Linux with Swift
  6.1.2 (ADR-032). Run it anywhere: `cd Packages/SunnieShared && swift test`.
- The iPhone app, the Watch app, and the widget extension have **never been
  built**. They need Xcode, which this project has never had access to.
- No screen has been rendered, on a simulator or a device.
- The app-side tests — roughly 220 of them — have never been executed.

Getting the shared package to compile found three defects that no amount of
static checking had caught: `ColorValue` encoding as an object against content
packs written as bare strings (which silently reduced the app to one theme),
travel coverage dropping tasks already overdue at departure, and a nickname
helper that was uncallable by its only callers. All three are fixed and have
regression tests.

`CLAUDE.md` says never to claim a feature is complete when it has only a
placeholder or an untested happy path. This document is that disclosure. Treat
everything here as a first draft that compiles only once you have made it
compile.

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

## Exit criteria not yet met

From `IMPLEMENTATION_ROADMAP.md` and `FIRST_VERTICAL_SLICE.md`, still open:

- [ ] iPhone and Watch schemes compile
- [ ] Tests run and pass
- [ ] Flow works on Simulator and a physical iPhone
- [ ] Queued Watch transfer verified on physically paired devices
- [ ] Local data survives relaunch
- [ ] All three branded presentations render coherently
- [ ] Accessibility pass: Dynamic Type, VoiceOver, Reduce Motion, contrast

Already satisfied by construction, and worth re-checking during review:

- [x] No direct SwiftData access from feature views
- [x] No duplicate rewards or care events, by design and by test
- [x] Content validated at test and script time
