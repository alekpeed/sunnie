# Sunnie Days — start here

A private iPhone app built for one person, with an Apple Watch companion, home
screen widgets, and a small Android app for playing its games together.
**All of it builds, and every automated test passes.** What remains is artwork,
testing on real devices, and a short list of unfinished features — all listed
below, nothing hidden.

There are two halves to this document. **Part 1 is for the app's owner** and
assumes no technical knowledge. **Part 2 is for the developer** and assumes
plenty.

---

# Part 1 — For the owner

## What this is

An app for looking after houseplants, wellbeing check-ins and a journal, travel
planning, meals, puzzle games, and a collection of things you unlock over time —
all fronted by a cartoon sloth called Sunnie.

## The honest status

This table is the **only** place in the project that records test results. Every
other document links here instead of copying numbers, because copied numbers
drift — that is how an out-of-date claim spread through these documents before.

| Part | Status | Evidence |
|---|---|---|
| Shared logic (the rules, no screens) | Builds; **485 tests pass** on Linux and macOS | CI run 37158041394, Oct 3 2026 |
| iPhone app and widgets | Builds; **231 app tests and 22 screen tests pass** in the iPhone simulator | same run |
| Apple Watch app | Builds, with no errors | same run — and inside every iPhone build since Aug 11, because the iPhone app includes it |
| Android game app | Builds into an installable file; **33 rule tests pass** | same run — the file is attached to it |

Every number above is a count of tests that actually ran and passed, not an
estimate. They are tied to one run so they stay true as a record even after later
work adds more tests.

## What's left

**Things only you can do:**

1. **Sunnie's artwork.** Sunnie is currently drawn as a simple placeholder shape,
   and every other picture in the app is a placeholder too. When the artwork is
   ready, one file changes and nothing else does. The full list of pictures
   needed is in `AssetsSource/ASSET_MANIFEST.md`.
2. **Put it on Vanessa's iPhone.** The TestFlight setup is six steps in
   `Documentation/TESTFLIGHT_SETUP.md`, done once with your Apple account.
3. **Decide where the game server lives**, so the Android app can play against
   the iPhone. The choice and what each option costs are in `Backend/README.md`.

**Things worth knowing about the first TestFlight build:** Apple Health,
home-screen widget contents, weather, and iCloud sync will be switched off. They
need extra Apple account setup that is deliberately left until the basics are
proven (ADR-012). Everything else works without them.

**Gaps found in the October 2026 audit** are listed, with priorities, in
`Documentation/AUDIT_2026-10.md`. The most important: a deleted journal entry
can be brought back for thirty days, and the app says so — but after the
immediate "Undo" button disappears, there is no screen to do it from.

## Known-unfinished on purpose — do not "fix"

- **There is no "delete everything" button.** Your decision (ADR-033): deleting
  the app is the erase-everything path, and one tap that destroys years of
  journal entries is the wrong thing to offer on a bad night.
- **No composed music yet.** Rain, crickets, and the other background sounds do
  work — the app generates them itself.
- **iCloud sync is off** until it can be tested properly.
- **Nothing plays sound when the app opens.** A design choice.

## One thing to agree before you send this anywhere

This app was built for a specific person. The written specification includes her
name, her dietary requirement, and the design of mood and health tracking
intended for her. There are no passwords or security keys in here, but it is
personal. Agree with anyone you share it with where it gets stored and who sees
it.

## What's in here

| Folder or file | What it is |
|---|---|
| `START_HERE.md` | This document, and the only record of test results |
| `HANDOFF.md` | How to continue in a new Claude Code session, with a prompt to paste |
| `Documentation/AUDIT_2026-10.md` | What the October 2026 audit found and what remains |
| `REVIEW_PACKET.md` | A deeper orientation for a developer |
| `Documentation/` | The full written specification — what the app should do and why |
| `Apps/iOS`, `Apps/Watch`, `Apps/Widgets` | The Apple apps |
| `Apps/Android` | The Android game app (ADR-035) |
| `Packages/SunnieShared` | The shared rules both Apple apps use |
| `Backend/` | The game server's design, and rule tests both phones share |
| `ARCHITECTURE_DECISIONS.md` | Why things were built the way they were |

---

# Part 2 — For the developer

## The short version

Native Swift/SwiftUI iPhone app with a watchOS companion and a widget extension:
a modular monolith around one local SPM package, with **no third-party packages**.
iOS 18 / watchOS 11, Swift 5 language mode with
`SWIFT_STRICT_CONCURRENCY = complete`.

Plus a native Android client for turn-based games (ADR-035): Kotlin and Compose,
with the game rules in a pure-JVM `wire` module held to the Swift implementation
by shared fixtures in `Backend/contract`. Its dependencies are recorded in
ADR-035.

All targets compile in CI and all suites pass — see the table in Part 1, which is
the one place counts live.

## Where to start

```bash
cd Packages/SunnieShared && swift test          # any machine, Linux included
cd Apps/Android && ./gradlew :wire:test          # any machine with a JDK
```

Both run without a Mac, an Android SDK, or a developer account. The shared Swift
package is about a third of the codebase and holds the domain logic; the `wire`
module holds the rules the Android client must agree on. Then use the `SunnieDays`
scheme for the iPhone simulator, which also builds the Watch app it embeds.

Signing is deliberately unconfigured and entitlements ship commented out
(ADR-012), so a fresh clone builds with no Apple account. `Config/*.xcconfig` is
where that changes.

## Read these, in this order

| Document | Why |
|---|---|
| `ARCHITECTURE_DECISIONS.md` | 35 ADRs. When code looks wrong, the argument for it is usually here — and several things that look like gaps are decisions (ADR-033 above all). Disagreeing is a legitimate finding; not knowing the argument existed is wasted time. |
| `Documentation/AUDIT_2026-10.md` | Open findings, ranked, with file references. |
| `Documentation/DEVICE_BRING_UP.md` | Clone → device: entitlements, App Group identifiers, and symptoms that look like bugs but are configuration. |
| `Backend/README.md` | The multiplayer backend: what is decided, what is not, and the privacy boundary it must not cross. |

## Things worth knowing

**CI is the source of truth, and its diagnostics are summarised.** The iPhone
job's "Summarize diagnostics" step separates compile errors from test failures —
including Swift Testing's, which do not print `error:` — so read that step before
the raw log.

**The class of bug this codebase actually has** is code that type-checks and
means something else when it runs. Three `#Predicate` bodies compiled into SQL
that silently matched nothing (an optional compared with `!=`, a `.isEmpty`, a
`??`); a media sweep would have deleted every recipe photo because it checked
the wrong owner type, with a test that agreed with it; a no-eggs filter allowed
egg noodles, with a test that agreed with that too. When a test passes, check it
was built from the same source of truth as the code — not hand-written to match.

**The Watch app is not a separate concern.** `SunnieDays` depends on and embeds
`SunnieDaysWatch`, so a Watch compile error fails the iPhone job.

## The highest-consequence untested area

Eight SwiftData schema versions, all additive. Every prior schema is now opened
at the current version in a test, but only as an **empty** store — no migration
has run against real data. The failure mode would be silent data loss on a
device rather than a crash. ADR-017 also records a schema-namespace freeze that
is still owed.

## Repository access

The repository is private on GitHub. Ask the owner for access.
