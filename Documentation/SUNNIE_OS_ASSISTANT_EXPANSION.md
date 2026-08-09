# Sunnie Days — OS / Assistant Expansion

## Purpose

This document extends the Sunnie Days product-integration revamp. These additions are not intended to turn Sunnie Days back into a collection of separate mini-apps. They exist to make the existing personal operating environment more useful, more personal, more playful, and more coherent.

Two additions have first-class priority above the rest:

1. **Tell Sunnie** — the universal natural-language and voice capture/action layer.
2. **Flight Mode** — a whole-app contextual operating state for Vanessa's work travel.

The remaining concepts support these two pillars and deepen Sunnie Days as a persistent personal world.

The non-pressure rule from `PRODUCT_INTEGRATION_AND_REWARD_SYSTEM.md` applies to every item here. None of these systems may introduce streak loss, guilt, punishment, nagging, emotional dependency, artificial urgency, or loss of earned progress.

---

## Priority 1: Tell Sunnie

### Product role

Tell Sunnie should become one of the primary ways Vanessa interacts with Sunnie Days.

Instead of requiring her to decide which feature owns a thought or action, she can type or speak naturally and let Sunnie Days interpret the intent, identify the relevant subsystem, show what it understood, and route the request through the existing deterministic use case.

Examples:

- "I bought fertilizer for Fern."
- "Remember this restaurant for Lisbon."
- "I want to make arroz tomorrow."
- "Watered the monstera this morning."
- "Remind me to pack my charger for Tokyo."
- "Save this as a trip memory."
- "How many plants need care before I leave?"
- "What do I still need to do before my flight?"

### Interaction model

Tell Sunnie should be available from multiple surfaces rather than living in a separate utility screen:

- Today;
- Sunnie Home;
- a persistent compose/capture action where appropriate;
- widgets where supported;
- Apple Watch for concise capture;
- App Intents / Siri / Shortcuts;
- hardware/system entry points exposed by iOS when appropriate.

Input may be text or voice. The user should never need to know the app's internal feature taxonomy.

### Architecture

Tell Sunnie is an intent router, not a second data layer.

The flow should be:

1. capture text or speech;
2. classify the user's intent;
3. extract structured candidate data;
4. identify the existing app tool/use case that can fulfill it;
5. present a concise interpretation when confirmation is appropriate;
6. execute through the normal use case;
7. emit the same typed domain event as a manually initiated action;
8. refresh shared context.

The underlying feature remains authoritative. Tell Sunnie must never bypass repository validation, permissions, safety rules, duplicate protection, or confirmation requirements.

### Intelligence layer

Where supported, Apple's Foundation Models framework may interpret natural language and produce structured tool calls. Deterministic parsing and fallback commands should remain available where practical so core capture does not depend on model availability.

Foundation Models may help answer questions using already-authorized Sunnie Days context, but must not invent facts or silently modify records.

### Confirmation rules

Low-risk, reversible actions can be optimized for speed. Destructive, ambiguous, externally visible, privacy-sensitive, or consequential actions require clear confirmation.

Examples that should normally confirm:

- deleting or replacing records;
- sending or sharing information;
- adding calendar events if the exact interpretation is uncertain;
- Health writes whose value was inferred rather than explicitly supplied;
- actions involving another person;
- ambiguous plant/trip/recipe identity matches.

### Why this matters

Tell Sunnie is the clearest expression of the OS concept. The user stops thinking "which section do I open?" and starts thinking "tell Sunnie what I need." It turns the existing breadth of Sunnie Days into an advantage rather than a navigation burden.

---

## Priority 2: Flight Mode

### Product role

Flight Mode should be a whole-app contextual operating state for Vanessa's work travel, not a new flight-attendant tab.

When a work trip is active or imminent, Sunnie Days should temporarily reorganize itself around the information and actions most relevant to that trip while leaving all ordinary functionality available.

### Activation

Flight Mode may be activated by:

- an explicitly marked work trip;
- a calendar event or trip record the user has connected and confirmed;
- manual activation;
- an App Intent / Siri action.

Automatic activation must be conservative and reversible. Sunnie Days should not infer employment status or begin a work mode solely from weak signals.

### Whole-app effects

During Flight Mode, the shared context engine should elevate useful travel/work information across Today, Sunnie Home, widgets, Watch, Tell Sunnie, and relevant notifications.

Potential context includes:

- local and destination time;
- weather at origin/destination;
- trip schedule and segments;
- packing state;
- departure/return checklists;
- plant coverage status;
- saved places and trip memories;
- meal/packed-food planning;
- hydration and sleep helpers where enabled;
- destination language moments;
- calendar context;
- destination-specific Sunnie visuals, keepsakes, and ambient world state.

The user should see one coherent trip situation, not eight cards from eight subsystems.

### Work-boundary rule

