# Compile-risk review

A pass over the places most likely to need attention the first time this
codebase meets a compiler, ordered so the ones that cascade come first.

> **Update after the first real compile.** The shared package now builds and
> passes 460 tests on Linux (ADR-032). That run found three genuine defects —
> `ColorValue` JSON encoding, travel coverage for already-overdue tasks, and a
> `some`/`any RandomSource` mismatch — all now fixed with regression tests. It
> also confirmed the biggest claim below: strict concurrency produced warnings,
> not errors. The iPhone app, widget, and Watch target have since compiled in
> macOS CI; §1 records what the compiler actually found.
>
> **Second update — the app targets have now been parsed.** All 142 files pass
> `swiftc -parse` (`./Tools/parse_check.sh`, wired into CI). That is a real
> result and a narrow one: it proves the files are well-formed Swift, and proves
> nothing about whether they compile. Parsing resolves no imports, looks up no
> names, and checks no types.
>
> The earlier Linux-only attempt could not settle §1 because the localization
> API is Apple-only. The later Xcode build did settle it; see §1 for the result.

**This is not a list of known bugs.** It is a list of places where the code makes
an assumption a type checker has never confirmed. Most will be fine. The point is
to shorten the first build day by saying where to look when something breaks,
rather than reading 64,000 lines from the top.

Three things were found and fixed while writing this; they are marked **FIXED**
and described so you know what changed and why.

---

## The good news first

Some whole categories of problem were checked and came back clean.

| Checked | Result |
|---|---|
| `@Model` property types across all 8 schema versions | All 366 are SwiftData-native — `String`, `Int`, `Double`, `Bool`, `Date`, `UUID`, `Data`, `[String]`, `[UUID]`. No custom types, no relationships, nothing needing a transformer. |
| All 119 `#Predicate` bodies | Simple comparisons and boolean logic. One risky construct, now fixed (§2). |
| Shared package imports | `Foundation` and `os`, nothing else. No SwiftUI, no SwiftData, no `Bundle.main`. **This row was wrong** — it read "genuinely platform-neutral" while `os` is Apple-only, so the package could not build off Apple at all. Both Apple-only touch points are now `canImport`-guarded (ADR-032), and it is neutral in fact rather than in claim. |
| `.onChange(of:)` | All three use the two-parameter iOS 17+ form. Correct for an iOS 18 target. |
| `try!`, `as!` | Zero of each. |
| `fatalError` | Two, both genuinely unrecoverable (§6). |
| Environment injection | `AppDependencies`, `AppState`, `AppRouter`, `WatchModel` are all `@MainActor @Observable`, which is what `@Environment(X.self)` needs. |
| SwiftUI body size | Largest is 129 lines with a 7-modifier chain. Long, but broken into sub-views — not the single-huge-expression shape that causes type-checker timeouts. |

**Strict concurrency will not block you.** `SWIFT_STRICT_CONCURRENCY = complete`
sounds alarming, but the project is in **Swift 5 language mode**, where data-race
diagnostics are *warnings*. They will be noisy. They will not stop the build. If
they drown out real errors, drop `Config/Shared.xcconfig` to
`SWIFT_STRICT_CONCURRENCY = targeted` while you work — then put it back, because
ADR-010 is explicit that this is a stepping stone to Swift 6 rather than a
permanent setting.

---

## 1. Runtime-key localization — 34 call sites, highest count in the codebase

> **Settled by a real compiler.** The app target has now been built with Xcode
> 26.3 on a GitHub macOS runner, and the compile half of this section has an
> answer: **`String(localized: .init(runtimeKey))` type-checks.** Those call
> sites compiled without complaint, so the "missing argument label" outcome
> guessed at below does not happen.
>
> What did fail was narrower and was not predicted here at all:
> `String(localized:defaultValue:)` types its *key* as `StaticString`. That
> broke two things — two sites passing a runtime key alongside a `defaultValue`,
> and sixteen sites interpolating a value into the key itself. Both are fixed;
> `Tools/validate_localization_keys.py` keeps the second from returning, and
> `LocalizationKeys.text(_:fallback:)` is the supported way to resolve a runtime
> key, wrapping `Bundle.localizedString(forKey:value:table:)`.
>
> **The second half below is still open**, and is the more interesting one: these
> calls compile, but whether a runtime key actually resolves to a translation
> rather than returning the key itself is a runtime question that no build
> answers. It needs a device or a simulator run.

