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

## Product-wide screen test

Every screen should be reviewed with this question:

> Does this feel like Sunnie Days, or like a separate app embedded inside Sunnie Days?

A screen that feels separate should be improved through shared visual language, context, direct navigation, Sunnie presence where appropriate, common reward/event infrastructure, and tighter integration with Today and Sunnie Home. It should not be made more "integrated" merely by adding links to other modules.

## Near-term implementation order

1. Remove stale module-placeholder behavior from Today and expose already-built systems as part of one active world.
2. Add a unified Today/context summary layer rather than having Today directly query feature storage.
3. Surface positive progression and recent unlocks in Today/Sunnie Home.
4. Expand cross-feature context beginning with Travel + Jungle, Travel + Meals, and progression + Sunnie Home.
5. Enrich Sunnie's reactive behavior and environmental state.
6. Perform a screen-by-screen integration pass.
7. Only after this work should a new major feature category be considered.

## Acceptance criteria

The integration effort is successful when:

- a normal session can be completed largely from context without mentally switching among modules;
- Today no longer contains placeholders for already-built systems;
- rewards are visible in the world and never depend on maintaining activity;
- no feature can remove previously earned progress;
- inactivity produces no negative state or messaging;
- multiple feature systems can contribute to a single coherent context item;
- Sunnie's behavior reflects the current world without becoming needy or intrusive;
- the application still works offline for all core personal data and functions.
