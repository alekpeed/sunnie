# Claude Code Operating Instructions — Sunnie Days

## Mission

Implement Sunnie Days faithfully from the documents in this repository. Optimize for correctness, consistency, maintainability, privacy, and visual coherence. Do not optimize for speed by skipping architecture, tests, migrations, accessibility, or documented behavior.

## Non-negotiable product facts

- The app is **Sunnie Days**.
- It is a fully native iOS application written in Swift and SwiftUI.
- The Apple Watch companion is also native Swift and SwiftUI.
- Sunnie is a **young, baby-faced, highly cartoony male sloth** based on the canonical reference images.
- Sunnie must not be redesigned as tall, mature, realistic, lanky, or adult-proportioned.
- The initial app is 2D. Voice, advanced animation, and 3D are future extensions.
- The public day-cycle labels are **Sunnie Days**, **Sunnie Afternoonies**, and **Sunnie Nights**.
- Never introduce “Sunnie Mornings” or “Sunnie Evenings.”
- Vanessa never sees MIDI import or MIDI-management tools. Music ingestion is creator-side only.
- The app must never use sarcasm, shame, guilt, hostility, threats, or punitive streak language.
- Vanessa’s dietary rule is no eggs.
- Core app data must work offline.
- HealthKit and Apple Watch are optional integrations, not prerequisites for using the app.

## First actions in a new repository

1. Read `README_FIRST.md` and `MASTER_SOURCE_OF_TRUTH.md` fully.
2. Read the technical architecture and implementation roadmap.
3. Inventory the repository before changing files.
4. Create or update `ARCHITECTURE_DECISIONS.md` when a locked decision must change.
5. Implement only the current approved phase.
6. Run tests before claiming completion.

## Implementation discipline

- Work in small vertical slices.
- Present a concise plan before a substantial change.
- Do not create parallel half-finished feature systems.
- Do not bypass repository or service boundaries from SwiftUI views.
- Do not place business logic in views.
- Do not hardcode theme colors, Sunnie dialogue, destination content, game content, or reward definitions inside screens.
- Use stable identifiers for persisted records and content definitions.
- Treat persistence migrations as required product work.
- Make repeated operations idempotent, particularly rewards, Watch actions, notification actions, and sync imports.
- Preserve offline functionality.
- Maintain accessibility while implementing each screen, not as a final retrofit.

## Technology constraints

Use:

- Swift
- SwiftUI
- Observation (`@Observable`) for feature state where appropriate
- Swift concurrency (`async`/`await`)
- SwiftData behind repositories
- CloudKit/private iCloud synchronization where specified
- HealthKit
- WatchConnectivity
- WidgetKit and App Intents where specified
- EventKit
- MapKit
- WeatherKit
- UserNotifications
- AVFAudio and Core MIDI only through the audio layer

Do not add a third-party package without an Architecture Decision Record and explicit approval. Do not introduce a cross-platform UI framework.

## Architecture rule

The application is a modular monolith. Feature folders are isolated by protocol boundaries. The app target composes dependencies. A shared local Swift package contains platform-neutral domain types, content schemas, identifiers, and shared utilities used by iPhone, Watch, widgets, and tests.

Feature modules must not import one another to mutate state. Cross-feature behavior occurs through use cases, repositories, summary providers, and typed domain events.

## Assets

- Use the canonical Sunnie images only as appearance references.
- Do not crop generated mockups into production UI assets unless explicitly approved.
- When a required production asset does not exist, create a clearly named placeholder and record it in the asset manifest.
- Do not silently invent a new Sunnie design.
- Context images may guide environment, wardrobe, or pose, but not age or proportions.

## Copy and tone checks

Every user-facing string must pass these tests:

- Is it kind?
- Is it nonjudgmental?
- Does it avoid urgency unless urgency is real and user-enabled?
- Does it avoid implying that Sunnie is disappointed?
- Does it avoid medical diagnosis or unsupported certainty?
- Does it remain useful if the user has ignored previous reminders?

The nickname “Noonies” is eligible in approximately 1 in 20 appropriate Sunnie messages. It is never used in warnings, health permissions, errors, privacy copy, or serious travel notices.

## Testing requirements

For each feature:

- Unit-test business rules.
- Test repository behavior with an in-memory store.
- Test idempotency.
- Test empty, loading, error, offline, and denied-permission states.
- Test all three branded day-cycle presentations.
- Test Dynamic Type, VoiceOver labels, reduced motion, and sufficient contrast.
- Add UI tests for critical flows.
- Test WatchConnectivity on paired physical devices before release; Simulator-only validation is insufficient for queued background transfers.

## Completion reporting

When a task is complete, report:

1. Files changed
2. Behavior implemented
3. Tests run and results
4. Known limitations
5. Any documentation or ADR changes
6. The next dependency-safe task

Never claim a feature is complete when it has only placeholder logic, an untested happy path, or unsolved data migration behavior.
