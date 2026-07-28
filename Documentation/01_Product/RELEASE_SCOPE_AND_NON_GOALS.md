# Release Scope and Non-Goals

## Release model

The product is broad, but implementation must remain phased. “Final version” in this package means the complete native 2D release, not every possible future platform or media extension.

## Release 1.0: Complete native 2D app

Release 1.0 should contain:

- Today dashboard and Sunnie companion
- Universal day-cycle engine
- Three initial theme families
- Deep Jungle/plant system
- Practical travel and flight-attendant tools
- Travel memories, map, stamps, and destination content
- Wellness, journal, meditations, breathing, and sounds
- Meals, pantry, grocery, and prep
- Initial original game library and daily puzzle
- Progression, collectibles, and Sunnie Home
- Creator-managed audio
- Optional HealthKit
- Native Apple Watch companion
- Local notifications
- MapKit, WeatherKit, EventKit, WidgetKit, and App Intents where specified
- Local-first persistence and private iCloud synchronization
- Accessibility, export, deletion, testing, and migration support

Release 1.0 may use static or layered 2D character assets and ordinary SwiftUI animations. It does not require a skeletal character rig.

## Content after 1.0

The architecture should permit ongoing additions without new foundational systems:

- Themes
- Destination packs
- Game and puzzle packs
- Outfits
- Decor
- Affirmations
- Meditations
- Music
- Soundscapes
- Recipes
- Plant reference content
- Story scenes

## Deferred platform extensions

These are not implementation targets for the first repository build:

### Android companion

A lightweight future app for shared turn-based games and possibly shared postcards. Do not build or scaffold an Android project now.

### Plant caretaker app

A future minimal app for Vanessa’s mother to scan QR tags, view assigned instructions, and log care. Define stable QR and shared-record concepts now; do not implement the app or shared backend.

### LifeOS integration

Keep integration points protocol-based. Do not add LifeOS dependencies or network contracts until a separate specification exists.

### Voice and 3D

Preserve renderer and audio-narration boundaries. Do not build a voice pipeline, facial animation, 3D models, or RealityKit scenes now.

### Generative AI

Do not call an LLM or image model in the initial implementation. Plant and meal functionality should be deterministic and user-authored until an AI specification, privacy model, and cost model are approved.

## Explicit non-goals

- Commercial monetization
- Ads
- Public profiles
- Social feed
- Follower system
- Public user-generated content
- Medical diagnosis
- Aviation operations, crew scheduling, or safety-critical flight data
- Airline employee authentication
- Full offline Apple map tiles
- Public recipe marketplace
- Habit punishment
- Competitive leaderboards against strangers
- Crypto, paid currency, loot boxes, or consumable purchases

## Country-pack clarification

A downloadable country or destination pack contains Sunnie Days content such as art, outfits, stamps, postcards, trivia, ambient audio, saved guides, and metadata. It does not promise downloadable MapKit basemap tiles. Trip records and downloaded app-authored content remain available offline; MapKit imagery depends on Apple’s services and system caching.

## Scope-change rule

Any change that introduces a new platform, backend, third-party dependency, medical claim, commercial system, or major data-sharing behavior requires an Architecture Decision Record before implementation.
