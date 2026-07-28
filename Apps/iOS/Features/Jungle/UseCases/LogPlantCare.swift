import Foundation
import SunnieShared

/// The complete "I watered this plant" action.
///
/// This is the spine of the first vertical slice. One call carries the flow all
/// the way through: validate, store the event idempotently, recalculate the
/// schedule, evaluate progression once, publish a domain event, refresh Today,
/// pick a Sunnie reaction, and hand the Watch a new snapshot.
///
/// Everything after the local save is best-effort. The user's record is
/// committed to disk before any of it runs, so a missing Watch, a failed
/// progression read, or no network cannot lose what they did
/// (TECHNICAL_ARCHITECTURE.md §12).
struct LogPlantCare: Sendable {

    /// What the caller needs to render the result.
    struct Result: Sendable {
        let event: PlantCareEvent
        /// False when this action had already been recorded — a replayed Watch
        /// transfer or a double tap. The UI treats it the same as success,
        /// because from the user's point of view it did work.
        let wasNewlyRecorded: Bool
        let progression: ProgressionOutcome
        let message: SunnieMessage?
        let updatedSchedule: PlantCareSchedule?
    }

    private let plantRepository: any PlantRepository
    private let careEventRepository: any PlantCareEventRepository
    private let progressionEngine: ProgressionEngine
    private let summaryProvider: PlantSummaryProvider
    private let messageProvider: any SunnieMessageProviding
    private let timeResolver: any TimePhaseResolving
    private let preferencesRepository: any PreferencesRepository
    private let watchSync: any WatchSyncing
    private let eventPublisher: any DomainEventPublishing
    private let clock: any SunnieClock
    private let deviceID: DeviceID

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    /// Tolerance for a timestamp ahead of the clock. Small clock skew between a
    /// Watch and its phone is normal; hours ahead is not, and would poison the
    /// schedule.
    static let futureTolerance: TimeInterval = 60 * 5

    init(
        plantRepository: any PlantRepository,
        careEventRepository: any PlantCareEventRepository,
        progressionEngine: ProgressionEngine,
        summaryProvider: PlantSummaryProvider,
        messageProvider: any SunnieMessageProviding,
        timeResolver: any TimePhaseResolving,
        preferencesRepository: any PreferencesRepository,
        watchSync: any WatchSyncing,
        eventPublisher: any DomainEventPublishing,
        clock: any SunnieClock,
        deviceID: DeviceID
    ) {
        self.plantRepository = plantRepository
        self.careEventRepository = careEventRepository
        self.progressionEngine = progressionEngine
        self.summaryProvider = summaryProvider
        self.messageProvider = messageProvider
        self.timeResolver = timeResolver
        self.preferencesRepository = preferencesRepository
        self.watchSync = watchSync
        self.eventPublisher = eventPublisher
        self.clock = clock
        self.deviceID = deviceID
    }

    func callAsFunction(
        plantID: UUID,
        careType: CareType,
        performedAt: Date? = nil,
        note: String? = nil,
        scheduleID: UUID? = nil,
        actionKey: ActionKey? = nil,
        sourceDeviceID: DeviceID? = nil
    ) async throws -> Result {
        let now = clock.now
        let timestamp = performedAt ?? now

        guard let plant = try await plantRepository.plant(id: plantID) else {
            throw DomainError.notFound(entity: "Plant", id: plantID)
        }
        guard timestamp.timeIntervalSince(now) <= Self.futureTolerance else {
            throw DomainError.validationFailed(reason: .timestampInFuture)
        }

        // A Watch action arrives with its key already generated, so redelivery
        // resolves to the same record. A phone action derives one now.
        let key = actionKey ?? ActionKeyFactory.plantCare(
            plantID: plantID, careType: careType, performedAt: timestamp
        )

        // Read the previous care of this type *before* saving, so the
        // plausibility check compares against history rather than this action.
        let previous = try await careEventRepository.mostRecentEvent(
            forPlantID: plantID, careType: careType
        )

        let event = PlantCareEvent(
            plantID: plantID,
            careType: careType,
            performedAt: timestamp,
            sourceDeviceID: sourceDeviceID ?? deviceID,
            note: note?.isEmpty == true ? nil : note,
            actionKey: key,
            createdAt: now
        )

        let outcome = try await careEventRepository.save(event)
        let storedEvent = outcome.value

        // A duplicate stops here. The schedule was already advanced and
        // progression already evaluated when the original was recorded; doing it
        // again would move the next due date twice.
        guard outcome.wasCreated else {
            log.debug("Care action was already recorded; returning the existing event.")
            return Result(
                event: storedEvent,
                wasNewlyRecorded: false,
                progression: .skippedAsDuplicate(existingKey: key.rawValue),
                message: try? await reaction(),
                updatedSchedule: nil
            )
        }

        let updatedSchedule = try await advanceSchedule(
            plantID: plantID,
            careType: careType,
            scheduleID: scheduleID,
            completedAt: timestamp
        )

        let progression = await evaluateProgression(
            actionKey: key,
            plantID: plantID,
            careType: careType,
            performedAt: timestamp,
            previousCareAt: previous?.performedAt
        )

        await eventPublisher.publish(
            DomainEvent(
                type: .plantCareLogged,
                occurredAt: timestamp,
                sourceEntityID: plantID,
                deterministicKey: key.rawValue
            )
        )

        await summaryProvider.invalidate()
        let message = try? await reaction()
        await pushToWatch()

        log.info("Recorded \(careType.storageKey) for plant \(SunnieLog.identifier(plant.id)).")

        return Result(
            event: storedEvent,
            wasNewlyRecorded: true,
            progression: progression,
            message: message,
            updatedSchedule: updatedSchedule
        )
    }