**Look here first if you see a wall of errors in one shape.**

Thirty-four places do this:

```swift
String(localized: .init(pattern.displayNameKey))
```

`String(localized:)` takes a `String.LocalizationValue`. The `.init(…)` is
constructing one from a **runtime** `String`, not a literal. Two separate
concerns:

**Will it compile?** `String.LocalizationValue` conforms to
`ExpressibleByStringInterpolation`, whose initializer is `init(stringLiteral:)` —
labelled. Whether an unlabelled `init(_ value: String)` is also available is
exactly the kind of thing I cannot confirm without a compiler. If it is not, all
34 fail with *"missing argument label 'stringLiteral:'"* and the fix is
mechanical.

**Will it work?** This is the more interesting half, and it applies **even if it
compiles**. `String(localized:)` is designed around literals so the tooling can
extract them. A value built at runtime is not extracted into a String Catalog,
and lookup with a variable key is not a supported pattern. So these may compile
and then return the key itself rather than the translation.

**The reliable replacement**, if either half bites — one helper, then a
find-and-replace:

```swift
/// Localizes a key that is only known at run time.
///
/// Content packs store localization *keys*, so the actual string is chosen by
/// data rather than written in source. `String(localized:)` is built around
/// literals it can extract at build time and is not the right tool for that;
/// this is.
func localized(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}
```

`value: key` rather than `value: nil` matters: a missing key then renders as the
key itself, which is visible and debuggable, instead of an empty string that
looks like a layout bug.

The 89 uses of `LocalizedStringKey(runtimeString)` in SwiftUI views are a
different API and are fine — `Text(LocalizedStringKey(…))` does resolve a runtime
key correctly.

## 2. FIXED — optional chaining inside a `#Predicate`

`SwiftDataWellnessRepository.entries(matching:limit:)`, the journal search.

```swift
// was
($0.title?.localizedStandardContains(trimmed) ?? false)
// now
($0.title ?? "").localizedStandardContains(trimmed)
```

Identical semantics — no title means no match — but optional-chaining a *method
call* inside `#Predicate` is one of the constructs the macro handles least
reliably, and it fails at **run time** with "could not be converted to a
predicate expression" rather than at compile time. That makes it the worst kind
of bug to find on a device: journal search would simply throw, on a screen whose
other 118 predicates all work.

The remaining 118 are plain comparisons and need nothing.

## 3. FIXED — HealthKit purpose strings were missing

`Apps/iOS/Resources/Info.plist` had no `NSHealthShareUsageDescription` or
`NSHealthUpdateUsageDescription`, while `SunnieHealthService` calls
`requestAuthorization`. **iOS terminates the process** — not a denied prompt, a
kill — so the app would have crashed the first time anyone enabled Health on a
device.

Both strings are now present, and `Tools/validate_permissions.py` checks the
whole class of problem: it maps permission-gated APIs to required plist keys
across all three targets. It was verified to fail on the original state, so it is
not a vacuous check.

The audit also confirmed what does **not** need fixing: calendar, microphone,
camera, and photo keys are all present and correct; `CoreLocation` is only used to
build a `CLLocation` from a trip's stored coordinates for WeatherKit and never
requests the user's location, so no location key is needed; and neither the Watch
nor the widget target touches a permission-gated framework.

## 4. FIXED — a non-isolated mutable static

`PlantEntity.defaultQuery` was `static var`; it is now `static let`. `AppEntity`
only requires a getter. A mutable non-isolated static is the exact shape strict
concurrency objects to — a warning today, an error the moment this moves to
Swift 6.

The only other global mutable state is `IntentDependencies.shared`, which is
inside a `@MainActor enum` and therefore already safe.

## 5. The five `@unchecked Sendable` types

These opt out of the compiler's checking, so the compiler will not tell you if
they are wrong. Each has a written argument for why it is safe; the arguments are
worth reading rather than trusting.

