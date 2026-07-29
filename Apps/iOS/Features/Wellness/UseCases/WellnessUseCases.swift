import Foundation
import SunnieShared

/// Records a check-in.
///
/// The response rules are as much a part of this use case as the save
/// (WELLNESS_JOURNAL_AND_CALM.md §3): acknowledge the entry, do not reinterpret
/// or challenge what was recorded, offer at most one optional next step, and
/// soften Sunnie's voice when the entry describes a harder moment.
struct RecordWellnessCheckIn: Sendable {

    struct Result: Sendable {
        let checkIn: WellnessCheckIn
        /// False when this check-in had already been recorded — a redelivered
        /// save or a double tap. Presented to the user as success either way.
        let wasNewlyRecorded: Bool
        let progression: ProgressionOutcome
        /// Sunnie's acknowledgement. Never a reinterpretation of the answer.
        let message: SunnieMessage?
        /// At most one, and always dismissible.
        let suggestion: Suggestion?
    }

    /// A single optional next step. Never more than one, never insistent.
    enum Suggestion: Hashable, Sendable {
        case breathing(ContentID)
        case journal
        case calmSounds
    }

    private let repository: any WellnessRepository
    private let preferencesRepository: any PreferencesRepository
    private let progressionEngine: ProgressionEngine
    private let messageProvider: any SunnieMessageProviding
    private let timeResolver: any TimePhaseResolving
    private let eventPublisher: any DomainEventPublishing
    private let summaryProvider: WellnessSummaryProvider
    private let clock: any SunnieClock
    private let deviceID: DeviceID

    init(
        repository: any WellnessRepository,
        preferencesRepository: any PreferencesRepository,
        progressionEngine: ProgressionEngine,
        messageProvider: any SunnieMessageProviding,
        timeResolver: any TimePhaseResolving,
        eventPublisher: any DomainEventPublishing,
        summaryProvider: WellnessSummaryProvider,
        clock: any SunnieClock,
        deviceID: DeviceID
    ) {
        self.repository = repository
        self.preferencesRepository = preferencesRepository
        self.progressionEngine = progressionEngine
        self.messageProvider = messageProvider
        self.timeResolver = timeResolver
        self.eventPublisher = eventPublisher
        self.summaryProvider = summaryProvider
        self.clock = clock
        self.deviceID = deviceID
    }

