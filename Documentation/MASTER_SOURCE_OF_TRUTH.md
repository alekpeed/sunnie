# Sunnie Days — Master Source of Truth

**Status:** Locked product baseline for the initial native 2D application  
**Primary user:** Vanessa, age 38  
**Product owner/creator:** The user commissioning the app  
**Primary platforms:** iPhone and Apple Watch  
**Implementation:** Swift and SwiftUI, fully native

## 1. Product definition

Sunnie Days is a personalized all-in-one companion app centered on Sunnie, a cute, young, sometimes sleepy male sloth. It helps Vanessa manage travel, flight-attendant routines, a very large plant collection, wellness, journaling, meal preparation, and intelligent games. Its practical systems are unified by Sunnie, a changing home environment, themed presentation, music, gentle reminders, and positive progression.

The app should feel substantial and useful, not like a collection of shallow novelty screens. It should also feel playful, beautiful, and emotionally warm without appearing designed for a child.

## 2. Canonical character

Sunnie’s visual identity is defined by the three images in `Reference_Images/Canonical/`.

Required traits:

- Young and baby-faced
- Large glossy brown eyes
- Rounded cream-colored face mask
- Small dark nose and small mouth
- Soft blush on the cheeks
- Short tuft of hair
- Small plush body with short limbs
- Light caramel/tan fur
- Soft, rounded, toy-like proportions
- Expressive but gentle face
- Sometimes half-lidded or sleepy, without looking old or ill

Prohibited reinterpretations:

- Tall adult body
- Long realistic limbs
- Mature or elderly face
- Narrow head
- Photorealistic animal anatomy
- Aggressive expression
- Sharp or intimidating styling

## 3. Product pillars

### 3.1 Travel

Travel has two connected layers:

- Practical support for flight-attendant and irregular travel life
- A recreational travel log, world map, destination collection, and memory system

### 3.2 Jungle

The plant system must support more than 50 plants with deep profiles, care schedules, history, health notes, photos, travel coverage, and QR-ready identities.

### 3.3 Wellness and companion

The wellness system includes check-ins, affirmations, gratitude, journaling, calm sounds, meditation, breathing, self-care routines, sleep support, and gentle suggestions. Sunnie is present throughout but must never obstruct information.

## 4. Major supporting systems

- Meal planning and preparation
- Original games and puzzles
- Journal and memory archive
- Progression and collectibles
- Sunnie’s evolving home
- Themes and day-cycle presentation
- Creator-managed music and ambience
- Apple Health integration
- Apple Watch companion
- Widgets and App Intents
- Optional calendar, map, weather, and notification integrations

## 5. Final primary navigation

The iPhone app uses five primary destinations:

1. **Today**
2. **Jungle**
3. **Travel**
4. **Wellness**
5. **More**

`More` contains Meals, Games, Journal, Collections, Sunnie Home, Themes, Audio settings, Health and Watch settings, and general Settings.

Meals, games, and journal actions also surface contextually on Today.

## 6. App name and day-cycle naming

The product name is always **Sunnie Days**.

The optional branded day-cycle skin uses:

- **Sunnie Days** for morning/day
- **Sunnie Afternoonies** for afternoon
- **Sunnie Nights** for evening/night/late night

The universal time engine affects every theme, not only the branded day-cycle skin.

## 7. Initial visual theme families

1. **Lush Tropical Jungle**
2. **Travel Scrapbook**
3. **Day-Cycle Theme**, using Sunnie Days, Sunnie Afternoonies, and Sunnie Nights

Themes are data-driven and expandable.

## 8. Tone

Sunnie is caring, loving, hopeful, calm, and happy. The app never uses:

- Sarcasm
- Rudeness
- Cynicism
- Pessimism
- Shame
- Guilt
- Threats
- Punishment
- Fear-based reminders
- “You failed” framing
- Loss of earned rewards for inactivity

Missed actions become neutral carryovers or fresh opportunities.

## 9. Personalization

- Vanessa may occasionally be called “Noonies.”
- Approximate eligible-message probability: 1 in 20.
- Repeated random occurrences are acceptable.
- The nickname is never part of permanent branding or serious system copy.
- Favorite destination content should prioritize Vietnam, Tokyo, Paris, Spain, and Brazil.
- Languages relevant to games: English, Spanish, Portuguese, and French.
- Dietary rule: no eggs.

## 10. Platform and current scope

### Current release target

- Fully native iPhone app
- Native Apple Watch companion
- 2D presentation
- Standard SwiftUI motion and layered art
- Local-first data
- Private iCloud synchronization
- HealthKit compatibility
- Creator-managed music

### Explicitly deferred extensions

- Android game companion
- Plant caretaker companion app
- Cross-platform multiplayer backend
- LifeOS synchronization
- Full voice performance system
- Advanced character rigging
- 3D environments or character rendering
- Generative AI plant diagnosis
- Generative AI meal planning
- Public social network or community

The architecture must accommodate these later, but the current implementation must not build them prematurely.

## 11. Music

The creator composes music externally using a computer, DAW, piano, or MIDI keyboard. MIDI ingestion is behind the scenes. Vanessa sees only finished music and audio controls.

Preferred runtime approach:

- Rendered AAC/CAF assets for exact playback
- Runtime MIDI only when adaptive sequencing provides a specific benefit
- Source MIDI excluded from the user-facing interface

## 12. Data and privacy

- Core features work offline.
- App-owned structured data uses SwiftData behind repositories.
- Eligible data syncs through the user’s private iCloud/CloudKit database.
- Health data remains in HealthKit except for minimal derived summaries and references required by the app.
- No advertising or behavior-selling SDKs.
- Export and deletion controls are required.

## 13. Distribution and branding

The initial app is personal/private. Flight-attendant presentation may be Delta-inspired for Vanessa. Airline brand assets must remain isolated and replaceable. Do not hardcode third-party trademarks into core design components or data models.

## 14. Definition of success

Sunnie Days succeeds when Vanessa can use it daily as one coherent companion rather than several disconnected utilities. Practical tasks should become easier; Sunnie should feel consistent and lovable; the app should remain responsive with realistic data; and new content should be addable without architectural rewrites.
