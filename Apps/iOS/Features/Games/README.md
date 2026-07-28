# Games

Not implemented yet. Reserved for **Phase 7 — shared game host, daily puzzle, the initial game set, save/resume, explanations**
(`Documentation/06_Delivery/IMPLEMENTATION_ROADMAP.md`).

The folder exists so the feature-first structure in
`PROJECT_STRUCTURE_AND_CODING_STANDARDS.md` §1 is visible from the start, and so
the placeholder screen this feature currently shows has an obvious home to grow
into. Until then the tab or More entry routes to `PlaceholderFeatureScreen`.

When building this out, follow the per-feature layout:

```
Games/
├── Screens/
├── Components/
├── Models/
├── UseCases/
├── Repositories/
├── Summary/
└── Routing/
```

The feature must not import another feature to mutate its state. Cross-feature
behaviour goes through use cases, repositories, summary providers, and typed
domain events (`TECHNICAL_ARCHITECTURE.md` §6).