Flight Mode is a personal assistant for Vanessa's trip and wellbeing. It is not an airline operations, dispatch, crew scheduling, aviation safety, or regulatory system. It must not represent itself as authoritative for safety-critical flight information.

### Return behavior

When the trip ends, Flight Mode should quietly resolve back into ordinary Sunnie Days. It may offer memories, photos, keepsakes, journal prompts, or plant-return context, but nothing should imply that the user failed to complete a trip routine.

### Why this matters

Flight Mode demonstrates the integration thesis better than almost any other feature. Travel, plants, meals, wellness, language, weather, calendar, memories, rewards, and Sunnie's world all become one temporary operating state driven by real context.

---

## Supporting expansion 1: Sunnie Memory Book

Create a visual, longitudinal memory layer that can assemble meaningful moments already stored across Sunnie Days.

Candidate sources include:

- travel memories;
- photos;
- journal entries chosen by the user for inclusion;
- plant milestones and growth photos;
- unlocked postcards and stamps;
- notable game/collection moments;
- selected wellness reflections;
- seasonal or destination moments.

The Memory Book should feel like chapters of a life rather than a database timeline. It may generate layouts, summaries, map groupings, and visual chapters from existing records.

Privacy-sensitive material must be opt-in for cross-feature memory presentation. Journal and wellness content must never be surfaced in a decorative memory book merely because it exists.

Potential reward tie-in: destination chapters, stationery styles, album designs, frames, and Sunnie scrapbook interactions can unlock permanently.

---

## Supporting expansion 2: Language Moments

Use travel, saved places, time, and user language preferences to surface short optional language moments in context.

Examples:

- a useful Japanese phrase during a Japan trip;
- a Portuguese expression tied to a saved place in Brazil;
- a French phrase attached to a café memory;
- a tiny translation action inside Tell Sunnie.

This is not a streak-based language course. There are no missed lessons, daily obligations, mastery penalties, or required progression trees.

Language Moments should be ambient, relevant, optional, and easy to dismiss.

---

## Supporting expansion 3: Photo Intelligence

Create a shared photo interpretation layer that can propose useful actions based on an image.

Possible classifications include:

- plant;
- meal/food;
- destination/place;
- receipt or document;
- travel memory;
- packing item;
- growth photo;
- general personal memory.

Examples:

- photograph a plant and offer to attach it to an existing plant or create a growth entry;
- photograph a meal and offer to save it with a recipe or memory;
- photograph a place and offer to attach it to the current trip;
- photograph a receipt and offer to preserve it as a trip document if that capability is later supported.

Classification must be presented as a suggestion, not a claim. The image remains under the app's existing local-first/privacy rules.

Photo Intelligence should feed Tell Sunnie, not become a separate photo-management application.

---

## Supporting expansion 4: Sunnie's Curio Cabinet

Create a highly visual collection of small objects representing things that happened in Vanessa's real Sunnie Days world.

Examples:

- miniature airplanes;
- destination trinkets;
- tiny plant pots;
- souvenirs;
- game trophies;
- seasonal objects;
- humorous novelty items;
- objects tied to personal milestones;
- rare hidden collectibles.

These are permanent positive rewards. They never expire and are never revoked because of inactivity.

Objects may be inspectable or interactive and may unlock small animations, sounds, Sunnie reactions, or environmental changes.

The Curio Cabinet should connect to the existing collection/home ownership model rather than create a second reward inventory.

---

## Supporting expansion 5: Dynamic Environments

Deepen Sunnie Home so the environment can react to actual context.

Possible environmental inputs:

- day-cycle state: Sunnie Days / Sunnie Afternoonies / Sunnie Nights;
- local weather;
- active destination;
- active Flight Mode;
- season/hemisphere;
- equipped rewards;
- collected plants or decorative representations;
- recent travel keepsakes;
- selected soundscape;
- special dates or user-selected occasions.

Examples:

- rain appearing outside Sunnie's window when it is raining locally;
- Tokyo-inspired ambient scenery during an active Japan trip;
- evening lamps activating during Sunnie Nights;
- a newly earned travel object appearing naturally in the room;
- plant-derived decor gradually making the environment greener.

Environmental state must remain pleasant and informative, never punitive. Bad weather, low wellness input, inactivity, or unfinished optional tasks must not make Sunnie's world bleak as a behavioral pressure mechanism.

---

## Supporting expansion 6: Personal Favorites Intelligence

Build a local preference graph from explicit favorites and repeated choices so Sunnie Days can connect information across features.

Examples:

- favorite places;
- meals and recipes;
- plants;
- games;
- sounds;
- travel destinations;
- routines;
- outfit/decor preferences;
- recurring packing choices.

This should primarily improve ranking and recall:

- "You saved this café last time you were in Madrid.";
- surfacing a favorite recipe when planning meals;
- reusing a preferred packing template;
- making favorite sounds easier to reach;
- giving Tell Sunnie better disambiguation.

