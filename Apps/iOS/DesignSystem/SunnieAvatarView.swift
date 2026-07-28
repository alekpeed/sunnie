import SwiftUI
import SunnieShared

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

    let state: SunnieVisualState

    var body: some View {
        Group {
            if state.presence == .hidden {
                EmptyView()
            } else {
                avatar
            }
        }
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
        // Sunnie is companionship, not information. Anything he expresses is
        // also available as text elsewhere on the screen, so VoiceOver users
        // lose nothing by skipping him.
        .accessibilityAddTraits(.isImage)
    }

    private var size: CGFloat {
        switch state.presence {
        case .prominent: 132
        case .medium: 88
        case .small: 56
        case .minimal: 36
        case .hidden: 0
        }
    }

    /// A stand-in mapping from expression to SF Symbol. Replaced wholesale by
    /// the layered character art.
    private var symbolName: String {
        switch state.expression {
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

    /// Motion stops entirely under Reduce Motion, and the time engine already
    /// calms it down at night.
    private var breathing: Bool {
        !reduceMotion && state.animationIntensity > 0.4
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
                "sunnie.expression.\(state.expression.rawValue)",
                value: expressionDescription,
                comment: "Plain description of Sunnie's expression"
            )
        )
    }

    private var expressionDescription: String {
        switch state.expression {
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
        // Sunnie's words are the content; his portrait is decoration around it.
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
