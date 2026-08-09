# Sunnie Days — Product Integration and Reward System

## Product direction

Sunnie Days is one personal operating environment, not a bundle of separate utility apps.

Plants, travel, wellness, meals, games, journal, collections, Watch, widgets, and future capabilities are subsystems. The product the user experiences is Sunnie Days: a persistent personal world that understands what is happening across those subsystems and presents the right thing in context.

The design goal is therefore not "six competent apps in one container." It is one exceptional app whose underlying systems happen to cover several areas of life.

## Non-negotiable behavioral rule: no pressure or punishment

Sunnie Days must never use loss, guilt, disappointment, fear of missing out, emotional dependency, or punishment to drive engagement.

Forbidden patterns include:

- broken streaks or streak-loss messaging;
- points, levels, collectibles, access, or progress that decay because the app was not used;
- "you missed a day" framing;
- "Sunnie missed you," "Sunnie is sad," or any implication that Sunnie's emotional wellbeing depends on app use;
- repeated nagging because an optional task was ignored;
- countdowns designed to create artificial urgency;
- negative comparison against previous activity;
- punishment for declining a suggestion, notification, Health permission, or integration.

A period of non-use is simply a period with no new events. Nothing breaks. Nothing is lost. Nothing scolds the user on return.

## Positive progression

Progression is additive only.

Meaningful actions may award experience/points. Points never decrease. Earned rewards remain owned permanently. There is no revoke, expiry, decay, or missed-day penalty.

The system should reward breadth rather than prescribe a correct way to use Sunnie Days. A user who mainly travels, mainly cares for plants, mainly plays games, or uses several systems should all make meaningful progress.

Eligible reward classes include:

- Sunnie outfits and accessories;
- home decor and furniture;
- environmental variants and visual treatments;
- Sunnie animations, reactions, poses, and idle behaviors;
- sound packs and future voice variants;
- postcards, stamps, souvenirs, and destination keepsakes;
- themes and interface treatments;
- seasonal cosmetics;
- small gimmicks and hidden interactions;
- future room/home expansions where appropriate.

Rewards should increasingly change the lived app environment rather than exist only as entries in a collection screen. Progress should make Sunnie Days visibly more personal over time.

## Today is the operating layer

Today should become the primary contextual surface of Sunnie Days.

It should not mirror the navigation hierarchy. It should assemble what matters now from across the app and expose direct actions without requiring the user to decide which feature owns the information.

Examples:

- an upcoming trip can surface packing, plant coverage, destination time, weather, and saved memories as one travel context;
- a plant task can be completed directly from Today;
- a meal or grocery action can surface when relevant without requiring a trip through the More hierarchy;
- a daily game can appear as an optional activity without a streak or missed-day state;
- recent unlocks can appear as something new in Sunnie's world rather than as a demand to visit Collections.

Today should prioritize relevance, not module equality. Some days a feature may not appear at all.

## Context engine

Cross-feature combinations are a first-class product capability.

The app should develop a context layer that consumes typed domain events and summary providers, then produces context items that can be used consistently by Today, Sunnie, widgets, Watch, and notifications.

The context layer must remain read-oriented. It should not mutate another feature's state behind the user's back.

A context item should be able to express:

- why it is relevant now;
- what facts contributed to it;
- one primary action and, when necessary, one secondary action;
- whether it is informational, actionable, celebratory, or ambient;
- an expiry/relevance window when the underlying situation is time-bound;
- whether it is appropriate for a notification, widget, Watch, or only in-app presentation.

The context engine must never manufacture urgency. Urgency must come from an actual user-defined or externally meaningful deadline.

## Sunnie as the universal character layer

Sunnie should be the connective tissue between systems, not a mascot pasted onto separate screens.

Sunnie's expression, pose, environment, dialogue, outfit, and small behaviors may react to the current context. Reactions must remain optional, concise, and nonjudgmental.

Sunnie may acknowledge completed actions or new rewards. Sunnie must never express disappointment about inactivity or ignored suggestions.

Over time, richer behavior should come primarily from:

- more contextual expressions and poses;
- environmental interactions;
- more equipped/owned items appearing naturally in the scene;
- destination and time-of-day behavior;
- subtle idle activities;
- context-specific reactions;
- optional voice/audio variants.

## Cross-feature integration

A feature should contribute to the shared world whenever doing so creates a coherent connection rather than a novelty hook.

Examples:

- saving a travel memory can grant and display a destination keepsake;
- a newly added plant can eventually appear decoratively in Sunnie's environment;
- a completed game can unlock a cosmetic object;
- a destination can influence Sunnie's home scene while the trip is active;
- a plant coverage plan can appear as part of travel preparation rather than only inside Jungle;
- wellness state can influence message sensitivity without becoming a score or judgment;
- meal planning can integrate with travel and packing where useful.

The test for every integration is: does this make Sunnie Days feel like one world, or does it merely create another cross-link?

## Navigation principle

Navigation remains available and predictable, but the user should not be forced to traverse module hierarchy for common contextual actions.

Today, widgets, Watch, Sunnie Home, notifications, and App Intents should deep-link directly to the relevant action or record.

The feature tabs are durable organizational roots. They are not the product model that every interaction must expose.

## Event model

Typed domain events are the shared vocabulary of the application.

Meaningful actions should emit stable events when other systems may legitimately need to react. Existing progression events and domain events should be extended rather than creating feature-specific notification mechanisms.

Events must describe what happened, not what another feature should do about it.

Good:

- plantCareLogged
- tripCreated
- tripMemorySaved
- wellnessCheckInRecorded
- mealsPlanned
- dailyPuzzleCompleted
- rewardGranted

Bad:

- refreshTodayPlantCard
- showSunnieTravelMessage
- unlockLampOnHomeScreen

Consumers decide how to react.

## Behind-the-scenes native infrastructure

The revamp should also improve Sunnie Days through system-wide infrastructure that Vanessa does not need to think about as a separate feature. These utilities should make every surface more intelligent, current, searchable, and integrated while preserving the local-first privacy model.

### 1. Unified Context Engine

This is the highest-priority infrastructure addition.

The engine should assemble a read-only `CurrentContext` from the existing summary providers, typed events, time engine, preferences, travel state, plant state, meals, wellness, games, progression, calendar/weather availability, and device capabilities.

Today, Sunnie Home, Sunnie dialogue, widgets, Watch, App Intents, and notifications should consume this shared context rather than independently reconstructing what is happening.

The context engine must produce facts and ranked opportunities, not silently perform user actions.

### 2. Native Foundation Models integration

Where the operating system and device support Apple's Foundation Models framework, Sunnie Days should be able to use it as an optional intelligence layer behind the existing deterministic systems.

Appropriate uses include:

- turning natural-language input into structured app data;
- summarizing several already-known facts into concise contextual copy;
- interpreting what the user is asking Sunnie to find or do;
- selecting among explicitly exposed app tools/actions;
- generating structured output for a deterministic feature to validate before use.

The model must not become the source of truth for schedules, health facts, progression, permissions, rewards, or persisted records. Existing deterministic engines and repositories remain authoritative.

The model must never silently mutate user data. Any action it selects must pass through the same use case and confirmation rules as a manually initiated action.

Foundation Models support is capability-gated. Core Sunnie Days behavior must remain fully functional without it.

### 3. Background refresh and maintenance orchestration

Use the native background-task system to opportunistically keep derived state current while the app is not foregrounded.

Suitable background work includes:

- refreshing the shared context snapshot;
- rebuilding widget snapshots;
- reconciling additive reward unlocks;
- maintaining search indexes;
- refreshing noncritical derived travel information when permitted;
- performing safe local housekeeping already designed to be idempotent.

Background execution is best-effort and scheduled by iOS. No critical deadline or safety-sensitive behavior may depend on a background task running at an exact time.

### 4. Core Spotlight as a private universal index

Sunnie Days should expose appropriate local entities to Core Spotlight so the user's information can behave like one searchable personal space rather than several databases.

Candidate entities include plants, trips, places, memories, recipes, games, collections, and other non-sensitive records that are appropriate for system search.

