import Foundation

/// Reminder categories (NOTIFICATIONS_AND_REMINDERS.md §2).
public enum ReminderCategory: String, Hashable, Sendable, Codable, CaseIterable {
    case plantCare
    case travelPreparation
    case departureChecklist
    case returnChecklist
    case mealPrep
    case packedFood
    case hydration
    case wellnessRoutine
    case journalPrompt
    case meditationBreathing
    case dailyPuzzle
    case collectionEvent

    /// The most notifications this category may produce in one day, whatever the
    /// cadence level says. A ceiling that no configuration can raise.
    public var dailyMaximum: Int {
        switch self {
        case .hydration: 6
        case .travelPreparation, .departureChecklist, .returnChecklist: 3
        case .plantCare, .mealPrep, .packedFood: 2
        case .wellnessRoutine, .journalPrompt, .meditationBreathing,
             .dailyPuzzle, .collectionEvent: 1
        }
    }

    /// Whether this category is *ever* permitted to sound during quiet hours,
    /// even with explicit user permission.
    ///
    /// Wellness, games, and collectible notifications never bypass quiet hours —
    /// no setting unlocks it, which is why this is a property of the category
    /// rather than a preference (NOTIFICATIONS_AND_REMINDERS.md §8).
    public var mayEverBypassQuietHours: Bool {
        switch self {
        case .wellnessRoutine, .journalPrompt, .meditationBreathing,
             .dailyPuzzle, .collectionEvent:
            false
        case .plantCare, .travelPreparation, .departureChecklist,
             .returnChecklist, .mealPrep, .packedFood, .hydration:
            true
        }
    }

    /// The shortest gap between two reminders for the same task.
    public var minimumReOfferInterval: TimeInterval {
        switch self {
        case .hydration: 60 * 60 * 2
        default: 60 * 60 * 4
        }
    }
}

/// How often a category may re-offer (NOTIFICATIONS_AND_REMINDERS.md §5).
///
/// The level is chosen by the user and read by the planner. Nothing in the
/// planner can raise it — see `ReminderPlan`.
public enum AdaptiveCadenceLevel: Int, Hashable, Sendable, Codable, CaseIterable {
    /// No reminders at all.
    case disabled = 0
    /// One gentle reminder.
    case single = 1
    /// One reminder plus an optional later re-offer.
    case singleWithReOffer = 2
    /// A regular cadence the user configured themselves.
    case regular = 3

    /// How many notifications this level permits per task per day, before the
    /// category ceiling is applied.
    public var dailyAllowance: Int {
        switch self {
        case .disabled: 0
        case .single: 1
        case .singleWithReOffer: 2
        case .regular: Int.max
        }
    }
}

/// Which clock a reminder follows (NOTIFICATIONS_AND_REMINDERS.md §4).
public enum ReminderTimeZonePolicy: String, Hashable, Sendable, Codable, CaseIterable {
    case fixedInstant
    case deviceTimeZone
    case homeTimeZone
    case destinationTimeZone
}

/// What the user did with the last reminder.
///
/// Recorded to decide whether re-offering is useful, never to characterise the
/// user. There is no "ignored" state that the copy could ever refer to.
public enum ReminderResponse: String, Hashable, Sendable, Codable {
    case completed
    case opened
    case snoozed
    case skippedForToday
    case dismissed
    case noResponse
}

/// Everything the planner needs. Passed as one value so planning stays a pure
/// function of stated inputs.
public struct ReminderContext: Hashable, Sendable {
    public let category: ReminderCategory
    public let cadenceLevel: AdaptiveCadenceLevel
    public let desiredFireDate: Date
    public let now: Date
    public let quietHours: QuietHours
    /// The user explicitly allowed this category to sound during quiet hours.
    /// Only meaningful when the category permits it at all.
    public let userGrantedQuietHoursBypass: Bool
    /// Fire dates already scheduled or delivered for this task today.
    public let alreadySentToday: [Date]
    public let lastResponse: ReminderResponse
    /// The user asked not to be reminded again until this moment.
    public let snoozedUntil: Date?
    /// The user chose to skip today. Cleared by the next calendar day.
    public let skippedForDayStartingAt: Date?
    /// The task this reminder is about is already done.
    public let isTaskComplete: Bool

    public init(
        category: ReminderCategory,
        cadenceLevel: AdaptiveCadenceLevel,
        desiredFireDate: Date,
        now: Date,
        quietHours: QuietHours,
        userGrantedQuietHoursBypass: Bool = false,
        alreadySentToday: [Date] = [],
        lastResponse: ReminderResponse = .noResponse,
        snoozedUntil: Date? = nil,
        skippedForDayStartingAt: Date? = nil,
        isTaskComplete: Bool = false
    ) {
        self.category = category
        self.cadenceLevel = cadenceLevel
        self.desiredFireDate = desiredFireDate
        self.now = now
        self.quietHours = quietHours
        self.userGrantedQuietHoursBypass = userGrantedQuietHoursBypass
        self.alreadySentToday = alreadySentToday
        self.lastResponse = lastResponse
        self.snoozedUntil = snoozedUntil
        self.skippedForDayStartingAt = skippedForDayStartingAt
        self.isTaskComplete = isTaskComplete
    }
}

/// The planner's answer.
///
/// **This type is the no-escalation guarantee.** It carries a fire date and
/// nothing else — no cadence level, no urgency, no tone, no "attempt number".
/// There is structurally no channel through which the planner could make a
/// reminder more insistent than the one before it. Frequency adapts; pressure
/// cannot (NOTIFICATIONS_AND_REMINDERS.md §1, §5).
public enum ReminderPlan: Hashable, Sendable {
    case schedule(at: Date)
    case suppress(SuppressionReason)

    /// Why no reminder will be sent. Every one of these is a normal outcome, and
    /// none is ever surfaced to the user as a problem.
    public enum SuppressionReason: String, Hashable, Sendable {
        case cadenceDisabled
        case taskAlreadyComplete
        case skippedForToday
        case snoozed
        case dailyAllowanceReached
        case categoryMaximumReached
        case tooSoonAfterLastReminder
        /// The moment has passed and there is no sensible later slot today.
        case noSuitableTimeRemaining
    }

    public var fireDate: Date? {
        if case .schedule(let date) = self { return date }
        return nil
    }

    public var isScheduled: Bool { fireDate != nil }
}
