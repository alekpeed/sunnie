# Technical Architecture

## 1. Architecture style

Use a **modular monolith**:

- One Xcode project/workspace
- Native iPhone app target
- Native Watch app target
- Widget extension target when implemented
- Shared local Swift package for platform-neutral models, protocols, content schemas, and utilities
- Feature-first folders in the iPhone target
- Strict repository/service boundaries

Do not begin with dozens of independent packages. Extract additional local packages only when compile boundaries or Watch/widget reuse justify them.

## 2. Technology baseline

- Swift
- SwiftUI
- Observation (`@Observable`)
- Swift concurrency
- SwiftData
- CloudKit/private iCloud
- UserNotifications
- HealthKit
- WatchConnectivity
- WidgetKit
- App Intents
- EventKit
- MapKit
- WeatherKit
- AVFAudio/Core MIDI

## 3. Layering

```text
SwiftUI View
  ↓ user action / displayed state
Feature Model (@Observable, @MainActor)
  ↓
Application Use Case
  ↓
Repository or Service Protocol
  ↓
Concrete Persistence / Apple Framework Adapter
```

## 4. Responsibilities

### Views

- Layout
- Accessibility
- Display state
- Input forwarding
- Navigation intent

Views do not:

- Query SwiftData directly for complex feature behavior
- Call HealthKit, CloudKit, WeatherKit, or WatchConnectivity
- Calculate rewards
- Schedule notifications
- Select raw asset file names

### Feature models

- Screen/feature state
- Loading and errors
- Invoke use cases
- Map domain results to view state
- Cancel work on lifecycle changes

### Use cases

Represent complete actions:

- `LogPlantCare`
- `CreateTrip`
- `GeneratePackingList`
- `RecordWellnessCheckIn`
- `CreateMealPrepPlan`
- `CompletePuzzle`
- `GrantReward`
- `StartMeditation`

### Repositories

Own app data retrieval and persistence through domain-oriented methods.

### Services

Wrap Apple frameworks and device behavior.

## 5. Dependency direction

Allowed:

- App composition imports all feature and adapter implementations.
- Features import shared domain types and protocol definitions.
- Adapters import Apple frameworks and shared protocols.
- Watch and widgets import shared domain/payload types.

Prohibited:

- Feature A directly mutating Feature B
- Domain models importing SwiftUI
- SwiftUI views importing CloudKit or HealthKit for business behavior
- Apple framework types leaking into core domain APIs
- Game rules directly editing rewards
- Theme assets hardcoded in feature views

## 6. Cross-feature communication

Use:

- Typed domain events
- Use cases
- Summary providers
- Shared repository reads
- App router

Example:

```text
Plant care event saved
→ Plant summary invalidated
→ Progression engine evaluates typed event
→ Reward grant stored idempotently
→ Today summary refreshes
→ Sunnie message service selects reaction
→ Watch application context updates
```

## 7. State management

### Global app state

Keep small:

- Active profile
- Active theme
- Current time phase
- Active trip ID
- Integration authorization summaries
- Sync state
- Router

### Feature state

Owned by feature models and recreated/preserved according to navigation lifecycle.

### Persistent state

Owned by repositories.

## 8. Dependency injection

Use explicit initializer injection for use cases and feature models. Use SwiftUI environment for stable app-level services only. Avoid hidden global singletons except Apple system singleton wrappers owned by adapters.

## 9. Routing

Use typed routes:

```swift
enum AppRoute: Hashable {
    case today
    case jungle
    case plant(UUID)
    case travel
    case trip(UUID)
    case wellness
    case checkIn
    case meals
    case games
    case game(String)
    case journal
    case collections
    case sunnieHome
    case themes
    case settings
}
```

Deep links, notifications, widgets, and App Intents resolve into this route system.

## 10. Domain events

Use stable, versioned event types. Events that affect persistence/progression include deterministic IDs.

```swift
struct DomainEvent: Codable, Sendable {
    let id: UUID
    let type: DomainEventType
    let occurredAt: Date
    let sourceEntityID: UUID?
    let deterministicKey: String?
    let payloadVersion: Int
}
```

## 11. Content architecture

Non-user content is versioned and data-driven:

- Sunnie messages
- Affirmations
- Themes
- Audio cues
- Destinations
- Games/puzzles
- Rewards
- Collectibles
- Meditations

Content is validated at build/test time.

## 12. Offline-first behavior

- Write to local persistence first.
- Update UI optimistically after successful local transaction.
- Synchronize later.
- Show sync state only when relevant.
- Network unavailability must not block ordinary records.

## 13. Future platform boundary

Future Android/multiplayer uses platform-neutral Codable game state and a `MultiplayerService` protocol. Do not place CloudKit record types in game domain models.

Future 3D/animation uses semantic `SunnieVisualState`, not feature-specific engine calls.

## 14. Architecture quality gates

Before broad feature work:

- Project compiles for iPhone and Watch.
- Shared package boundaries work.
- In-memory persistence works in tests.
- Theme/time/Sunnie engines have protocol boundaries.
- First vertical slice passes tests.
- No direct framework calls from views.
