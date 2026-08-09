import SwiftUI
import SunnieShared

private struct SunnieWorldEnvironmentKey: EnvironmentKey {
    static let defaultValue: WorldEnvironment? = nil
}

extension EnvironmentValues {
    /// Set only by the Sunnie Home OS container. Other appearances of Sunnie
    /// keep the semantic state supplied by their feature.
    var sunnieWorldEnvironment: WorldEnvironment? {
        get { self[SunnieWorldEnvironmentKey.self] }
        set { self[SunnieWorldEnvironmentKey.self] = newValue }
    }
}

/// Renders Sunnie from his semantic visual state.
///
/// **Placeholder art.** No production Sunnie assets exist yet; this draws a
/// simple shape at the correct size with the right accessibility description.
/// See `AssetsSource/ASSET_MANIFEST.md` for what the real layered art must
/// supply.
///
/// The important part is the contract, not the drawing. Views describe Sunnie
/// semantically — expression, pose, presence — and this is the only place that
/// turns that into pixels. When the layered art lands, and later when animation
/// or 3D replaces it, nothing outside this file changes
/// (TECHNICAL_ARCHITECTURE.md §13).
struct SunnieAvatarView: View {
    @Environment(\.sunnieTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sunnieWorldEnvironment) private var worldEnvironment

    let state: SunnieVisualState

    var body: some View {
        Group {
            if effectiveState.presence == .hidden {
                EmptyView()
            } else {
                avatar
            }
        }
    }

    /// Home is allowed to react to the shared OS context without making the
    /// underlying Home repository own travel or plant state. Outside Sunnie Home
    /// the environment value is nil and the caller's state is untouched.
    private var effectiveState: SunnieVisualState {
        guard let worldEnvironment else { return state }

        let expression: SunnieExpression
        let pose: SunniePose

        switch worldEnvironment {
        case .ordinary:
            return state
        case .plantDay:
            expression = .caringForPlant
            pose = .holdingWateringCan
        case .tripPreparing:
            expression = .traveling
            pose = .pullingSuitcase
        case .tripAway:
            expression = .traveling
            pose = .wearingTravelUniform
        case .tripReturning:
            expression = .happyClosedEyed
            pose = .holdingMug
        }

        return SunnieVisualState(
            expression: expression,
            pose: pose,
            presence: state.presence,
            outfitID: state.outfitID,
            propID: state.propID,
            animationIntensity: state.animationIntensity
        )
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(theme.color.accentSunnie.opacity(0.35))
            Circle()
                .strokeBorder(theme.color.accentSunnie, lineWidth: 2)
            Image(systemName: symbolName)
                .font(.system(size: size * 0.42))
                .foregroundStyle(theme.color.textPrimary)
        }
        .frame(width: size, height: size)
        .scaleEffect(breathing ? 1.02 : 1.0)
        .animation(breathingAnimation, value: breathing)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    private var size: CGFloat {
        switch effectiveState.presence {
        case .prominent: 132
        case .medium: 88
        case .small: 56
        case .minimal: 36
        case .hidden: 0
        }
    }

    private var symbolName: String {
        switch effectiveState.expression {
        case .sleeping, .sleepyHalfLidded: "moon.zzz"
        case .calmBreathing: "wind"
        case .caringForPlant: "leaf"
        case .traveling: "airplane"
        case .celebratingQuietly, .proud: "sparkles"
        case .excitedDiscovery: "star"
        case .curious, .thinking: "questionmark.circle"
        case .comforting, .huggingObject: "heart"
        case .gentleWave: "hand.wave"
        case .happyClosedEyed, .happyOpenEyed: "sun.max"
        }
    }

    private var breathing: Bool {
        !reduceMotion && effectiveState.animationIntensity > 0.4
    }

    private var breathingAnimation: Animation? {
        guard breathing else { return nil }
        return .easeInOut(duration: 2.4).repeatForever(autoreverses: true)
    }

    private var accessibilityLabel: String {
        String(
            format: NSLocalizedString(
                "sunnie.avatar.label",
                value: "Sunnie, %@",
                comment: "Accessibility label for Sunnie's portrait; %@ is his current mood"
            ),
            NSLocalizedString(
                "sunnie.expression.\(effectiveState.expression.rawValue)",
                value: expressionDescription,
                comment: "Plain description of Sunnie's expression"
            )
        )
    }

    private var expressionDescription: String {
        switch effectiveState.expression {
        case .happyOpenEyed, .happyClosedEyed: "looking happy"
        case .sleepyHalfLidded: "looking sleepy"
        case .sleeping: "fast asleep"
        case .gentleWave: "waving hello"
        case .proud: "looking proud"
        case .curious: "looking curious"
        case .calmBreathing: "breathing calmly"
        case .excitedDiscovery: "looking delighted"
        case .huggingObject: "having a hug"
        case .thinking: "thinking"
        case .traveling: "ready to travel"
        case .caringForPlant: "caring for a plant"
        case .celebratingQuietly: "quietly celebrating"
        case .comforting: "being reassuring"
        }
    }
}

/// Sunnie plus a line of his dialogue.
struct SunnieMessageView: View {
    @Environment(\.sunnieTheme) private var theme

    let message: SunnieMessage
    var presence: SunniePresence = .medium

    var body: some View {
        HStack(alignment: .center, spacing: Space.m) {
            SunnieAvatarView(state: message.visualState.withPresence(presence))
            Text(message.text)
                .font(SunnieFont.body)
                .foregroundStyle(theme.color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Presence sizes") {
    VStack(spacing: Space.l) {
        SunnieAvatarView(state: .idle.withPresence(.prominent))
        SunnieAvatarView(state: .idle.withPresence(.medium))
        SunnieAvatarView(state: .idle.withPresence(.small))
    }
    .padding()
}
