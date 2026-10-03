# Handoff — continuing Sunnie Days in a new Claude Code session

Written Oct 3 2026, when the project moved from a cloud session to a local one.
Everything below was true at commit `2b2ca4c` on `main` and the docs commit after
it. Where something can drift, this says where to check rather than restating it.

## Where the project is

- **Everything is on `main`.** No open pull requests, no unmerged branches worth
  keeping. The old `claude/app-creation-b4rx6m` branch is fully merged and can be
  deleted.
- **Every target builds and every suite passes in CI** — iPhone app, widget,
  Watch app, shared Swift package, Android app, and the Kotlin contract tests.
  Counts and the run they came from are in `START_HERE.md`, and only there.
- **Open work is ranked in `Documentation/AUDIT_2026-10.md`.** Start there.

## The owner

Builds this for Vanessa, the one person who uses it. Not a developer:
explain in plain language, say what something means for Vanessa rather than how
it is implemented, and be direct about what is and is not done. "Done except for
X, Y, Z" is the format that works.

Has an Apple Developer account and **no Mac**.

## Where the work happens

The owner works from a local SSD and builds on a **RunPod Linux machine**.
GitHub holds the repository, and it is also **the only place the Apple targets
compile**: Apple builds require macOS and Xcode, which RunPod cannot provide. So
GitHub is not just a backup. Push to it whenever the iPhone, Watch, or widget
code needs checking, and to ship anything through TestFlight.

Setting up RunPod for the parts that do run on Linux:

- **Swift** — the toolchain from swift.org, or the `swift:6.1.2` Docker image
  that CI uses. Gives you `swift test` for `Packages/SunnieShared`.
- **JDK 17 or newer** — enough for `./gradlew :wire:test`.
- **Android SDK command-line tools**, with `ANDROID_HOME` set — needed for
  `:app:assembleDebug`. Without it, `settings.gradle.kts` skips `:app` on
  purpose and `:wire` still builds.
- **Python 3** — for the validators in `Tools/`.

A CPU pod is enough; nothing here uses a GPU.

## How to verify anything

There is no local Apple toolchain. That shapes everything.

| What | How | Where it runs |
|---|---|---|
| Shared Swift package | `cd Packages/SunnieShared && swift test` | Locally, if a Swift toolchain is installed; always in CI |
| Android rules (`wire`) | `cd Apps/Android && ./gradlew :wire:test` | Locally with a JDK (17+) |
| Android APK | `./gradlew :app:assembleDebug` | Needs an Android SDK; always in CI |
| Content, permissions, localization, contract coverage | `python3 Tools/validate_*.py` | Locally |
| iPhone app, widget, Watch app | — | **CI only** (`.github/workflows/ci.yml`, macOS) |

- CI runs on every push. A manual run (`gh workflow run ci.yml --ref <branch>`)
  also builds the Watch app on its own; every push already compiles it inside
  the iPhone build, because the iPhone app embeds it.
- When the iPhone job fails, read its **"Summarize diagnostics"** step first. It
  separates compile errors from test failures, including Swift Testing's, which
  never print `error:`.
- `gh run list`, `gh run view <id> --log-failed` are the quickest way in from a
  terminal.
- Pushing to a branch cancels that branch's in-progress CI run.

## Rules that are easy to break

All of `CLAUDE.md` binds. These are the ones a new session is most likely to
trip over:

- **ADR-033: there is no erase-everything control, and there must not be one.**
  The owner decided this. Do not raise it as a gap.
- **ADR-035: the Android app and backend are approved.** The backend carries game
  moves only. The rule fixtures in `Backend/contract` must be read by *both* the
  Swift and Kotlin test suites — `Tools/validate_contract_coverage.py` enforces it.
- **No third-party Swift packages.** The Android client's dependencies are listed
  in ADR-035; anything new on either side needs an ADR first.
- **Vanessa's dietary rule is no eggs**, enforced in `DietaryFilter.swift`.
- **Test counts live only in `START_HERE.md`.** Don't copy them elsewhere.

## What has actually gone wrong here, so it does not again

The defects in this codebase are almost never "it doesn't compile". They are
code that compiles and does something else:

- `#Predicate` bodies that type-check but translate to SQL that matches nothing
  (`!=` on an optional column, `.isEmpty`, `??`). Three were found and fixed.
- A cleanup routine checking the wrong record type, which would have deleted
  every recipe photo — **with a test that made the same mistake and passed.**
- A no-eggs filter that allowed egg noodles — **with a test asserting it was
  right.**

So: when a test passes, check it builds its inputs from the same source the app
uses (e.g. `Recipe.mediaOwner`), not from a hand-written guess.

The other recurring failure is **documentation stating things nobody verified.**
Docs claimed the Watch app compiled when no Watch job had run; a later session
"corrected" that to "never compiled", which was also wrong (it compiles inside
every iPhone build). Check the evidence — the CI log — before writing a status
claim, and tie numbers to a run ID.

## What is waiting on the owner

1. **Artwork** — starting now. Sunnie is drawn by `Apps/iOS/DesignSystem/SunnieAvatarView.swift`
   as a placeholder shape; that file is the only place Sunnie becomes pixels, so
   the real art swaps in there. `AssetsSource/ASSET_MANIFEST.md` lists every
   asset; `AssetsSource/FrontPageBrief/` is the brief for image generation.
2. **TestFlight setup** — `Documentation/TESTFLIGHT_SETUP.md`. The pipeline
   (`.github/workflows/testflight.yml`) is built but has never run. First build
   ships with Health, widget data, weather, and iCloud off (ADR-012).
3. **Where the game server lives** — `Backend/README.md`. Nothing is applied to
   any database.
4. **Tell Sunnie's speech fallback** — keep sending speech to Apple when
   on-device recognition is unavailable, or offer typing instead (audit M4).

## Suggested next work

In order, from the audit:

1. **H1 — a "Recently deleted" journal screen.** The app tells Vanessa a deleted
   entry can be restored for 30 days, but after the Undo banner there is nowhere
   to do it. `JournalRepository.deletedEntries()` and `restore(entryID:)` exist;
   only the screen is missing.
2. **M1 — move the Today front page's ~30 hardcoded strings into
   `Localizable.strings`.**
3. The small ones: L1 greeting fallback, L2 the last silent delete, L3 the unused
   photo-library permission, L4 stale comments.
4. When the artwork arrives: wire it into `SunnieAvatarView` and the asset
   catalog, and update `ASSET_MANIFEST.md`.

Work on a branch, open a pull request, merge when CI is green. Commit messages in
this repo explain *why*; keep doing that.

---

## Prompt to start the local session

Clone, open a terminal in the repo, start `claude`, and paste:

```
I'm continuing the Sunnie Days project, which until now was worked on in a
Claude Code cloud session. Read HANDOFF.md, then START_HERE.md, then
Documentation/AUDIT_2026-10.md, and CLAUDE.md is binding throughout.

I work from my SSD and build on a RunPod Linux machine. I don't have a Mac, so
the iPhone and Watch code only compiles in GitHub Actions — don't tell me
anything about those works unless CI shows it, and don't try to build them on
RunPod.

When you've read those, tell me in plain language where things stand and what
you'd suggest doing next, then wait for me before changing anything.
```