Implicit preference inference should be conservative. Explicit user choices override inferred ones, and the user should be able to inspect or reset learned preferences where practical.

---

## Supporting expansion 7: Voice and Personality Unlocks

Expand positive progression into alternate Sunnie presentation packs.

Possible permanent unlocks include:

- voice variants;
- greeting styles;
- small sound sets;
- animation sets;
- poses;
- idle behavior packs;
- themed interaction sounds;
- special destination/seasonal reactions.

Unlocks change presentation, not Sunnie's fundamental behavioral ethics. No personality pack may become guilt-inducing, hostile, sarcastic toward the user, punitive, or emotionally dependent.

Voice output should remain optional and independently controllable from reward ownership.

---

## Supporting expansion 8: Surprises and Easter Eggs

Add rare, harmless discoveries created from combinations of context, owned items, dates, destinations, weather, and environment state.

Examples:

- Sunnie interacting unexpectedly with a newly placed object;
- a special animation during unusual weather;
- a destination-specific hidden interaction;
- a rare combination of outfit and decor causing a playful scene;
- an old travel souvenir triggering a tiny ambient callback.

Easter eggs must not rely on maintaining streaks, opening the app at a precise time, purchasing anything, or fear of missing out.

If a surprise is missed, nothing should tell the user that they missed it. Similar discoveries can recur naturally later.

---

## How the additions fit together

These systems should reinforce one another rather than form ten new destinations.

A representative flow:

1. Vanessa enters Flight Mode for a Tokyo work trip.
2. Today reorganizes around the trip, packing, plant coverage, weather, local time, and relevant meals.
3. She tells Sunnie, "remember this little ramen place."
4. Tell Sunnie identifies the active trip and offers the matching place/memory action.
5. A photo can attach to the memory through Photo Intelligence.
6. A useful Japanese Language Moment may appear contextually later.
7. The trip eventually contributes a page/chapter to the Memory Book.
8. The destination may grant a permanent Curio Cabinet object or home keepsake.
9. Sunnie Home can adopt a destination-aware environment during the trip.
10. Personal Favorites Intelligence can recall the restaurant if she returns to Tokyo in the future.

The value is the chain. Each capability makes the others more useful.

---

## Navigation and surface rules

Tell Sunnie and Flight Mode are product-level interaction modes and may appear prominently on Today and Sunnie Home.

The remaining additions should normally be reached contextually or through existing homes:

- Memory Book through travel/memories/collections or an appropriate world surface;
- Language Moments through context, travel, Tell Sunnie, and optional settings;
- Photo Intelligence through capture/import actions;
- Curio Cabinet through Sunnie Home/Collections;
- Dynamic Environments through Sunnie Home;
- Favorites Intelligence mostly invisibly, with management in settings if needed;
- Voice/Personality Unlocks through Collections/Sunnie Home;
- Easter Eggs through the world itself.

Do not add a new top-level tab for each concept.

---

## Implementation priority

### Tier 1 — first-class assistant behavior

1. Unified Context Engine / `CurrentContext`.
2. **Tell Sunnie** text capture with deterministic tool routing.
3. **Tell Sunnie** voice capture and App Intent entry points.
4. **Flight Mode** context contract and manual/work-trip activation.
5. Flight Mode integration across Today, Travel, Jungle, Meals, weather/time, Watch, widgets, and Sunnie Home.
6. Foundation Models tool selection only after Tell Sunnie's deterministic action contracts are stable.

### Tier 2 — make the world remember and react

7. Dynamic Environments.
8. Sunnie Memory Book.
9. Curio Cabinet expansion on the existing reward/collection model.
10. Personal Favorites Intelligence.

### Tier 3 — ambient intelligence and delight

11. Photo Intelligence.
12. Language Moments.
13. Voice/Personality Unlock packs.
14. Surprises and Easter Eggs.

This priority is intentional. Tell Sunnie and Flight Mode should be excellent before substantial engineering time is spent on novelty content.

---

## Acceptance criteria

The expansion is successful when:

- Vanessa can express common actions naturally without first choosing a module;
- Tell Sunnie executes through existing use cases rather than parallel data paths;
- Flight Mode changes the whole app's context rather than opening a separate work-travel dashboard;
- travel, plants, meals, language, weather, calendar, memories, rewards, and Sunnie Home can coherently contribute to one active trip context;
- the app becomes more personal as it accumulates history, preferences, rewards, and memories;
- earned objects, voices, environments, and presentation variants remain permanently owned;
- optional delight never turns into a retention mechanism based on guilt or fear of missing out;
- privacy-sensitive information is not surfaced across features without an appropriate policy or explicit user action;
- all core personal data and deterministic functions continue to work without Foundation Models;
- none of the supporting expansions requires its own top-level product silo.
