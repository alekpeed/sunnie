# Build, Release, and Migration Checklist

## Project configuration

- [ ] Bundle identifiers recorded
- [ ] iOS/watchOS deployment targets correct
- [ ] Signing teams and profiles correct
- [ ] iCloud/CloudKit container correct
- [ ] HealthKit capability and descriptions correct
- [ ] Watch companion association correct
- [ ] App Group configured if widgets/shared summaries use it
- [ ] Background modes limited to required uses
- [ ] WeatherKit entitlement/configuration correct

## Build quality

- [ ] Clean build succeeds
- [ ] iPhone scheme tests pass
- [ ] Watch scheme tests pass
- [ ] Widget target builds
- [ ] No compiler warnings accepted without review
- [ ] Content validation passes
- [ ] Localization validation passes
- [ ] Asset manifest validation passes

## Data

- [ ] Current schema version recorded
- [ ] Migration from every released schema tested
- [ ] In-memory repository tests pass
- [ ] CloudKit development schema validated
- [ ] CloudKit production deployment reviewed
- [ ] Offline create/update/delete tested
- [ ] Export tested
- [ ] Delete-all tested
- [ ] Media cleanup tested

## Integrations

- [ ] Notification denied/authorized paths
- [ ] Health denied/partial/authorized paths
- [ ] Calendar denied/authorized paths
- [ ] Location denied/manual paths
- [ ] Weather attribution displayed
- [ ] Watch paired physical-device tests
- [ ] Widget privacy
- [ ] App Intents run through shared use cases

## Visual and character

- [ ] Sunnie matches canonical young design
- [ ] No mature context art used as final character art
- [ ] All three themes reviewed
- [ ] Sunnie Days presentation reviewed
- [ ] Sunnie Afternoonies presentation reviewed
- [ ] Sunnie Nights presentation reviewed
- [ ] No prohibited day-cycle names in strings/assets
- [ ] Night contrast reviewed

## Accessibility

- [ ] VoiceOver critical flows
- [ ] Dynamic Type largest expected sizes
- [ ] Reduce Motion
- [ ] High contrast
- [ ] Non-color status cues
- [ ] Touch targets
- [ ] Game alternatives
- [ ] Audio captions/visual alternatives

## Privacy

- [ ] Privacy usage descriptions accurate
- [ ] No private text in logs
- [ ] Lock-screen content reviewed
- [ ] No ad/analytics SDK introduced
- [ ] Temporary exports cleaned
- [ ] Airline/private assets isolated

## Audio

- [ ] No unexpected auto-play
- [ ] Audio route/interruption tests
- [ ] Loop tests
- [ ] Source MIDI excluded unless runtime-required
- [ ] Creator/license metadata complete

## Performance

- [ ] 50–100 plant fixture
- [ ] Large care history
- [ ] Large journal/media fixture
- [ ] Theme switching
- [ ] Today cold/local load
- [ ] Memory review
- [ ] Battery/background review

## Beta and release

- [ ] Fresh-install onboarding
- [ ] Upgrade install
- [ ] iCloud account missing
- [ ] Airplane/offline travel use
- [ ] User acceptance feedback incorporated
- [ ] Known limitations documented
- [ ] Changelog updated
- [ ] Version/build numbers updated
- [ ] Release archive validated