    // MARK: - Steps

    /// Moves the schedule forward. Prefers the schedule the user acted on;
    /// otherwise finds the enabled one matching this care type.
    private func advanceSchedule(
        plantID: UUID,
        careType: CareType,
        scheduleID: UUID?,
        completedAt: Date
    ) async throws -> PlantCareSchedule? {
        let schedule: PlantCareSchedule?
        if let scheduleID {
            schedule = try await plantRepository.schedule(id: scheduleID)
        } else {
            schedule = try await plantRepository
                .schedules(forPlantID: plantID)
                .first { $0.careType == careType && $0.isEnabled }
        }

        // Logging care for something with no schedule is perfectly normal — the
        // event is still recorded, there is simply nothing to advance.
        guard let schedule else { return nil }

        let updated = CareScheduleCalculator.applyingCompletion(
            to: schedule,
            completedAt: completedAt,
            calendar: clock.calendar,
            timeZone: clock.timeZone
        )
        try await plantRepository.save(updated)
        return updated
    }

    /// Progression must never break the flow. A failure here costs experience,
    /// not the user's record of what they did.
    private func evaluateProgression(
        actionKey: ActionKey,
        plantID: UUID,
        careType: CareType,
        performedAt: Date,
        previousCareAt: Date?
    ) async -> ProgressionOutcome {
        do {
            return try await progressionEngine.evaluatePlantCare(
                actionKey: actionKey,
                plantID: plantID,
                careType: careType,
                performedAt: performedAt,
                previousCareAt: previousCareAt
            )
        } catch {
            log.error("Progression evaluation failed; the care event is still saved.")
            return .skippedAsDuplicate(existingKey: actionKey.rawValue)
        }
    }

    private func reaction() async throws -> SunnieMessage? {
        let preferences = try await preferencesRepository.preferences()
        let profile = try await preferencesRepository.profile()

        let timeContext = timeResolver.resolve(
            at: clock.now,
            preferences: preferences,
            timeZone: clock.timeZone,
            reduceMotion: preferences.accessibility.forceReducedMotion
        )

        return messageProvider.message(for: SunnieMessageContext(
            category: .careCompleted,
            timeContext: timeContext,
            displayName: profile.displayName,
            nickname: profile.preferredNickname,
            nicknameProbability: preferences.nicknameProbability
        ))
    }

    private func pushToWatch() async {
        guard watchSync.isSupported else { return }
        do {
            let summary = try await summaryProvider.summary()
            let preferences = try await preferencesRepository.preferences()
            let timeContext = timeResolver.resolve(
                at: clock.now,
                preferences: preferences,
                timeZone: clock.timeZone,
                reduceMotion: false
            )

            await watchSync.updateApplicationContext(
                WatchApplicationContext(
                    generatedAt: clock.now,
                    dueTasks: summary.actionableTasks
                        .prefix(WatchApplicationContext.maximumDueTasks)
                        .map(WatchDueTask.init(task:)),
                    totalActivePlants: summary.totalActivePlants,
                    dayCyclePresentationKey: timeContext.presentation.rawValue,
                    sunnieGreeting: nil
                )
            )
        } catch {
            // The Watch being out of date is not worth surfacing; the next
            // summary refresh will carry the change.
            log.debug("Could not refresh the Watch context after logging care.")
        }
    }
}
