# Requirements Traceability

Priority legend: **P0** required foundation or release blocker; **P1** required for the complete 2D release; **P2** planned expandable content or future-ready behavior.

| ID | Priority | Requirement | Primary specification |
|---|---:|---|---|
| PLAT-001 | P0 | The iPhone app shall be implemented entirely in native Swift and SwiftUI. | `05_Technical/TECHNICAL_ARCHITECTURE.md` |
| PLAT-002 | P0 | The Apple Watch companion shall be implemented in native Swift and SwiftUI. | `05_Technical/TECHNICAL_ARCHITECTURE.md` |
| PLAT-003 | P0 | The minimum default deployment targets shall be iOS 18.0 and watchOS 11.0. | `05_Technical/TECHNICAL_ARCHITECTURE.md` |
| PLAT-004 | P0 | The initial product shall not use a web wrapper or cross-platform UI framework. | `05_Technical/TECHNICAL_ARCHITECTURE.md` |
| CHAR-001 | P0 | Sunnie shall match the young canonical reference images. | `02_Character_and_Design/SUNNIE_CHARACTER_BIBLE.md` |
| CHAR-002 | P0 | Sunnie shall remain male, baby-faced, plush, rounded, and highly cartoony. | `02_Character_and_Design/SUNNIE_CHARACTER_BIBLE.md` |
| CHAR-003 | P0 | Context images shall not override canonical age or proportions. | `02_Character_and_Design/SUNNIE_CHARACTER_BIBLE.md` |
| TONE-001 | P0 | User-facing content shall not shame, threaten, guilt, mock, or punish the user. | `01_Product/TONE_COPY_AND_BEHAVIOR.md` |
| TONE-002 | P0 | Missed actions shall be presented neutrally or as a fresh opportunity. | `01_Product/TONE_COPY_AND_BEHAVIOR.md` |
| TONE-003 | P1 | The nickname Noonies shall appear in approximately 1 in 20 eligible Sunnie messages. | `01_Product/TONE_COPY_AND_BEHAVIOR.md` |
| NAME-001 | P0 | The app name shall be Sunnie Days. | `MASTER_SOURCE_OF_TRUTH.md` |
| NAME-002 | P0 | The branded day-cycle labels shall be Sunnie Days, Sunnie Afternoonies, and Sunnie Nights. | `MASTER_SOURCE_OF_TRUTH.md` |
| NAME-003 | P0 | Sunnie Mornings and Sunnie Evenings shall not appear. | `MASTER_SOURCE_OF_TRUTH.md` |
| NAV-001 | P0 | Primary navigation shall contain Today, Jungle, Travel, Wellness, and More. | `03_UX/INFORMATION_ARCHITECTURE.md` |
| HOME-001 | P0 | Today shall show a time-aware greeting, affirmation, Sunnie message, and feature summaries. | `04_Features/HOME_AND_COMPANION.md` |
| HOME-002 | P1 | Today shall surface travel, plant, wellness, meal, puzzle, and progression information. | `04_Features/HOME_AND_COMPANION.md` |
| TIME-001 | P0 | A universal time engine shall affect every theme. | `02_Character_and_Design/THEMES_AND_TIME_OF_DAY.md` |
| TIME-002 | P1 | The time engine shall support local time-zone and manual override. | `02_Character_and_Design/THEMES_AND_TIME_OF_DAY.md` |
| THEME-001 | P0 | Themes shall be data-driven and not hardcoded per screen. | `02_Character_and_Design/THEMES_AND_TIME_OF_DAY.md` |
| THEME-002 | P1 | Initial theme families shall be Lush Tropical Jungle, Travel Scrapbook, and Day-Cycle Theme. | `02_Character_and_Design/THEMES_AND_TIME_OF_DAY.md` |
| PLANT-001 | P0 | The Jungle system shall remain usable with at least 50 plants. | `04_Features/PLANT_CARE.md` |
| PLANT-002 | P0 | Each plant shall support identity, photos, location, care schedules, history, and notes. | `04_Features/PLANT_CARE.md` |
| PLANT-003 | P1 | Plant health observations and growth timelines shall be supported. | `04_Features/PLANT_CARE.md` |
| PLANT-004 | P1 | Plant search, filter, sort, grouping, and bulk actions shall be supported. | `04_Features/PLANT_CARE.md` |
| PLANT-005 | P1 | Plants shall have stable QR-ready identifiers. | `04_Features/PLANT_CARE.md` |
| PLANT-006 | P1 | Trip-specific caretaker instructions and coverage shall be supported. | `04_Features/PLANT_CARE.md` |
| TRAVEL-001 | P0 | Travel shall support personal and work-trip contexts. | `04_Features/TRAVEL_AND_FLIGHT_ATTENDANT.md` |
| TRAVEL-002 | P1 | Trips shall support itineraries, packing, departure, return, time zones, weather, and notes. | `04_Features/TRAVEL_AND_FLIGHT_ATTENDANT.md` |
| TRAVEL-003 | P1 | Travel shall support sleep, hydration, meal, layover, hotel, recovery, and plant-handoff tools. | `04_Features/TRAVEL_AND_FLIGHT_ATTENDANT.md` |
| TRAVEL-004 | P1 | Travel memories shall support places, photos, notes, stamps, postcards, and souvenirs. | `04_Features/TRAVEL_AND_FLIGHT_ATTENDANT.md` |
| TRAVEL-005 | P1 | A world map shall visualize visited and saved places. | `04_Features/TRAVEL_AND_FLIGHT_ATTENDANT.md` |
| TRAVEL-006 | P2 | Destination packs shall be expandable app-authored content packs. | `04_Features/TRAVEL_AND_FLIGHT_ATTENDANT.md` |
| WELL-001 | P0 | Wellness shall support mood, energy, stress, and sleep check-ins. | `04_Features/WELLNESS_JOURNAL_AND_CALM.md` |
| WELL-002 | P1 | Wellness shall support affirmations, gratitude, breathing, meditation, grounding, and calm sounds. | `04_Features/WELLNESS_JOURNAL_AND_CALM.md` |
| WELL-003 | P1 | Wellness trends shall avoid diagnostic or moral conclusions. | `04_Features/WELLNESS_JOURNAL_AND_CALM.md` |
| JOURNAL-001 | P0 | Journal entries shall support text and draft preservation. | `04_Features/WELLNESS_JOURNAL_AND_CALM.md` |
| JOURNAL-002 | P1 | Journal entries shall support voice, photos, gratitude, tags, and feature links. | `04_Features/WELLNESS_JOURNAL_AND_CALM.md` |
| MEAL-001 | P0 | Meal planning shall permanently support a no-eggs dietary rule. | `04_Features/MEALS_AND_PREP.md` |
| MEAL-002 | P1 | Meals shall support home, work, trip, layover, and recovery contexts. | `04_Features/MEALS_AND_PREP.md` |
| MEAL-003 | P1 | Grocery, pantry, batch prep, packed food, and use-before-trip workflows shall be supported. | `04_Features/MEALS_AND_PREP.md` |
| GAME-001 | P0 | Games shall use original mechanics rather than direct template clones. | `04_Features/GAMES_AND_FUTURE_MULTIPLAYER.md` |
| GAME-002 | P1 | The app shall provide a daily puzzle and a game library. | `04_Features/GAMES_AND_FUTURE_MULTIPLAYER.md` |
| GAME-003 | P1 | Game content may use English, Spanish, Portuguese, and French. | `04_Features/GAMES_AND_FUTURE_MULTIPLAYER.md` |
| GAME-004 | P2 | Game state shall be deterministic and serializable for future turn-based play. | `04_Features/GAMES_AND_FUTURE_MULTIPLAYER.md` |
| PROG-001 | P0 | Progression shall not remove earned rewards for missed activity. | `04_Features/PROGRESSION_COLLECTIONS_AND_SUNNIE_HOME.md` |
| PROG-002 | P1 | Rewards shall include outfits, decor, plants, postcards, stamps, music, sounds, and scenes. | `04_Features/PROGRESSION_COLLECTIONS_AND_SUNNIE_HOME.md` |
| HOMEBASE-001 | P1 | Sunnie Home shall evolve through decor, plants, destinations, themes, and day-cycle context. | `04_Features/PROGRESSION_COLLECTIONS_AND_SUNNIE_HOME.md` |
| AUDIO-001 | P0 | MIDI import and assignment shall be creator-side only. | `04_Features/AUDIO_MIDI_AND_SOUNDSCAPES.md` |
| AUDIO-002 | P0 | Vanessa shall not see source MIDI files or MIDI management. | `04_Features/AUDIO_MIDI_AND_SOUNDSCAPES.md` |
| AUDIO-003 | P1 | Rendered audio shall be preferred when exact playback is desired. | `04_Features/AUDIO_MIDI_AND_SOUNDSCAPES.md` |
| AUDIO-004 | P1 | Music, ambience, narration, and effects shall have separate controls. | `04_Features/AUDIO_MIDI_AND_SOUNDSCAPES.md` |
| HEALTH-001 | P0 | HealthKit access shall be optional and permission-scoped. | `04_Features/HEALTH_WATCH_WIDGETS_AND_INTENTS.md` |
| HEALTH-002 | P1 | The app shall remain functional when HealthKit permission is denied. | `04_Features/HEALTH_WATCH_WIDGETS_AND_INTENTS.md` |
| WATCH-001 | P0 | The Watch app shall support queued idempotent actions. | `04_Features/HEALTH_WATCH_WIDGETS_AND_INTENTS.md` |
| WATCH-002 | P1 | Watch features shall include quick check-in, hydration, plant tasks, calm sessions, travel, and affirmations. | `04_Features/HEALTH_WATCH_WIDGETS_AND_INTENTS.md` |
| NOTIF-001 | P0 | Reminders shall respect quiet hours and time zones. | `03_UX/NOTIFICATIONS_AND_REMINDERS.md` |
| NOTIF-002 | P0 | Reminder tone shall never escalate into guilt or threats. | `03_UX/NOTIFICATIONS_AND_REMINDERS.md` |
| NOTIF-003 | P1 | Users shall be able to snooze, reschedule, dismiss, or disable reminder categories. | `03_UX/NOTIFICATIONS_AND_REMINDERS.md` |
| DATA-001 | P0 | Core user actions shall work offline. | `05_Technical/PERSISTENCE_CLOUDKIT_OFFLINE_AND_SYNC.md` |
| DATA-002 | P0 | App-owned structured data shall be accessed through repository abstractions. | `05_Technical/PERSISTENCE_CLOUDKIT_OFFLINE_AND_SYNC.md` |
| DATA-003 | P1 | Eligible private data shall synchronize through iCloud/CloudKit. | `05_Technical/PERSISTENCE_CLOUDKIT_OFFLINE_AND_SYNC.md` |
| DATA-004 | P0 | Persistent schema changes shall include migration planning and tests. | `05_Technical/PERSISTENCE_CLOUDKIT_OFFLINE_AND_SYNC.md` |
| DATA-005 | P0 | Reward grants, Watch actions, and imported events shall be idempotent. | `05_Technical/PERSISTENCE_CLOUDKIT_OFFLINE_AND_SYNC.md` |
| PRIV-001 | P0 | The app shall contain no advertising or data-selling SDK. | `05_Technical/PRIVACY_SECURITY_AND_DATA_LIFECYCLE.md` |
| PRIV-002 | P1 | Users shall be able to export and delete app-owned data. | `05_Technical/PRIVACY_SECURITY_AND_DATA_LIFECYCLE.md` |
| A11Y-001 | P0 | Core screens shall support Dynamic Type and VoiceOver. | `05_Technical/PRIVACY_SECURITY_AND_DATA_LIFECYCLE.md` |
| A11Y-002 | P0 | Motion shall respect Reduce Motion. | `05_Technical/PRIVACY_SECURITY_AND_DATA_LIFECYCLE.md` |
| A11Y-003 | P0 | Color shall not be the sole carrier of status. | `05_Technical/PRIVACY_SECURITY_AND_DATA_LIFECYCLE.md` |
| ARCH-001 | P0 | The app shall use a modular-monolith feature architecture. | `05_Technical/TECHNICAL_ARCHITECTURE.md` |
| ARCH-002 | P0 | SwiftUI views shall not directly call persistence or Apple integration frameworks. | `05_Technical/TECHNICAL_ARCHITECTURE.md` |
| ARCH-003 | P0 | Feature modules shall communicate through use cases, repositories, summaries, or typed events. | `05_Technical/TECHNICAL_ARCHITECTURE.md` |
| ARCH-004 | P0 | Third-party packages require an Architecture Decision Record and approval. | `05_Technical/TECHNICAL_ARCHITECTURE.md` |
| EXP-001 | P1 | Themes, games, destinations, messages, audio, and rewards shall use versioned content definitions. | `05_Technical/CONTENT_PACK_AND_EXPANSION_ARCHITECTURE.md` |
| FUTURE-001 | P0 | Voice, advanced animation, 3D, Android, caretaker, LifeOS, backend, and generative AI shall not be implemented in the initial phase. | `02_Character_and_Design/FUTURE_ANIMATION_VOICE_AND_3D.md` |
| TEST-001 | P0 | Business rules shall have automated unit tests. | `06_Delivery/TESTING_AND_QUALITY_STRATEGY.md` |
| TEST-002 | P0 | Critical flows shall have UI tests. | `06_Delivery/TESTING_AND_QUALITY_STRATEGY.md` |
| TEST-003 | P1 | Watch background transfers shall be validated on paired physical devices before release. | `06_Delivery/TESTING_AND_QUALITY_STRATEGY.md` |
