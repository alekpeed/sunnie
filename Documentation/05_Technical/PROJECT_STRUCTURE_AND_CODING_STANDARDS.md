# Project Structure and Coding Standards

## 1. Recommended repository structure

```text
SunnieDays/
├── CLAUDE.md
├── Documentation/
├── SunnieDays.xcodeproj
├── Apps/
│   ├── iOS/
│   │   ├── App/
│   │   ├── Features/
│   │   │   ├── Today/
│   │   │   ├── Jungle/
│   │   │   ├── Travel/
│   │   │   ├── Wellness/
│   │   │   ├── Meals/
│   │   │   ├── Games/
│   │   │   ├── Journal/
│   │   │   ├── Collections/
│   │   │   ├── SunnieHome/
│   │   │   ├── Themes/
│   │   │   └── Settings/
│   │   ├── Integrations/
│   │   ├── Persistence/
│   │   └── Resources/
│   ├── Watch/
│   └── Widgets/
├── Packages/
│   └── SunnieShared/
│       ├── Sources/
│       │   ├── Domain/
│       │   ├── Protocols/
│       │   ├── ContentSchemas/
│       │   ├── Payloads/
│       │   └── Utilities/
│       └── Tests/
├── AssetsSource/
├── CreatorAudioSource/
├── Scripts/
└── Tests/
```

## 2. File organization within a feature

```text
FeatureName/
├── Screens/
├── Components/
├── Models/
├── UseCases/
├── Repositories/
├── Summary/
├── Routing/
└── Tests/
```

Do not create a generic `Helpers` dumping ground.

## 3. Naming

- Types: UpperCamelCase
- Functions/properties: lowerCamelCase
- Protocols describe capability, not implementation
- Use cases use verbs: `LogPlantCare`, `LoadTodaySummary`
- Repository implementations identify storage: `SwiftDataPlantRepository`
- Content IDs use dot-delimited stable strings
- Asset names follow the asset manifest

## 4. Swift conventions

- Prefer value types for domain data.
- Use `Sendable` where concurrency crosses boundaries.
- UI feature models are `@MainActor`.
- Use structured concurrency.
- Avoid detached tasks without documented reason.
- Handle cancellation.
- Do not use force unwraps in production paths.
- Avoid `Any` in domain APIs.
- Keep functions focused.
- Document non-obvious invariants, not obvious syntax.

## 5. Observation

Use `@Observable` for feature models. Avoid duplicating the same state across multiple models. Derive display values where cheap; cache expensive summaries in appropriate services.

## 6. Error handling

- Domain errors are typed.
- Adapters translate framework errors into domain/service errors.
- UI maps errors to actionable states.
- Never expose raw framework error strings directly to Vanessa.

## 7. Logging

Use Apple unified logging through a wrapper. Redact:

- Journal text
- Voice-note content
- Health data
- Exact travel documents
- Private notes
- User photos

## 8. Localization

All user-facing strings live in localization resources or versioned content packs. Do not concatenate sentences from fragments that become untranslatable.

## 9. Third-party dependencies

Default: none.

A dependency requires:

- Need not met by Apple frameworks or small internal code
- License review
- Privacy review
- Size/performance review
- Maintenance assessment
- ADR and approval

## 10. Code generation

Permitted for:

- Content manifest validation
- Asset ID generation
- Localization key checks
- Test fixture generation

Generated code must be reproducible and committed only when appropriate.

## 11. CI commands

CI should discover available destinations and run schemes through `xcodebuild`. Pin the Xcode version in CI configuration. Do not rely on one developer’s local simulator name.

## 12. Documentation changes

When implementation changes a locked decision:

- Add ADR
- Update source-of-truth doc
- Update requirement mapping
- Update tests/acceptance criteria

Do not silently diverge from the package.
