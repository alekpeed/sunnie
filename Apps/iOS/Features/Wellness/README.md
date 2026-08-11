# Wellness

Implemented in Phase 3. The Wellness tab provides multidimensional check-ins,
affirmations, gratitude, breathing, meditation, calm audio, descriptive history,
and optional Health integration.

```
Wellness/
├── Models/WellnessModel.swift
├── Screens/WellnessScreen.swift
├── Screens/PracticeScreens.swift
├── UseCases/WellnessUseCases.swift
└── UseCases/ManageHealthIntegration.swift
```

Views operate through `AppDependencies`; SwiftData and HealthKit remain behind
repository and service boundaries. Permission refusal is an ordinary supported
state, and history reports observations without diagnoses or moral conclusions.
