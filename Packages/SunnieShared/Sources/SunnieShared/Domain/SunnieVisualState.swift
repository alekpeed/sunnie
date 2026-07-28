import Foundation

/// Expressions from the character bible's minimum 2D set
/// (SUNNIE_CHARACTER_BIBLE.md §10).
///
/// Note what is absent: there is no angry, disappointed, scolding, frightened,
/// or distressed expression, and none may be added. Sunnie's emotional register
/// is consistently positive; calm is allowed, negativity is not.
public enum SunnieExpression: String, Hashable, Sendable, Codable, CaseIterable {
    case happyOpenEyed
    case happyClosedEyed
    case sleepyHalfLidded
    case sleeping
    case gentleWave
    case proud
    case curious
    case calmBreathing
    case excitedDiscovery
    case huggingObject
    case thinking
    case traveling
    case caringForPlant
    case celebratingQuietly
    case comforting
}

/// Pose categories from the character bible (§11).
public enum SunniePose: String, Hashable, Sendable, Codable, CaseIterable {
    case standingNeutral
    case sittingNeutral
    case waving
    case stretching
    case sleepingCurled
    case huggingPillow
    case holdingMug
    case holdingWateringCan
    case holdingPassport
    case pullingSuitcase
    case reading
    case meditating
    case pointingAtTask
    case wearingTravelUniform
    case decoratingHome
    case playingGame
}

/// How much of the screen Sunnie occupies. He should feel present without
/// covering essential controls (SUNNIE_CHARACTER_BIBLE.md §13).
public enum SunniePresence: String, Hashable, Sendable, Codable, CaseIterable {
    /// Today and Sunnie Home.
    case prominent
    /// Feature landing screens.
    case medium
    /// Completion reactions.
    case small
    /// Dense forms, maps, tables, settings.
    case minimal
    case hidden
}

/// The semantic description of how Sunnie should appear right now.
///
/// This is the boundary the future animation and 3D systems will consume
/// (TECHNICAL_ARCHITECTURE.md §13). Views resolve this into assets through the
/// asset provider; they never pick file names themselves, and no feature calls
/// a renderer directly.
public struct SunnieVisualState: Hashable, Sendable {
    public let expression: SunnieExpression
    public let pose: SunniePose
    public let presence: SunniePresence
    /// Outfit content ID, e.g. `sunnie.outfit.cozyPajamas`. Nil uses the theme default.
    public let outfitID: ContentID?
    /// Prop overlay content ID, e.g. `sunnie.prop.wateringCan`.
    public let propID: ContentID?
    /// 0 = static art only. Reduce Motion pins this to 0.
    public let animationIntensity: Double

    public init(
        expression: SunnieExpression,
        pose: SunniePose,
        presence: SunniePresence,
        outfitID: ContentID? = nil,
        propID: ContentID? = nil,
        animationIntensity: Double = 1
    ) {
        self.expression = expression
        self.pose = pose
        self.presence = presence
        self.outfitID = outfitID
        self.propID = propID
        self.animationIntensity = animationIntensity
    }

    public static let idle = SunnieVisualState(
        expression: .happyOpenEyed,
        pose: .standingNeutral,
        presence: .medium
    )

    public func withPresence(_ presence: SunniePresence) -> SunnieVisualState {
        SunnieVisualState(
            expression: expression,
            pose: pose,
            presence: presence,
            outfitID: outfitID,
            propID: propID,
            animationIntensity: animationIntensity
        )
    }

    public func withAnimationIntensity(_ intensity: Double) -> SunnieVisualState {
        SunnieVisualState(
            expression: expression,
            pose: pose,
            presence: presence,
            outfitID: outfitID,
            propID: propID,
            animationIntensity: intensity
        )
    }
}
