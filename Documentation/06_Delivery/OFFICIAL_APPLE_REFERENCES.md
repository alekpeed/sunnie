# Official Apple Technical References

These links are starting points. Claude Code must verify current API signatures and availability in the installed SDK before implementation.

## Swift and interface

- SwiftUI: https://developer.apple.com/documentation/swiftui
- SwiftUI tutorials: https://developer.apple.com/tutorials/swiftui

## Persistence and cloud

- SwiftData: https://developer.apple.com/documentation/swiftdata
- Preserving model data: https://developer.apple.com/documentation/swiftdata/preserving-your-apps-model-data-across-launches
- Syncing SwiftData across devices: https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices
- CloudKit: https://developer.apple.com/documentation/cloudkit
- CloudKit private database: https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase

## Health and Watch

- HealthKit: https://developer.apple.com/documentation/healthkit
- Setting up HealthKit: https://developer.apple.com/documentation/healthkit/setting-up-healthkit
- Reading HealthKit data: https://developer.apple.com/documentation/healthkit/reading-data-from-healthkit
- Saving HealthKit data: https://developer.apple.com/documentation/healthkit/saving-data-to-healthkit
- WatchConnectivity: https://developer.apple.com/documentation/watchconnectivity
- Transferring data with WatchConnectivity: https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity

## Maps, weather, and calendar

- MapKit: https://developer.apple.com/documentation/mapkit
- WeatherKit: https://developer.apple.com/documentation/weatherkit
- EventKit: https://developer.apple.com/documentation/eventkit

## Notifications and system experiences

- UserNotifications: https://developer.apple.com/documentation/usernotifications
- App Intents: https://developer.apple.com/documentation/appintents

## Audio and MIDI

- AVFAudio: https://developer.apple.com/documentation/avfaudio
- Audio Engine: https://developer.apple.com/documentation/avfaudio/audio-engine
- AVAudioEngine: https://developer.apple.com/documentation/avfaudio/avaudioengine
- Core MIDI: https://developer.apple.com/documentation/coremidi

## Implementation notes grounded in Apple documentation

- HealthKit is permission-based and stores health/fitness data across Apple devices.
- SwiftData can synchronize compatible model data through iCloud when required capabilities are configured.
- WatchConnectivity provides immediate messages, application context, queued user-info transfer, and file transfer for different synchronization needs.
- WeatherKit provides current, hourly, daily, and alert data and requires proper provider attribution.
- App Intents exposes app actions to Siri, Shortcuts, widgets, Spotlight, and other system experiences.
- AVAudioEngine supports node-based audio processing and MIDI/sampler workflows.
