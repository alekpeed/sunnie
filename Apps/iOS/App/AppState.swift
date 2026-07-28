import Foundation
import Observation
import SwiftUI
import SunnieShared

/// Small global state: the things genuinely shared across every feature
/// (TECHNICAL_ARCHITECTURE.md §7).
///
/// Everything else belongs to a feature model. This holds the active profile,
/// preferences, resolved theme, and current time phase — and nothing more.
@MainActor
@Observable
final class AppState {

    private(set) var profile: UserProfile?
    private(set) var preferences: UserPreferences = .default
    private(set) var theme: SunnieTheme = .placeholder
    private(set) var timeContext: TimeContext

    /// A phase the user is previewing in Settings. Overrides the live phase for
    /// display only and is never persisted (THEMES_AND_TIME_OF_DAY.md §7).
    var previewPhase: TimePhase? {
        didSet { refreshTheme() }
    }

    var systemReduceMotion = false {
        didSet { refreshTheme() }
    }

    var systemHighContrast = false {
        didSet { refreshTheme() }
    }

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self.timeContext = dependencies.timeEngine.resolve(
            at: dependencies.clock.now,
            preferences: .default,
            timeZone: dependencies.clock.timeZone,
            reduceMotion: false
        )
        refreshTheme()
    }

    func load() async {
        do {
            profile = try await dependencies.preferencesRepository.profile()
            preferences = try await dependencies.preferencesRepository.preferences()
        } catch {
            // Defaults are already in place; a settings read failing must not
            // keep the app from opening.
            SunnieLog(category: .persistence).error("Could not load preferences at launch.")
        }
        refreshTheme()
        await dependencies.audioService.apply(preferences: preferences.audio)
        dependencies.haptics.setEnabled(preferences.hapticsEnabled)
    }

    func update(preferences newValue: UserPreferences) async {
        preferences = newValue
        refreshTheme()
        await dependencies.audioService.apply(preferences: newValue.audio)
        dependencies.haptics.setEnabled(newValue.hapticsEnabled)

        do {
            try await dependencies.preferencesRepository.save(newValue)
            await dependencies.eventBus.publish(
                DomainEvent(
                    type: .preferencesChanged,
                    occurredAt: dependencies.clock.now,
                    sourceEntityID: nil
                )
            )
        } catch {
            SunnieLog(category: .persistence).error("Could not save preferences.")
        }
    }

    /// Recomputes the phase. Called on a timer and when the app returns to the
    /// foreground, so a presentation does not sit stale across a phase boundary.
    func refreshTimeContext() {
        refreshTheme()
    }

    private func refreshTheme() {
        var effective = preferences
        // A preview pins the phase without touching what is stored.
        if let previewPhase {
            effective.automaticDayCycle = false
            effective.dayCycleOverride = previewPhase
        }

        timeContext = dependencies.timeEngine.resolve(
            at: dependencies.clock.now,
            preferences: effective,
            timeZone: dependencies.clock.timeZone,
            reduceMotion: systemReduceMotion
        )

        theme = SunnieTheme(resolved: dependencies.themeEngine.resolve(
            themeID: preferences.activeThemeID,
            timeContext: timeContext,
            highContrast: systemHighContrast || preferences.accessibility.forceHighContrast
        ))
    }

    /// Greeting shown at the top of Today.
    func greeting() -> SunnieMessage? {
        dependencies.messageService.message(for: SunnieMessageContext(
            category: .greeting,
            timeContext: timeContext,
            displayName: profile?.displayName ?? DefaultProfile.displayName,
            nickname: profile?.preferredNickname,
            nicknameProbability: preferences.nicknameProbability
        ))
    }
}
