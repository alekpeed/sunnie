# Travel

Implemented in Phase 5. Travel provides personal and work trips, segments,
packing templates, departure and return checklists, itineraries, time-zone
context, calendar and weather adapters, places and maps, memories, and plant
coverage handoff.

```
Travel/
├── Models/TravelModel.swift
├── Screens/TravelScreen.swift
├── Screens/TripOverviewScreen.swift
├── Screens/TripEditorAndPacking.swift
├── Screens/ChecklistAndMapScreens.swift
├── UseCases/ManageTrip.swift
└── UseCases/ManagePackingAndChecklists.swift
```

Core trip data works offline. Calendar, weather, and location are optional
adapters with denied/manual fallbacks; no feature view mutates another feature
directly.
