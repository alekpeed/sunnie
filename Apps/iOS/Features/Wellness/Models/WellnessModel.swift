import Foundation
import Observation
import SunnieShared

/// Feature model for the Wellness tab.
@MainActor
@Observable
final class WellnessModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(WellnessSummary)
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var affirmation: AffirmationDefinition?
    /// Sunnie's reply to the check-in just recorded, plus its optional next step.
    private(set) var acknowledgement: SunnieMessage?
    private(set) var suggestion: RecordWellnessCheckIn.Suggestion?

    var isCheckInPresented = false

    /// Recently shown affirmations, so the same line does not come back
    /// immediately. Session-scoped on purpose — persisting it would be more
    /// bookkeeping than the problem deserves.
    private var recentAffirmationIDs: [ContentID] = []
    private let recentAffirmationLimit = 5

    private let dependencies: AppDependencies
    private let appState: AppState
    private var eventToken: UUID?

    init(dependencies: AppDependencies, appState: AppState) {
        self.dependencies = dependencies
        self.appState = appState
    }

    func onAppear() async {
        refreshAffirmation()
        await load()

        guard eventToken == nil else { return }
        eventToken = await dependencies.eventBus.subscribe { [weak self] event in
            guard event.type == .wellnessCheckInRecorded else { return }
            await self?.load()
        }
    }

    func onDisappear() async {
        guard let eventToken else { return }
        await dependencies.eventBus.unsubscribe(eventToken)
        self.eventToken = nil
    }

    func load() async {
        if case .loaded = state {} else {
            state = .loading
        }

        do {
            state = .loaded(try await dependencies.wellnessSummaryProvider.summary())
        } catch {
            state = .failed(String(
                localized: "wellness.error.load",
                defaultValue: "I couldn't gather this just now. Everything you've recorded is still here.",
                comment: "Shown when the wellness summary cannot be built"
            ))
        }
    }

    /// Picks a line for the moment.
    ///
    /// A recent harder check-in narrows the library to gentler lines — a bright
    /// affirmation on a bad day is worse than a plain one.
    func refreshAffirmation() {
        let sensitive: Bool
        if case .loaded(let summary) = state {
            sensitive = summary.mostRecentCheckIn?.suggestsSensitiveMoment ?? false
        } else {
            sensitive = false
        }

        let next = dependencies.affirmationService.affirmation(for: .init(
            phase: appState.timeContext.phase,
            isSensitiveMoment: sensitive,
            recentlyShownIDs: recentAffirmationIDs
        ))

        if let next {
            recentAffirmationIDs.append(next.id)
            if recentAffirmationIDs.count > recentAffirmationLimit {
                recentAffirmationIDs.removeFirst()
            }
        }
        affirmation = next
    }

    func recordCheckIn(
        mood: WellnessScaleValue?,
        energy: WellnessScaleValue?,
        stress: WellnessScaleValue?,
        sleepQuality: WellnessScaleValue?,
        note: String?
    ) async {
        do {
            let result = try await dependencies.recordWellnessCheckIn(
                mood: mood,
                energy: energy,
                stress: stress,
                sleepQuality: sleepQuality,
                note: note
            )

            acknowledgement = result.message
            suggestion = result.suggestion
            if result.wasNewlyRecorded {
                dependencies.haptics.success()
            }
            isCheckInPresented = false
            refreshAffirmation()
            await load()
        } catch DomainError.validationFailed {
            // Nothing was entered. Just close; there is nothing to report.
            isCheckInPresented = false
        } catch {
            state = .failed(String(
                localized: "wellness.error.save",
                defaultValue: "That didn't save just now. Nothing else has changed, and you can try again.",
                comment: "Shown when a check-in fails to save"
            ))
        }
    }

    /// Dismisses Sunnie's reply. Always available immediately
    /// (WELLNESS_JOURNAL_AND_CALM.md §3).
    func dismissAcknowledgement() {
        acknowledgement = nil
        suggestion = nil
    }

    var breathingPatterns: [BreathingPattern] {
        dependencies.affirmationService.suggestedBreathingPatterns
    }

    var allBreathingPatterns: [BreathingPattern] {
        dependencies.contentRegistry.wellnessPack.breathingPatterns
    }

    var meditations: [MeditationDefinition] {
        dependencies.contentRegistry.wellnessPack.meditations
    }

    var calmSounds: [CalmSoundDefinition] {
        dependencies.contentRegistry.wellnessPack.calmSounds
    }
}

