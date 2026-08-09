# Sunnie Days OS Revamp — Implementation 1–3

Status: implemented on `chatgpt/product-integration` for review.

This document records the first executable slice of the Sunnie Days personal-OS revamp. It complements `PRODUCT_INTEGRATION_AND_REWARD_SYSTEM.md` and `SUNNIE_OS_ASSISTANT_EXPANSION.md`.

## 1. Unified Context Engine

The app now has one shared read-only context contract rather than having Today independently reconstruct plant, wellness, progression, travel, meals, and trip state.

### Shared contracts

`SunnieShared/Domain/AssistantContext.swift` defines:

- `CurrentContext`
- `ContextItem`
- `ContextItemKind`
- `ContextAction`
- `FlightContext`
- `FlightModePhase`
- `FlightModeSelector`
- `TellSunnieIntent`
- `TellSunnieParser`

The shared types are platform-neutral. They do not import SwiftUI and they do not know how an iPhone screen navigates.

### ContextEngine

`Apps/iOS/Services/ContextEngine.swift` builds the current read-only world from existing authoritative systems.

The initial engine reads:

- Jungle/plant Today summary;
- wellness summary;
- progression profile;
- current and upcoming travel;
- Flight Mode state;
- today's meal-plan count;
- work-trip packing progress;
- personal trip checklist progress;
- travel plant-coverage state;
- destination place/time-zone context;
- WeatherKit summary when available.

It produces ranked `ContextItem` values rather than one card per module.

The context engine performs no user-data mutations. Existing repositories and use cases remain the source of truth.

### App-wide ownership

`AppState` now owns `currentContext` and refreshes it:

- at launch after seeding, Watch processing, and housekeeping;
- when the app returns to the foreground;
- when Today appears or receives a domain event;
- after Tell Sunnie performs a mutation;
- when Sunnie's Home opens through its assistant container.

This makes context genuinely shared state rather than a Today-only summary.

### Today

Today now consumes `CurrentContext` instead of separately querying plant, wellness, progression, and travel systems.

The old fixed "Your world" collection of module shortcuts is replaced with ranked live context. A subsystem does not need to appear merely because it exists.

## 2. Tell Sunnie

Tell Sunnie is implemented as the universal capture/action entry point.

### Entry points

Tell Sunnie is prominent on Today and available directly from Sunnie's Home.

### Input

The first implementation supports:

- typed natural-language input;
- native microphone capture;
- native Speech recognition;
- text-only fallback when either permission is declined or speech recognition is unavailable.

Microphone and speech-recognition permissions are requested only after the user taps the voice control. Typing never requires either permission.

### Deterministic parser

Common high-confidence commands work without any language model and remain available offline where the underlying action is offline-capable.

Initial supported intent classes:

- open a Sunnie Days area;
- log common plant care against an unambiguous plant name;
- add an item to the active Flight Mode packing list;
- ask for current work-trip preparation context;
- ask for the current plant-care picture.

Examples include:

- `Watered the monstera this morning`
- `Remind me to pack my charger`
- `What do I still need to do before my flight?`
- `Open my plants`

### Action safety

Tell Sunnie never writes directly to persistence.

Plant care goes through `LogPlantCare`. Packing additions go through `ManagePacking`. Navigation resolves through the typed route graph.

If a plant name is ambiguous, nothing is changed and Tell Sunnie routes the user to Jungle to choose. If there is no work trip in Flight Mode, Tell Sunnie does not guess which packing list was intended.

Unknown language is acknowledged as unknown rather than silently mapped to a guessed action.

Foundation Models remain a later intelligence layer. They should broaden natural-language understanding after deterministic tool boundaries are stable, not replace those boundaries.

## 3. Flight Mode

Flight Mode is an app state, not a new tab or a separate flight-attendant mini-app.

### Activation

Automatic Flight Mode activation is conservative:

- the trip must be explicitly marked `TripType.work`;
- a current work trip activates Flight Mode;
- the return day uses the returning state;
- an upcoming work trip enters preparation mode inside the initial three-day preparation window;
- personal trips never activate Flight Mode automatically;
- a distant work trip remains ordinary Travel until it enters the preparation window.

This prevents the app from inferring work from vague travel data.

### Current FlightContext

The initial Flight Mode context carries:

- trip identity and title;
- preparation / away / returning phase;
- destination name when known;
- destination time zone and local time presentation;
- departure timing;
- packing counts;
- personal checklist counts;
- plant-care coverage counts;
- today's meal-plan count;
- destination weather when available.

WeatherKit attribution remains visible wherever its data is shown. Stale weather is marked as earlier rather than presented as fresh.

### Surfaces

Flight Mode currently affects:

- Today, where it becomes the highest-priority context card;
- Sunnie's Home, where an active Flight Mode entry point and Tell Sunnie remain available and the existing travel-aware home scene continues to react to active travel;
- Apple Watch travel context, which now prioritizes the same explicit work-trip selection;
- widgets, whose trip panel now prioritizes the same explicit work-trip selection.

The underlying Travel screens remain fully available. Flight Mode is an orchestration layer above them.

### Deliberate boundary

Flight Mode is not airline operations software and does not present any checklist as an official procedure, safety requirement, readiness score, or compliance state.

Packing and checklist counts are facts only. An unchecked item is not called a failure, an emergency, or evidence that the user is behind.

## Non-pressure invariants

Nothing in phases 1–3 changes the product's permanent rule:

- no broken streaks;
- no point loss;
- no reward decay or revocation;
- no missed-day framing;
- no guilt or emotional-dependency language;
- no sad Sunnie because the app was not opened;
- no artificial urgency;
- no punishment for declining permissions or optional suggestions.

## Tests added

`AssistantContextTests` covers the first shared-domain guarantees:

- personal travel cannot activate Flight Mode;
- a current explicit work trip can activate Flight Mode;
- an imminent work trip enters preparation mode;
- a distant work trip does not activate early;
- the return day selects returning mode;
- plant-care language is parsed;
- packing language is parsed;
- trip-context questions are parsed;
- ordinary navigation language is parsed;
- context items are ranked by priority.

## Next implementation layer

With phases 1–3 established, the next work can build on these contracts rather than introduce parallel systems. The next logical expansion is the positive reward/world layer, followed by richer Sunnie Home reactions and Memory Book/Curio behavior.
