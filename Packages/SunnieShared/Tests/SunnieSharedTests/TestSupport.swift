import Foundation
@testable import SunnieShared

/// A UTC calendar so schedule assertions do not shift with the machine's locale.
enum TestFixtures {
    static let utc = TimeZone(identifier: "UTC")!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }

    static func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0,
        timeZone: TimeZone = utc
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = timeZone

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: components) else {
            fatalError("Test fixture produced an invalid date")
        }
        return date
    }

    static let plantID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let scheduleID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let phoneDevice = DeviceID(rawValue: "test.phone")
    static let watchDevice = DeviceID(rawValue: "test.watch")

    static func schedule(
        careType: CareType = .water,
        everyDays: Int = 7,
        preferredHour: Int = 9,
        seasonal: SeasonalModifier = .none,
        isEnabled: Bool = true,
        lastCompletedAt: Date? = nil,
        nextDueDate: Date? = nil
    ) -> PlantCareSchedule {
        PlantCareSchedule(
            id: scheduleID,
            plantID: plantID,
            careType: careType,
            recurrence: .everyDays(everyDays),
            seasonalModifier: seasonal,
            preferredHour: preferredHour,
            isEnabled: isEnabled,
            lastCompletedAt: lastCompletedAt,
            nextDueDate: nextDueDate
        )
    }

    static func preferences(
        automaticDayCycle: Bool = true,
        override: TimePhase? = nil,
        quietHours: QuietHours = QuietHours(),
        reduceMotion: Bool = false,
        nightReduction: Double = 0
    ) -> UserPreferences {
        var preferences = UserPreferences.default
        preferences.automaticDayCycle = automaticDayCycle
        preferences.dayCycleOverride = override
        preferences.quietHours = quietHours
        preferences.accessibility = AccessibilityOverrides(
            forceHighContrast: false,
            forceReducedMotion: reduceMotion,
            nightBrightnessReduction: nightReduction
        )
        return preferences
    }

    static func timeContext(phase: TimePhase = .day) -> TimeContext {
        TimePhaseEngine(calendar: calendar).resolve(
            at: date(2026, 7, 15, phase == .day ? 12 : 9),
            preferences: preferences(automaticDayCycle: false, override: phase),
            timeZone: utc,
            reduceMotion: false
        )
    }
}

/// In-memory progression storage with the same uniqueness guarantees the
/// SwiftData implementation must provide.
actor InMemoryProgressionRepository: ProgressionRepository {
    private var storedProfile = ProgressionProfile()
    private var events: [String: ProgressionEvent] = [:]
    private var rewards: [String: RewardGrant] = [:]

    /// Counts how often a save was rejected as a duplicate, so tests can assert
    /// the guard fired rather than inferring it from the absence of an effect.
    private(set) var duplicateEventAttempts = 0

    func profile() async throws -> ProgressionProfile { storedProfile }

    func save(_ profile: ProgressionProfile) async throws {
        storedProfile = profile
    }

    func save(_ event: ProgressionEvent) async throws -> SaveOutcome<ProgressionEvent> {
        if let existing = events[event.deterministicKey] {
            duplicateEventAttempts += 1
            return .alreadyExisted(existing)
        }
        events[event.deterministicKey] = event
        return .created(event)
    }

    func event(deterministicKey: String) async throws -> ProgressionEvent? {
        events[deterministicKey]
    }

    func save(_ grant: RewardGrant) async throws -> SaveOutcome<RewardGrant> {
        if let existing = rewards[grant.deterministicKey] {
            return .alreadyExisted(existing)
        }
        rewards[grant.deterministicKey] = grant
        return .created(grant)
    }

    func grants(limit: Int) async throws -> [RewardGrant] {
        Array(rewards.values.sorted { $0.grantedAt < $1.grantedAt }.prefix(limit))
    }

    /// Every grant, oldest first.
    ///
    /// Deliberately not `grants(limit:)` with a large number: the collection
    /// screen's whole point is that nothing owned is ever hidden, so a mock that
    /// silently capped would let a truncation bug pass.
    func allGrants() async throws -> [RewardGrant] {
        rewards.values.sorted { $0.grantedAt < $1.grantedAt }
    }

    func eventCounts() async throws -> [ProgressionEventType: Int] {
        events.values.reduce(into: [:]) { counts, event in
            counts[event.type, default: 0] += 1
        }
    }

    /// Distinct days on which anything happened, at or after `since`.
    ///
    /// Days rather than timestamps, and de-duplicated, because that is what the
    /// rhythm summary counts — two waterings on one afternoon are one day of
    /// caring, not two.
    func eventDates(since: Date) async throws -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let days = events.values
            .map(\.occurredAt)
            .filter { $0 >= since }
            .map { calendar.startOfDay(for: $0) }
        return Set(days).sorted()
    }

    var eventCount: Int { events.count }
    var rewardCount: Int { rewards.count }
}
