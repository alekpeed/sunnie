import Foundation

/// A descriptive read on one dimension over a period.
///
/// Every value here is a count of what the user recorded. Nothing is inferred,
/// correlated, or explained — the history describes, it does not diagnose
/// (WELLNESS_JOURNAL_AND_CALM.md §10).
public struct WellnessDistribution: Hashable, Sendable {
    public let dimension: WellnessDimension
    /// How many entries chose each point on the scale.
    public let counts: [WellnessScaleValue: Int]

    public init(dimension: WellnessDimension, counts: [WellnessScaleValue: Int]) {
        self.dimension = dimension
        self.counts = counts
    }

    public var totalEntries: Int {
        counts.values.reduce(0, +)
    }

    /// The value chosen most often, or nil when nothing was recorded or two
    /// values tie. A tie is genuinely ambiguous, and picking one arbitrarily
    /// would put a claim on screen the data does not support.
    public var mostFrequent: WellnessScaleValue? {
        guard let maximum = counts.values.max(), maximum > 0 else { return nil }
        let winners = counts.filter { $0.value == maximum }
        guard winners.count == 1 else { return nil }
        return winners.keys.first
    }

    /// Entries at the more comfortable end of this dimension, accounting for the
    /// fact that stress runs the other way.
    public var easierEndCount: Int {
        counts.reduce(0) { total, entry in
            let isEasier = switch dimension.polarity {
            case .higherIsEasier: entry.key >= .four
            case .lowerIsEasier: entry.key <= .two
            }
            return isEasier ? total + entry.value : total
        }
    }
}

/// The wellness slice of Today and of the history screen.
public struct WellnessSummary: Hashable, Sendable {
    public let periodStart: Date
    public let periodEnd: Date
    public let checkInCount: Int
    public let distributions: [WellnessDistribution]
    /// Total time spent in completed practices.
    public let practiceDuration: TimeInterval
    public let practiceCount: Int
    public let mostRecentCheckIn: WellnessCheckIn?
    /// True when the user has already checked in today. Used to change the
    /// card's offer, never to prompt them into checking in again.
    public let hasCheckedInToday: Bool
    public let generatedAt: Date

    public init(
        periodStart: Date,
        periodEnd: Date,
        checkInCount: Int,
        distributions: [WellnessDistribution],
        practiceDuration: TimeInterval,
        practiceCount: Int,
        mostRecentCheckIn: WellnessCheckIn?,
        hasCheckedInToday: Bool,
        generatedAt: Date
    ) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.checkInCount = checkInCount
        self.distributions = distributions
        self.practiceDuration = practiceDuration
        self.practiceCount = practiceCount
        self.mostRecentCheckIn = mostRecentCheckIn
        self.hasCheckedInToday = hasCheckedInToday
        self.generatedAt = generatedAt
    }

    public static func empty(at date: Date) -> WellnessSummary {
        WellnessSummary(
            periodStart: date,
            periodEnd: date,
            checkInCount: 0,
            distributions: [],
            practiceDuration: 0,
            practiceCount: 0,
            mostRecentCheckIn: nil,
            hasCheckedInToday: false,
            generatedAt: date
        )
    }

    public func distribution(for dimension: WellnessDimension) -> WellnessDistribution? {
        distributions.first { $0.dimension == dimension }
    }

    public var practiceMinutes: Int {
        Int((practiceDuration / 60).rounded())
    }
}

/// Builds summaries from stored records. Pure, so history rendering is testable
/// without a store.
public enum WellnessSummaryBuilder {

    public static func build(
        checkIns: [WellnessCheckIn],
        sessions: [WellnessSession],
        periodStart: Date,
        periodEnd: Date,
        now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> WellnessSummary {
        var zoned = calendar
        zoned.timeZone = timeZone

        let distributions = WellnessDimension.allCases.map { dimension in
            var counts: [WellnessScaleValue: Int] = [:]
            for checkIn in checkIns {
                guard let value = checkIn.value(for: dimension) else { continue }
                counts[value, default: 0] += 1
            }
            return WellnessDistribution(dimension: dimension, counts: counts)
        }

        // Only finished practices count toward the total. An abandoned session
        // is still recorded, but claiming credit for time not spent would make
        // the number meaningless.
        let finished = sessions.filter { $0.completion == .completed }
        let duration = finished.reduce(0.0) { $0 + ($1.actualDuration ?? 0) }

        let mostRecent = checkIns.max { $0.recordedAt < $1.recordedAt }
        let checkedInToday = checkIns.contains {
            zoned.isDate($0.recordedAt, inSameDayAs: now)
        }

        return WellnessSummary(
            periodStart: periodStart,
            periodEnd: periodEnd,
            checkInCount: checkIns.count,
            distributions: distributions,
            practiceDuration: duration,
            practiceCount: finished.count,
            mostRecentCheckIn: mostRecent,
            hasCheckedInToday: checkedInToday,
            generatedAt: now
        )
    }
}
