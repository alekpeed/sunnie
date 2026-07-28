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
    public let nickname: String?
    public let nicknameProbability: Double
    /// Message IDs shown recently, so the service can avoid immediate repeats.
    public let recentlyShownIDs: [ContentID]

    public init(
        category: SunnieMessageCategory,
        timeContext: TimeContext,
        nickname: String?,
        nicknameProbability: Double,
        recentlyShownIDs: [ContentID] = []
    ) {
        self.category = category
        self.timeContext = timeContext
        self.nickname = nickname
        self.nicknameProbability = nicknameProbability
        self.recentlyShownIDs = recentlyShownIDs
    }
}
