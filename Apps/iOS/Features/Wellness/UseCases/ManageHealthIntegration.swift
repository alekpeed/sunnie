import Foundation
import SunnieShared

/// The Health integration, from the app's side
/// (HEALTH_WATCH_WIDGETS_AND_INTENTS.md §2–§4, §12).
///
/// Three things live here and nowhere else:
///
/// - **Which types the user has turned on.** Stored as a preference rather than
///   read back from HealthKit, because HealthKit will not tell us about reads
///   (§12). The preference is what the app asked for; the system decides what it
///   actually gets, and the difference simply shows up as absent data.
/// - **Writing a finished practice as a mindful session**, once (§3).
/// - **Hydration**, logged locally first and mirrored to Health when allowed.
struct ManageHealthIntegration: Sendable {

    private let health: any HealthProviding
    private let hydrationRepository: any HydrationRepository
    private let wellnessRepository: any WellnessRepository
    private let preferencesRepository: any PreferencesRepository
    private let clock: any SunnieClock
    private let deviceID: DeviceID

    private var log: SunnieLog { SunnieLog(category: .integrations) }

    init(
        health: any HealthProviding,
        hydrationRepository: any HydrationRepository,
        wellnessRepository: any WellnessRepository,
        preferencesRepository: any PreferencesRepository,
        clock: any SunnieClock,
        deviceID: DeviceID
    ) {
        self.health = health
        self.hydrationRepository = hydrationRepository
        self.wellnessRepository = wellnessRepository
        self.preferencesRepository = preferencesRepository
        self.clock = clock
        self.deviceID = deviceID
    }

    var isAvailable: Bool { health.isAvailable }

    // MARK: - Permissions

    /// The types the user has asked the app to use.
    func enabledTypes() async -> Set<HealthDataType> {
        let preferences = (try? await preferencesRepository.preferences()) ?? .default
        return Set(preferences.healthTypeKeys.compactMap(HealthDataType.init(rawValue:)))
    }

    func writeAuthorization(for type: HealthDataType) async -> HealthAuthorization {
        await health.authorization(for: type)
    }

    /// Turns one type on, asking the system for exactly that type.
    ///
    /// The preference is recorded whatever the system answers. A user who
    /// declines and later changes their mind in the Settings app should find the
    /// data appearing without having to come back here and toggle again — and
    /// the app must not re-prompt, because iOS will not show the sheet twice
    /// anyway and a button that silently does nothing is worse than no button
    /// (§12).
    @discardableResult
    func enable(_ type: HealthDataType) async -> HealthAuthorization {
        var preferences = (try? await preferencesRepository.preferences()) ?? .default
        if !preferences.healthTypeKeys.contains(type.rawValue) {
            preferences.healthTypeKeys.append(type.rawValue)
            try? await preferencesRepository.save(preferences)
        }

        let result = await health.requestAuthorization(
            read: type.isRead ? [type] : [],
            write: type.isWritten ? [type] : []
        )
        return result[type] ?? .notDetermined
    }

    /// Turns one type off.
    ///
    /// Only the app's own preference changes — there is no API to hand a
    /// permission back, and pretending otherwise would be a lie in the copy. The
    /// footer says where the real switch is.
    func disable(_ type: HealthDataType) async {
        var preferences = (try? await preferencesRepository.preferences()) ?? .default
        preferences.healthTypeKeys.removeAll { $0 == type.rawValue }
        try? await preferencesRepository.save(preferences)
    }

    // MARK: - Reading

    /// Today's readings for the types the user turned on.
    ///
    /// Returns an empty snapshot rather than nil when nothing is enabled, so the
    /// caller has one shape to handle.
    func todaySnapshot() async -> HealthSnapshot {
        let types = await enabledTypes()
        guard !types.isEmpty else { return .empty(at: clock.now) }
        return await health.snapshot(types: types, day: clock.now, calendar: clock.calendar)
    }

    /// The lines the wellness screen may show.
    ///
    /// Built through `HealthPhrasing`, which is the only thing in the app allowed
    /// to turn a Health number into words — and which has no way to express a
    /// judgement, a target, or a comparison (§4).
    func todayDescriptors() async -> [HealthPhrasing.Descriptor] {
        let snapshot = await todaySnapshot()
        return HealthDataType.allCases.compactMap { type in
            snapshot.reading(type).flatMap(HealthPhrasing.descriptor(for:))
        }
    }