| Type | The claim |
|---|---|
| `NoiseEngine`, `ProceduralAudioEngine` | A render-state box mutated only on the audio thread, plus a `Double` volume written from the main actor. A torn `Double` read is not a real hazard on any platform this ships to. |
| `WatchConnectivityService`, `WatchConnectivityClient` | `WCSession` delegate callbacks arrive on an arbitrary queue and are immediately hopped onto an actor. |
| `SunnieHealthService`, `NotificationService` | Wrap Apple types that are thread-safe but not annotated `Sendable`. |

The two audio ones also claim their render blocks **allocate nothing and lock
nothing**. That is a design argument, not a measurement — nothing has profiled
them. If you hear breakup under load on an older device, that claim is where to
start, and the Time Profiler will settle it in minutes.

## 6. The two `fatalError`s — and the first crash you are likely to see

Both are in the persistence bring-up path, and both are defensible: an in-memory
container failing to build means the *schema itself* is malformed, which no
runtime handling can fix.

Practically, this means: **if the eight schema versions have a problem, the app
crashes on launch with `SwiftData schema is invalid: …`.** That is a good
outcome. The message names the real cause instead of surfacing as a mysterious
empty screen. Do not treat it as a bug in the crash handling.

The on-disk path is gentler — it falls back to in-memory for the session and logs
it, so a corrupt store degrades rather than blocks.

## 7. Package resources — already defended

`Package.swift` uses `.process("Resources")`, which flattens directory structure
in the built bundle. `ContentRegistry.decode` looks up with `subdirectory:
"Content"` **and** falls back to a bare lookup, so it resolves either way. No
change needed — noted only because "the content pack won't load" is a plausible
early symptom and this is the first place anyone would look.

## 8. Where a type checker is most likely to disagree

Ranked by how much of the codebase depends on the assumption. No specific error
is predicted — these are simply the widest blast radii.

1. **Repository protocol signatures.** ~40 methods in `Protocols/Repositories.swift`
   and `WellnessRepositories.swift`, each implemented once and called from several
   use cases. One wrong signature produces errors at the conformance *and* at
   every call site, which reads like ten problems instead of one. If errors seem
   to be everywhere, check whether they share a protocol.
2. **`ModelMapping` domain↔model conversions.** 29 files, mechanical, and the
   place a renamed property surfaces as a cascade.
3. **App Intents.** `AppEntity`, `EntityQuery`, and `AppIntent` have particular
   conformance requirements and evolve between SDKs. One file, self-contained.
4. **The widget target.** Its Xcode target was hand-written into `project.pbxproj`
   rather than added by Xcode. The structure audits clean — 89 objects defined and
   referenced, sections paired, no duplicate ids — but structural validity is not
   the same as Xcode accepting it. If the target misbehaves in ways that make no
   sense, delete it and re-add it through Xcode; the source files are fine.
5. **`Date.FormatStyle` in the Watch clocks.** `WatchFeatureScreens.swift` passes a
   `timeZone` into the format style, which is the difference between showing the
   destination's time and showing local time under a "There" label. Worth an
   actual look on a wrist rather than trusting it reads right.

## 9. Suggested order

1. `cd Packages/SunnieShared && swift build` — a third of the code, seconds per
   cycle, no UI in the way.
2. `swift test` there — 460 tests, all passing since ADR-032.
3. Open the project; build **SunnieDays** for the Simulator only.
4. Fix by *shape*, not by file. Errors will cluster: fix one protocol signature
   and thirty errors go at once. Recompiling after each cluster beats working
   down the list top to bottom.
5. Watch and widget targets last. Neither blocks the phone app.

## 10. What this review could not check

Said plainly, so the list is not mistaken for coverage:

- **Physical-device behavior.** Simulator builds type-check the Apple API usage,
  but cannot prove Health, camera, haptics, or paired Watch behavior.
- SwiftUI layout, and whether any view renders as intended.
- The Watch target compiles in the manual CI job after its watchOS SDK download,
  but paired-device behavior remains untested. The shared package's 460 tests and
  the app target's 223 tests plus 7 UI tests pass.
- Migration against real data. There is no V1 store in existence to migrate from,
  and ADR-017's namespace freeze is still owed. This remains the
  highest-consequence untested area in the project.