The app should also maintain its own unified in-app search surface using the same entity vocabulary. Search results should deep-link directly to the relevant record or action.

Sensitive categories such as journal and wellness content require a deliberately stricter indexing policy and should not be indexed merely because the framework permits it.

### 5. Expanded App Intents layer

The existing App Intents implementation should become the common system-facing action layer for useful Sunnie Days capabilities.

Where appropriate, the same intents and entities should support Siri, Shortcuts, Spotlight actions, widgets, Watch handoff, and hardware/system entry points exposed by iOS.

This prevents each Apple integration from inventing a parallel action API and makes system integrations another presentation of the same underlying Sunnie Days use cases.

### 6. Central Capability and Permission Broker

Introduce one capability service that describes what the current device and user configuration can actually provide.

It should normalize availability and authorization state for capabilities such as HealthKit, Watch connectivity, notifications, calendar, location, weather, Foundation Models, background refresh, widgets/App Groups, camera/photos, and other optional native integrations.

Feature code should ask the broker for capability state rather than independently duplicating availability logic.

The broker should support graceful substitution. An unavailable integration removes or simplifies the related enhancement; it must not make the underlying Sunnie Days function unusable.

### Infrastructure principles

These utilities are infrastructure, not new product silos.

They must follow these rules:

- no new top-level tab merely because an infrastructure service exists;
- local-first and offline-capable core behavior remains mandatory;
- intelligence assists deterministic systems rather than replacing their rules;
- optional Apple integrations degrade cleanly when unavailable or declined;
- no background system may create pressure, nagging, or artificial urgency;
- derived caches and indexes must always be reconstructable from authoritative data;
- permissions are requested only when the user reaches a capability that genuinely needs them;
- privacy-sensitive data receives stricter treatment than ordinary app entities.

### Infrastructure implementation priority

1. Unified Context Engine and `CurrentContext` contract.
2. Central Capability/Permission Broker.
3. Background context/widget/reward maintenance.
4. Core Spotlight + unified entity/search vocabulary.
5. Deeper App Intents coverage using the same use cases.
6. Foundation Models integration after the deterministic context/tool boundaries are established.

Foundation Models deliberately comes after the context and action contracts. The AI layer should plug into a coherent Sunnie Days architecture, not become the architecture.

## Product-wide screen test

Every screen should be reviewed with this question:

> Does this feel like Sunnie Days, or like a separate app embedded inside Sunnie Days?

A screen that feels separate should be improved through shared visual language, context, direct navigation, Sunnie presence where appropriate, common reward/event infrastructure, and tighter integration with Today and Sunnie Home. It should not be made more "integrated" merely by adding links to other modules.

## Near-term implementation order

1. Remove stale module-placeholder behavior from Today and expose already-built systems as part of one active world.
2. Add a unified Today/context summary layer rather than having Today directly query feature storage.
3. Surface positive progression and recent unlocks in Today/Sunnie Home.
4. Expand cross-feature context beginning with Travel + Jungle, Travel + Meals, and progression + Sunnie Home.
5. Add the central capability broker and background context maintenance.
6. Add unified entity search/Spotlight and deepen App Intents.
7. Add Foundation Models only after its tools and deterministic boundaries are defined.
8. Enrich Sunnie's reactive behavior and environmental state.
9. Perform a screen-by-screen integration pass.
10. Only after this work should a new major feature category be considered.

## Acceptance criteria

The integration effort is successful when:

- a normal session can be completed largely from context without mentally switching among modules;
- Today no longer contains placeholders for already-built systems;
- rewards are visible in the world and never depend on maintaining activity;
- no feature can remove previously earned progress;
- inactivity produces no negative state or messaging;
- multiple feature systems can contribute to a single coherent context item;
- Sunnie's behavior reflects the current world without becoming needy or intrusive;
- the application still works offline for all core personal data and functions;
- optional native intelligence and system integrations improve the app without becoming prerequisites;
- system search, widgets, Watch, Siri/Shortcuts, and Today increasingly expose the same underlying entities and actions rather than parallel implementations.