/// Drives one breathing or meditation session.
///
/// Owns a timer and the session record. The session is written when the practice
/// starts, so leaving the screen — or the app being killed — leaves a real record
/// rather than nothing.
@MainActor
@Observable
final class PracticePlayerModel {

    enum Phase: Equatable {
        case ready
        case inhale
        case holdAfterInhale
        case exhale
        case holdAfterExhale
        case running
        case finished
    }

    private(set) var phase: Phase = .ready
    private(set) var elapsed: TimeInterval = 0
    private(set) var completedCycles = 0
    private(set) var isRunning = false

    let pattern: BreathingPattern?
    let meditation: MeditationDefinition?
    var selectedDuration: TimeInterval

    private var session: WellnessSession?
    private var task: Task<Void, Never>?
    private let dependencies: AppDependencies

    init(
        pattern: BreathingPattern? = nil,
        meditation: MeditationDefinition? = nil,
        dependencies: AppDependencies
    ) {
        self.pattern = pattern
        self.meditation = meditation
        self.dependencies = dependencies
        self.selectedDuration = meditation?.defaultDuration
            ?? pattern?.totalDuration(cycles: pattern?.defaultCycles ?? 0)
            ?? 300
    }

    var title: String {
        if let meditation { return String(localized: .init(meditation.displayNameKey)) }
        if let pattern { return String(localized: .init(pattern.displayNameKey)) }
        return ""
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        elapsed = 0
        completedCycles = 0

        do {
            session = try await dependencies.manageWellnessSession.start(
                type: meditation?.type ?? .breathing,
                practiceID: meditation?.id ?? pattern?.id,
                plannedDuration: selectedDuration,
                startCueID: meditation?.startCueID,
                ambienceCueID: meditation?.ambienceCueID
            )
        } catch {
            // A practice can run without a stored record. Losing the history line
            // is a smaller cost than refusing to let someone breathe.
            SunnieLog(category: .persistence).debug("Could not record the start of a practice.")
        }

        task = Task { [weak self] in
            await self?.run()
        }
    }

    /// Stops the practice. `completed` distinguishes finishing from stopping
    /// early, but the UI presents neither as better than the other.
    func stop(completed: Bool) async {
        task?.cancel()
        task = nil
        isRunning = false
        phase = .finished

        guard let session else { return }
        try? await dependencies.manageWellnessSession.finish(
            session,
            completion: completed ? .completed : .endedEarly,
            endCueID: meditation?.endCueID
        )
        self.session = nil
    }

    /// Called when the screen goes away with a practice still running.
    func abandon() async {
        guard isRunning, let session else { return }
        task?.cancel()
        task = nil
        isRunning = false
        try? await dependencies.manageWellnessSession.finish(
            session, completion: .interrupted
        )
        self.session = nil
    }

    private func run() async {
        let tick: UInt64 = 100_000_000  // 0.1s

        while !Task.isCancelled && elapsed < selectedDuration {
            try? await Task.sleep(nanoseconds: tick)
            guard !Task.isCancelled else { return }
            elapsed += 0.1
            updatePhase()
        }

        guard !Task.isCancelled else { return }
        await stop(completed: true)
    }

    /// Maps elapsed time onto the breathing cycle, so the UI can show which part
    /// of the breath is current without owning any timing logic itself.
    private func updatePhase() {
        guard let pattern, pattern.isWellFormed else {
            phase = .running
            return
        }

        let cycle = pattern.cycleDuration
        completedCycles = Int(elapsed / cycle)
        let position = elapsed.truncatingRemainder(dividingBy: cycle)

        var boundary = pattern.inhaleSeconds
        if position < boundary { phase = .inhale; return }

        boundary += pattern.holdAfterInhaleSeconds
        if position < boundary { phase = .holdAfterInhale; return }

        boundary += pattern.exhaleSeconds
        if position < boundary { phase = .exhale; return }

        phase = .holdAfterExhale
    }

    var remaining: TimeInterval {
        max(0, selectedDuration - elapsed)
    }

    var progress: Double {
        guard selectedDuration > 0 else { return 0 }
        return min(1, elapsed / selectedDuration)
    }
}
