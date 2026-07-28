# Sunnie Days — Read This First

## What this package is

This is the source-of-truth planning and implementation package for **Sunnie Days**, a fully native iPhone and Apple Watch app written in Swift and SwiftUI.

The package is intended to be placed in the project repository and read by Claude Code before implementation. It defines the product, Sunnie’s canonical appearance and behavior, the final feature set, navigation, screen requirements, data model, architecture, integrations, testing standards, and build sequence.

## Canonical product summary

Sunnie Days is a private, highly personalized companion app for Vanessa. Sunnie is a young, baby-faced, plush-looking male sloth who is sometimes sleepy but always kind and positive. He is the visual and emotional centerpiece of the app.

The product has three primary pillars:

1. **Travel and flight-attendant support**
2. **Deep plant care for a 50+ plant home jungle**
3. **Wellness and companionship**

Meal planning, journaling, original games, progression, collectibles, themes, custom music, Apple Health, and Apple Watch are major integrated systems.

## Current implementation target

The current target is a polished **2D native app**. Use static and layered character art, standard SwiftUI animation, transitions, haptics, and audio. Do not begin voice acting, advanced character animation, or 3D work in the initial implementation. The architecture must leave clean extension points for those later systems.

## Locked platform choices

- iPhone first
- Native Swift and SwiftUI only
- Native watchOS companion in Swift and SwiftUI
- Minimum deployment target: iOS 18.0 and watchOS 11.0
- SwiftData for app-owned structured persistence
- Private iCloud/CloudKit synchronization for eligible app data
- Apple frameworks preferred over third-party dependencies
- No web wrapper, React Native, Flutter, Capacitor, or embedded HTML application
- No custom backend in the initial build
- No advertising, subscriptions, or paid unlocks

## App and day-cycle naming

The app is always named **Sunnie Days**.

The optional branded day-cycle presentation uses these names only:

- **Sunnie Days** — morning and daytime presentation
- **Sunnie Afternoonies** — afternoon presentation
- **Sunnie Nights** — evening, night, and late-night presentation

Do not use “Sunnie Mornings” or “Sunnie Evenings.”

Internally, the time engine may use more granular phases such as morning, day, afternoon, evening, night, and late night. Those internal phases do not create additional public names.

## Character-reference priority

The three images in `Reference_Images/Canonical/` are the visual source of truth for Sunnie.

The images in `Reference_Images/Context/` show useful settings and costume ideas, but their older, taller, or more realistic character proportions are **not canonical**. Re-create those contexts using the younger canonical Sunnie.

## Source-of-truth order

When documents appear to conflict, use this order:

1. `MASTER_SOURCE_OF_TRUTH.md`
2. `CLAUDE.md`
3. `REQUIREMENTS_TRACEABILITY.md`
4. Feature and technical specifications
5. Delivery plans and task lists
6. Reference images
7. Older files outside this package

Do not infer requirements from generated text visible inside reference images. Those images are visual references, not authoritative copy or navigation specifications.

## Required reading order for Claude Code

1. `CLAUDE.md`
2. `MASTER_SOURCE_OF_TRUTH.md`
3. `DOCUMENT_INDEX.md`
4. `01_Product/PRODUCT_VISION_AND_GOALS.md`
5. `01_Product/RELEASE_SCOPE_AND_NON_GOALS.md`
6. `02_Character_and_Design/SUNNIE_CHARACTER_BIBLE.md`
7. `05_Technical/TECHNICAL_ARCHITECTURE.md`
8. `06_Delivery/IMPLEMENTATION_ROADMAP.md`
9. Documents specific to the phase being implemented

## How implementation must begin

Do not start by constructing every feature. Begin with project setup, shared foundations, and the first vertical slice described in `06_Delivery/FIRST_VERTICAL_SLICE.md`.

The first vertical slice must prove this complete path:

`Today plant card → Jungle list → Plant detail → log watering → persist event → update Today → Sunnie response → progression event → Watch synchronization`

Only after this flow is stable and tested should broad feature implementation begin.
