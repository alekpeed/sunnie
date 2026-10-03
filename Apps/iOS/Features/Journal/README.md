# Journal

Implemented in Phase 3. The Journal supports resumable drafts, text editing,
gratitude items, tags, search, reversible deletion, photos, voice notes, and a
local JSON export from Settings.

```
Journal/
├── Screens/JournalScreens.swift
└── UseCases/JournalUseCases.swift     lifecycle and complete export
```

Attachment UI is shared with Wellness through the design-system component while
storage remains behind `MediaRepository`. Deleted entries retain the documented
restore window and launch housekeeping removes media only after its owner is no
longer restorable.