    // MARK: - Mindful minutes

    /// Writes a finished practice to Health as a mindful session (§3).
    ///
    /// Four guards, all of which have to pass:
    /// the session finished, it was not stopped early, it has not already been
    /// written, and the type is one the user turned on. Anything else is a
    /// no-op — silently, because nobody asked for this and nobody should be told
    /// it did not happen.
    @discardableResult
    func recordMindfulSession(_ session: WellnessSession) async -> String? {
        guard session.healthKitSampleID == nil else { return nil }
        guard session.completion == .completed, let endedAt = session.endedAt else { return nil }
        guard Self.mindfulTypes.contains(session.type) else { return nil }
        guard await enabledTypes().contains(.mindfulSession) else { return nil }

        guard let sampleID = await health.writeMindfulSession(
            from: session.startedAt, to: endedAt
        ) else { return nil }

        var updated = session
        updated.healthKitSampleID = sampleID
        try? await wellnessRepository.update(updated)
        return sampleID
    }

    /// Practices that count as mindful minutes.
    ///
    /// Breathing and meditation, and not the others: calm sounds playing in the
    /// background is not a mindful session, and writing it as one would put a
    /// claim into the user's Health record that they did not make.
    static let mindfulTypes: Set<WellnessSessionType> = [.breathing, .meditation]

    // MARK: - Hydration

    /// Logs water (§3, "after explicit hydration log").
    ///
    /// Stored locally first, always. Writing to Health is a mirror of that
    /// record, not the record itself — the entry belongs to the user whether or
    /// not they granted the permission.
    /// `loggedAt`, `source`, and `actionKey` are supplied for an entry that came
    /// from the Watch, so the wrist's own key travels with it and a redelivered
    /// transfer resolves to the entry already stored rather than a second glass.
    @discardableResult
    func logWater(
        millilitres: Int,
        loggedAt: Date? = nil,
        source: DeviceID? = nil,
        actionKey: ActionKey? = nil
    ) async throws -> HydrationLog {
        let amount = min(max(1, millilitres), HydrationLog.maximumSingleEntry)
        let now = loggedAt ?? clock.now

        let entry = HydrationLog(
            millilitres: amount,
            loggedAt: now,
            sourceDeviceID: source ?? deviceID,
            actionKey: actionKey
                ?? ActionKeyFactory.hydration(millilitres: amount, loggedAt: now)
        )

        let outcome = try await hydrationRepository.save(entry)
        guard outcome.wasCreated else { return outcome.value }

        if await enabledTypes().contains(.dietaryWater),
           let sampleID = await health.writeWater(millilitres: amount, at: now) {
            try? await hydrationRepository.markWritten(id: outcome.value.id, sampleID: sampleID)
        }
        return outcome.value
    }

    /// Today's total, from the app's own records.
    ///
    /// Deliberately not read back from Health: the local log is the app's own
    /// data and works with the permission off, and mixing the two sources would
    /// double-count every entry that was successfully mirrored.
    func todayHydration() async -> Int {
        let start = clock.calendar.startOfDay(for: clock.now)
        let end = clock.calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let logs = (try? await hydrationRepository.logs(from: start, to: end)) ?? []
        return logs.reduce(0) { $0 + $1.millilitres }
    }

    /// Mirrors anything that was logged while the permission was off.
    ///
    /// Runs at launch. Bounded, because a user who turns the permission on after
    /// a year of logging should not have the app spend a minute writing history
    /// into their Health app on the launch that follows.
    static let catchUpLimit = 25

    func catchUpHealthWrites() async {
        guard await enabledTypes().contains(.dietaryWater) else { return }
        guard await health.authorization(for: .dietaryWater).canWrite else { return }

        let pending = (try? await hydrationRepository.unwrittenLogs(limit: Self.catchUpLimit)) ?? []
        for entry in pending {
            guard let sampleID = await health.writeWater(
                millilitres: entry.millilitres, at: entry.loggedAt
            ) else { continue }
            try? await hydrationRepository.markWritten(id: entry.id, sampleID: sampleID)
        }
    }
}
