import Foundation
import HealthKit
import SunnieShared

/// The HealthKit adapter (HEALTH_WATCH_WIDGETS_AND_INTENTS.md §2–§4).
///
/// An actor, because `HKHealthStore` is not `Sendable` and everything here has to
/// cross a concurrency boundary. Named with the `Sunnie` prefix for the same
/// reason `SunnieWeatherService` is: HealthKit ships types close enough to these
/// names that an unprefixed one resolves ambiguously.
///
/// Three rules this file exists to hold:
///
/// - **Per type, never in bulk.** `requestAuthorization` passes exactly the types
///   it is given. There is no path that asks for everything (§1).
/// - **Absence is not zero.** A type with no data returns a `.none` reading with
///   a nil value, so nothing downstream can render "0 steps" for a day the app
///   was never allowed to look at.
/// - **Nothing is written without a completed user action.** The two write
///   methods are called from a finished session and from an explicit hydration
///   tap, and from nowhere else (§3).
actor SunnieHealthService: HealthProviding {

    private let store = HKHealthStore()
    private var log: SunnieLog { SunnieLog(category: .integrations) }

    nonisolated var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Types

    /// Maps a domain type onto HealthKit's.
    ///
    /// Returns nil for anything this build cannot express, which keeps the domain
    /// enum free to name something before the plumbing exists rather than
    /// pretending the plumbing is there.
    private nonisolated func sampleType(for type: HealthDataType) -> HKObjectType? {
        switch type {
        case .stepCount: HKQuantityType(.stepCount)
        case .sleepAnalysis: HKCategoryType(.sleepAnalysis)
        case .heartRate: HKQuantityType(.heartRate)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        case .workouts: HKObjectType.workoutType()
        case .activeEnergy: HKQuantityType(.activeEnergyBurned)
        case .standTime: HKQuantityType(.appleStandTime)
        case .mindfulSession: HKCategoryType(.mindfulSession)
        case .dietaryWater: HKQuantityType(.dietaryWater)
        }
    }

    private nonisolated func quantityType(for type: HealthDataType) -> HKQuantityType? {
        sampleType(for: type) as? HKQuantityType
    }

    // MARK: - Authorization

    func authorization(for type: HealthDataType) async -> HealthAuthorization {
        guard isAvailable else { return .unavailable }
        // Only write authorization is knowable. HealthKit deliberately does not
        // report read denial, and a screen that claimed to know would be lying
        // (§12).
        guard type.isWritten, let objectType = sampleType(for: type) else {
            return .notDetermined
        }

        switch store.authorizationStatus(for: objectType) {
        case .sharingAuthorized: return .sharingAuthorized
        case .sharingDenied: return .sharingDenied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    @discardableResult
    func requestAuthorization(
        read: Set<HealthDataType>, write: Set<HealthDataType>
    ) async -> [HealthDataType: HealthAuthorization] {
        guard isAvailable else {
            return Dictionary(
                uniqueKeysWithValues: read.union(write).map { ($0, .unavailable) }
            )
        }

        // Only types the app actually writes may be requested for sharing, and
        // only types it reads may be requested for reading. A caller asking for
        // a write on a read-only type is a bug, and silently widening the
        // request would be the worst possible response to it.
        let readTypes = Set(read.filter(\.isRead).compactMap(sampleType(for:)))
        let writeTypes = Set(
            write.filter(\.isWritten).compactMap { sampleType(for: $0) as? HKSampleType }
        )

        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
        } catch {
            // A refusal is not an error and does not reach here; this is the
            // store being unable to ask at all. Either way the app carries on.
            log.error("Health authorization could not be requested.")
        }

        var result: [HealthDataType: HealthAuthorization] = [:]
        for type in read.union(write) {
            result[type] = await authorization(for: type)
        }
        return result
    }

    // MARK: - Reading

    func snapshot(
        types: Set<HealthDataType>, day: Date, calendar: Calendar
    ) async -> HealthSnapshot {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start

        guard isAvailable else {
            return HealthSnapshot(
                generatedAt: day,
                readings: Dictionary(
                    uniqueKeysWithValues: types.map {
                        ($0, HealthReading.absent($0, start: start, end: end))
                    }
                )
            )
        }

        var readings: [HealthDataType: HealthReading] = [:]
        for type in types {
            readings[type] = await read(type, from: start, to: end, now: day)
        }
        return HealthSnapshot(generatedAt: day, readings: readings)
    }

    private func read(
        _ type: HealthDataType, from start: Date, to end: Date, now: Date
    ) async -> HealthReading {
        // A window that has not finished yet is reported as in-progress, which
        // is what stops "today's steps at 9am" being presented as a daily total
        // (§4).
        let coverage: HealthReading.Coverage = now < end ? .inProgress : .complete

        switch type {
        case .sleepAnalysis:
            return await readSleep(from: start, to: end, coverage: coverage)
        case .mindfulSession:
            return await readMindful(from: start, to: end, coverage: coverage)
        case .workouts:
            return await readWorkoutCount(from: start, to: end, coverage: coverage)
        case .heartRate, .restingHeartRate:
            return await readAverage(type, from: start, to: end, coverage: coverage)
        case .stepCount, .activeEnergy, .standTime, .dietaryWater:
            return await readSum(type, from: start, to: end, coverage: coverage)
        }
    }

    private func readSum(
        _ type: HealthDataType, from start: Date, to end: Date,
        coverage: HealthReading.Coverage
    ) async -> HealthReading {
        guard let quantityType = quantityType(for: type) else {
            return .absent(type, start: start, end: end)
        }
        let value = await statistic(
            quantityType, options: .cumulativeSum, from: start, to: end
        ) { statistics in
            statistics.sumQuantity()?.doubleValue(for: self.unit(for: type))
        }
        return reading(type, value: value, coverage: coverage, start: start, end: end)
    }

    private func readAverage(
        _ type: HealthDataType, from start: Date, to end: Date,
        coverage: HealthReading.Coverage
    ) async -> HealthReading {
        guard let quantityType = quantityType(for: type) else {
            return .absent(type, start: start, end: end)
        }
        let value = await statistic(
            quantityType, options: .discreteAverage, from: start, to: end
        ) { statistics in
            statistics.averageQuantity()?.doubleValue(for: self.unit(for: type))
        }
        return reading(type, value: value, coverage: coverage, start: start, end: end)
    }

    /// Runs one statistics query and hands the result to a reducer.
    ///
    /// Bridged with a continuation guarded against double-resume: HealthKit's
    /// completion handler is documented to be called once, and a crash here
    /// would be an app-wide crash rather than a missing number.
    private func statistic(
        _ type: HKQuantityType,
        options: HKStatisticsOptions,
        from start: Date,
        to end: Date,
        reduce: @escaping @Sendable (HKStatistics) -> Double?
    ) async -> Double? {
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: [.strictStartDate]
        )
        return await withCheckedContinuation { continuation in
            let resumed = ResumeGuard()
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options
            ) { _, statistics, _ in
                guard resumed.claim() else { return }
                continuation.resume(returning: statistics.flatMap(reduce))
            }
            store.execute(query)
        }
    }

    /// Sleep, as hours asleep.
    ///
    /// Sums the intervals HealthKit marks as asleep rather than the time between
    /// getting into and out of bed — "in bed" includes reading and lying awake,
    /// and reporting it as sleep would overstate every night.
    private func readSleep(
        from start: Date, to end: Date, coverage: HealthReading.Coverage
    ) async -> HealthReading {
        let samples = await categorySamples(HKCategoryType(.sleepAnalysis), from: start, to: end)
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]

        let seconds = samples
            .filter { asleepValues.contains($0.value) }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

        guard !samples.isEmpty else {
            return .absent(.sleepAnalysis, start: start, end: end)
        }
        return HealthReading(
            type: .sleepAnalysis,
            value: seconds / 3600,
            coverage: coverage,
            start: start,
            end: end
        )
    }

    private func readMindful(
        from start: Date, to end: Date, coverage: HealthReading.Coverage
    ) async -> HealthReading {
        let samples = await categorySamples(HKCategoryType(.mindfulSession), from: start, to: end)
        guard !samples.isEmpty else {
            return .absent(.mindfulSession, start: start, end: end)
        }
        let seconds = samples.reduce(0.0) {
            $0 + $1.endDate.timeIntervalSince($1.startDate)
        }
        return HealthReading(
            type: .mindfulSession,
            value: seconds / 60,
            coverage: coverage,
            start: start,
            end: end
        )
    }

    private func readWorkoutCount(
        from start: Date, to end: Date, coverage: HealthReading.Coverage
    ) async -> HealthReading {
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: [.strictStartDate]
        )
        let samples: [HKSample] = await withCheckedContinuation { continuation in
            let resumed = ResumeGuard()
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, _ in
                guard resumed.claim() else { return }
                continuation.resume(returning: results ?? [])
            }
            store.execute(query)
        }

        guard !samples.isEmpty else {
            return .absent(.workouts, start: start, end: end)
        }
        return HealthReading(
            type: .workouts,
            value: Double(samples.count),
            coverage: coverage,
            start: start,
            end: end
        )
    }

    private func categorySamples(
        _ type: HKCategoryType, from start: Date, to end: Date
    ) async -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: [.strictStartDate]
        )
        return await withCheckedContinuation { continuation in
            let resumed = ResumeGuard()
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, _ in
                guard resumed.claim() else { return }
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
    }

    private nonisolated func unit(for type: HealthDataType) -> HKUnit {
        switch type {
        case .stepCount, .workouts: .count()
        case .heartRate, .restingHeartRate: HKUnit.count().unitDivided(by: .minute())
        case .activeEnergy: .kilocalorie()
        case .standTime, .mindfulSession: .minute()
        case .dietaryWater: .literUnit(with: .milli)
        case .sleepAnalysis: .hour()
        }
    }

    /// Wraps a value into a reading, turning nil into a `.none` coverage.
    ///
    /// Kept in one place so no read path can accidentally report a nil value
    /// alongside a coverage that claims the window was covered.
    private nonisolated func reading(
        _ type: HealthDataType,
        value: Double?,
        coverage: HealthReading.Coverage,
        start: Date,
        end: Date
    ) -> HealthReading {
        guard let value else { return .absent(type, start: start, end: end) }
        return HealthReading(
            type: type, value: value, coverage: coverage, start: start, end: end
        )
    }

    // MARK: - Writing

    func writeMindfulSession(from start: Date, to end: Date) async -> String? {
        guard isAvailable, end > start else { return nil }
        guard await authorization(for: .mindfulSession).canWrite else { return nil }

        let sample = HKCategorySample(
            type: HKCategoryType(.mindfulSession),
            value: HKCategoryValue.notApplicable.rawValue,
            start: start,
            end: end
        )
        return await save(sample)
    }

    func writeWater(millilitres: Int, at date: Date) async -> String? {
        guard isAvailable, millilitres > 0 else { return nil }
        guard await authorization(for: .dietaryWater).canWrite else { return nil }

        let quantity = HKQuantity(
            unit: .literUnit(with: .milli), doubleValue: Double(millilitres)
        )
        let sample = HKQuantitySample(
            type: HKQuantityType(.dietaryWater),
            quantity: quantity,
            start: date,
            end: date
        )
        return await save(sample)
    }

    /// Saves and returns the sample's identifier.
    ///
    /// The identifier is what the caller stores to guarantee it never writes the
    /// same session twice — HealthKit has no deduplication of its own, so two
    /// writes of one meditation would be two mindful sessions in the user's
    /// Health app, which is their data being wrong because of us.
    private func save(_ sample: HKSample) async -> String? {
        do {
            try await store.save(sample)
            return sample.uuid.uuidString
        } catch {
            log.error("Writing a Health sample failed.")
            return nil
        }
    }
}

/// One-shot guard for a continuation resumed from a callback.
///
/// HealthKit's handlers are documented to fire once. This makes a violation a
/// dropped result rather than a crash, which is the right trade for a number on
/// a card.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if hasResumed { return false }
        hasResumed = true
        return true
    }
}
