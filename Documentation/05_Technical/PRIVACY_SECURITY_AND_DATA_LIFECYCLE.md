# Privacy, Security, Accessibility, and Data Lifecycle

## 1. Privacy baseline

Sunnie Days is private by design.

- No ad SDK
- No data broker
- No public profile
- No default remote analytics
- No custom account in the initial release
- No journal or Health content sent to a third-party service

## 2. Data categories

### Highly private

- Journal text/voice/photos
- Wellness check-ins
- HealthKit-derived data
- Travel history and places
- Plant/home details

Do not include in logs or crash breadcrumbs.

### App content

- Themes
- Games
- Affirmations
- Audio
- Collectibles

May be bundled/downloaded and is not personal data until ownership/preferences are recorded.

## 3. Health privacy

- Explain each requested Health type.
- Request only types used by enabled features.
- Treat denial as normal.
- Do not infer medical status.
- Do not use Health data for progression pressure.

## 4. Secrets

Use Keychain for credentials/tokens if any are introduced. Do not commit secrets. WeatherKit and iCloud configuration follow Apple entitlement practices.

## 5. Logging

Use privacy annotations/redaction. Log IDs and categories, not content. Example acceptable log:

```text
Saved JournalEntry id=... attachmentCount=2
```

Not acceptable:

```text
Journal body: ...
```

## 6. Export

- Explicit user action
- Explain included categories
- Generate locally
- Use share sheet
- Clean temporary export files after completion/timeout

## 7. Deletion

Provide:

- Delete individual record
- Archive where safer
- Delete category
- Delete all app data
- Explain HealthKit data deletion separately because Health owns its store
- Propagate CloudKit deletion
- Remove media files

## 8. Accessibility

Required:

- Dynamic Type
- VoiceOver labels/hints
- Logical focus order
- Minimum interactive target size
- Sufficient contrast
- Non-color status cues
- Reduce Motion
- Captions/transcripts for future voice
- Haptic alternatives
- Game alternatives for drag/timed interactions

## 9. Sensitive lock-screen content

Notifications/widgets should not display private journal content, detailed mood, exact travel documents, or Health values by default. Use generic phrasing and user-controlled privacy settings.

## 10. Airline branding

Keep third-party brand assets isolated. Private use does not justify mixing trademarks into reusable core components. A distributable build may require replacement/review.

## 11. Data retention

User controls retention. Do not auto-delete history merely to simplify storage. Derived caches may be purged and rebuilt.