    func callAsFunction(
        mood: WellnessScaleValue? = nil,
        energy: WellnessScaleValue? = nil,
        stress: WellnessScaleValue? = nil,
        sleepQuality: WellnessScaleValue? = nil,
        note: String? = nil,
        recordedAt: Date? = nil
    ) async throws -> Result {
        let now = clock.now
        let timestamp = recordedAt ?? now

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let checkIn = WellnessCheckIn(
            recordedAt: timestamp,
            timeZoneID: clock.timeZone.identifier,
            mood: mood,
            energy: energy,
            stress: stress,
            sleepQuality: sleepQuality,
            note: (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote,
            sourceDeviceID: deviceID,
            actionKey: ActionKeyFactory.wellnessCheckIn(recordedAt: timestamp),
            createdAt: now
        )

        // An entirely blank entry is not saved. Recording one thing is enough,
        // but recording nothing is not an entry.
        guard !checkIn.isEmpty else {
            throw DomainError.validationFailed(reason: .emptyName)
        }

        let outcome = try await repository.save(checkIn)
        let stored = outcome.value

        guard outcome.wasCreated else {
            return Result(
                checkIn: stored,
                wasNewlyRecorded: false,
                progression: .skippedAsDuplicate(existingKey: checkIn.actionKey.rawValue),
                message: try? await acknowledgement(for: stored),
                suggestion: nil
            )
        }

        let progression = await awardProgression(for: stored)

        await eventPublisher.publish(
            DomainEvent(
                type: .wellnessCheckInRecorded,
                occurredAt: timestamp,
                sourceEntityID: stored.id,
                deterministicKey: stored.actionKey.rawValue
            )
        )
        await summaryProvider.invalidate()

        return Result(
            checkIn: stored,
            wasNewlyRecorded: true,
            progression: progression,
            message: try? await acknowledgement(for: stored),
            suggestion: suggestion(for: stored)
        )
    }

    /// Sunnie's reply.
    ///
    /// A harder entry suppresses the nickname — the same warm word that lands
    /// well on a good day reads as trivializing on a bad one.
    private func acknowledgement(for checkIn: WellnessCheckIn) async throws -> SunnieMessage? {
        let preferences = try await preferencesRepository.preferences()
        let profile = try await preferencesRepository.profile()

        let timeContext = timeResolver.resolve(
            at: clock.now,
            preferences: preferences,
            timeZone: clock.timeZone,
            reduceMotion: preferences.accessibility.forceReducedMotion
        )

        return messageProvider.message(for: SunnieMessageContext(
            category: .casualAffirmation,
            timeContext: timeContext,
            displayName: profile.displayName,
            nickname: profile.preferredNickname,
            nicknameProbability: preferences.nicknameProbability,
            isSensitiveMoment: checkIn.suggestsSensitiveMoment
        ))
    }

    /// Exactly one optional next step, chosen from what the user recorded.
    ///
    /// Never framed as a prescription — the UI presents it as an offer that can
    /// be dismissed without acting on it.
    private func suggestion(for checkIn: WellnessCheckIn) -> Suggestion? {
        if let stress = checkIn.stress, stress >= .four {
            return .breathing("sunnie.breathing.longerExhale")
        }
        if let energy = checkIn.energy, energy <= .two {
            return .calmSounds
        }
        if checkIn.note != nil {
            return .journal
        }
        return nil
    }

    private func awardProgression(for checkIn: WellnessCheckIn) async -> ProgressionOutcome {
        do {
            return try await progressionEngine.award(
                type: .wellnessCheckInRecorded,
                sourceEntityID: checkIn.id,
                occurredAt: checkIn.recordedAt,
                deterministicKey: ActionKeyFactory.progression(
                    type: .wellnessCheckInRecorded,
                    sourceActionKey: checkIn.actionKey
                )
            )
        } catch {
            // Progression must never break the flow; the entry is already saved.
            return .skippedAsDuplicate(existingKey: checkIn.actionKey.rawValue)
        }
    }
}

/// Starts and finishes a calming practice.
///
/// The session is written when the practice *starts*, not when it ends. A
/// meditation interrupted by the app being killed then still exists in history
/// with no end date, rather than vanishing as though it never happened.
struct ManageWellnessSession: Sendable {

    private let repository: any WellnessRepository
    private let summaryProvider: WellnessSummaryProvider
    private let audio: any AudioPlaying
    private let clock: any SunnieClock
    private let deviceID: DeviceID

    init(
        repository: any WellnessRepository,
        summaryProvider: WellnessSummaryProvider,
        audio: any AudioPlaying,
        clock: any SunnieClock,
        deviceID: DeviceID
    ) {
        self.repository = repository
        self.summaryProvider = summaryProvider
        self.audio = audio
        self.clock = clock
        self.deviceID = deviceID
    }

    func start(
        type: WellnessSessionType,
        practiceID: ContentID?,
        plannedDuration: TimeInterval,
        startCueID: ContentID? = nil,
        ambienceCueID: ContentID? = nil
    ) async throws -> WellnessSession {
        let id = UUID()
        let session = WellnessSession(
            id: id,
            type: type,
            practiceID: practiceID,
            startedAt: clock.now,
            plannedDuration: plannedDuration,
            audioCueID: ambienceCueID,
            sourceDeviceID: deviceID,
            actionKey: ActionKeyFactory.wellnessSession(sessionID: id)
        )

        _ = try await repository.save(session)

        if let startCueID { await audio.playCue(startCueID) }
        if let ambienceCueID { await audio.startAmbience(ambienceCueID) }

        return session
    }

    /// Ends a session.
    ///
    /// `completion` distinguishes finishing from stopping early, but both are
    /// recorded the same way and neither is treated as better. Leaving a practice
    /// partway is a legitimate outcome.
    @discardableResult
    func finish(
        _ session: WellnessSession,
        completion: WellnessSessionCompletion,
        endCueID: ContentID? = nil
    ) async throws -> WellnessSession {
        var updated = session
        updated.endedAt = clock.now
        updated.completion = completion

        try await repository.update(updated)
        await audio.stopAmbience()

        if completion == .completed, let endCueID {
            await audio.playCue(endCueID)
        }

        await summaryProvider.invalidate()
        return updated
    }
}
