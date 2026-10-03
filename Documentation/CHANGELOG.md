# Document Pack Changelog

## 2026-10-03 — Everything merged; first full audit

- All outstanding branches and pull requests brought into `main` (PR #11);
  PRs #1, #5, #8, #9 closed with explanations.
- Every target builds and every suite passes in CI; results recorded only in
  `START_HERE.md`.
- Android game companion and shared rule contracts added (ADR-035), which
  amends the Android and backend non-goals in FUTURE-001,
  `RELEASE_SCOPE_AND_NON_GOALS.md`, `GAMES_AND_FUTURE_MULTIPLAYER.md` §9, and
  `START_HERE_PROMPT.md`.
- Code audit recorded in `AUDIT_2026-10.md`.
- `HANDOFF.md` added for moving the project to a local Claude Code session.

## 1.0 — 2026-07-28

- Consolidated the complete Sunnie Days concept into one coherent Claude Code package.
- Locked native Swift/SwiftUI implementation.
- Locked canonical young Sunnie design from the original reference images.
- Corrected branded day-cycle naming to Sunnie Days, Sunnie Afternoonies, and Sunnie Nights.
- Removed Sunnie Mornings and Sunnie Evenings from the source of truth.
- Defined current 2D scope and future animation, voice, 3D, Android, caretaker, and LifeOS extension boundaries.
- Defined feature specifications, architecture, data, sync, testing, delivery, and acceptance criteria.
