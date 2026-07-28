import Foundation

/// What kind of moment a Sunnie message belongs to.
///
/// The categories carry the nickname policy: `isNicknameEligible` is the single
/// place that encodes which moments may use "Noonies"
/// (TONE_COPY_AND_BEHAVIOR.md, nickname rule).
public enum SunnieMessageCategory: String, Hashable, Sendable, Codable, CaseIterable {
    case greeting
    case celebration
    case casualAffirmation
    case postcard
    case homeScene
    case careCompleted
    case gentleReminder
    case permissionRequest
    case error
    case privacyNotice
    case healthExplanation
    case travelDocumentAlert

    /// Ineligible categories are the serious and sensitive ones. A nickname in a
    /// permission prompt or a travel document alert reads as flippant, so the
    /// rule is enforced here rather than left to each call site.
    public var isNicknameEligible: Bool {
        switch self {
        case .greeting, .celebration, .casualAffirmation,
             .postcard, .homeScene, .careCompleted:
            true
        case .gentleReminder, .permissionRequest, .error, .privacyNotice,
             .healthExplanation, .travelDocumentAlert:
            false
        }
    }
}

/// A resolved message ready for display.
///
/// `text` is already fully composed. Sentences are never assembled from
/// fragments at runtime, because that does not survive translation
/// (PROJECT_STRUCTURE_AND_CODING_STANDARDS.md §8).
public struct SunnieMessage: Hashable, Sendable, Identifiable {
    public let id: ContentID
    public let text: String
    public let category: SunnieMessageCategory
    public let visualState: SunnieVisualState
    public let usedNickname: Bool

    public init(
        id: ContentID,
        text: String,
        category: SunnieMessageCategory,
        visualState: SunnieVisualState,
        usedNickname: Bool
    ) {
        self.id = id
        self.text = text
        self.category = category
        self.visualState = visualState
        self.usedNickname = usedNickname
    }
}

/// Everything the message service needs to choose a message. Passed as one value
/// so the selection function stays pure and testable.
public struct SunnieMessageContext: Hashable, Sendable {
    public let category: SunnieMessageCategory
    public let timeContext: TimeContext
    /// The name to use when the nickname is not chosen.
    ///
    /// Carried per call rather than captured once by the service: the profile is
    /// editable, and a name captured at app launch would keep Sunnie using the
    /// old one for the rest of the session.
    public let displayName: String
    public let nickname: String?
    public let nicknameProbability: Double
    /// The user has just recorded a harder moment.
    ///
    /// A third nickname gate, on top of category and chance. "Noonies" in a
    /// celebration is warm; the same word answering a low-mood check-in reads as
    /// trivializing, and the category alone cannot tell the two apart
    /// (WELLNESS_JOURNAL_AND_CALM.md §3).
    ///
    /// This is a tone adjustment and nothing more. The app performs no crisis
    /// detection and draws no conclusions about anyone's state (§12).
    public let isSensitiveMoment: Bool
    /// Message IDs shown recently, so the service can avoid immediate repeats.
    public let recentlyShownIDs: [ContentID]

    public init(
        category: SunnieMessageCategory,
        timeContext: TimeContext,
        displayName: String,
        nickname: String?,
        nicknameProbability: Double,
        isSensitiveMoment: Bool = false,
        recentlyShownIDs: [ContentID] = []
    ) {
        self.category = category
        self.timeContext = timeContext
        self.displayName = displayName
        self.nickname = nickname
        self.nicknameProbability = nicknameProbability
        self.isSensitiveMoment = isSensitiveMoment
        self.recentlyShownIDs = recentlyShownIDs
    }
}
