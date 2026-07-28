import SwiftUI
import SunnieShared

// MARK: - Card

/// The standard dashboard card container.
///
/// Placeholder presentation pending the visual design pass. What is *not*
/// placeholder is the structure: every card answers what it is, what state it is
/// in, and what to do next, and detail lives behind navigation rather than being
/// crammed in (VISUAL_DESIGN_SYSTEM.md §9).
struct SunnieCard<Content: View>: View {
    @Environment(\.sunnieTheme) private var theme

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let elevation = Elevation.card(isDark: theme.prefersDarkContent)

        VStack(alignment: .leading, spacing: Space.s) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                .fill(theme.color.surface)
        )
        .shadow(
            color: .black.opacity(elevation.opacity),
            radius: elevation.radius,
            y: elevation.y
        )
    }
}

// MARK: - Section header

struct SectionHeader: View {
    @Environment(\.sunnieTheme) private var theme

    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(title)
                .font(SunnieFont.sectionTitle)
                .foregroundStyle(theme.color.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One header, one VoiceOver stop.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Status chip

/// A compact state indicator.
///
/// Colour is never the only cue — each style carries a symbol and a text label
/// too, so the state survives greyscale, low vision, and VoiceOver
/// (THEMES_AND_TIME_OF_DAY.md §9).
struct StatusChip: View {
    @Environment(\.sunnieTheme) private var theme

    enum Style {
        case neutral
        case attention
        case done
    }

    let text: String
    let style: Style

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbolName)
        }
        .font(SunnieFont.caption)
        .foregroundStyle(foreground)
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xxs)
        .background(Capsule().fill(background))
        .accessibilityElement(children: .combine)
    }

    private var symbolName: String {
        switch style {
        case .neutral: "clock"
        case .attention: "drop"
        case .done: "checkmark.circle.fill"
        }
    }

    private var foreground: Color {
        switch style {
        case .neutral: theme.color.textSecondary
        case .attention: theme.color.attention
        case .done: theme.color.success
        }
    }

    private var background: Color {
        foreground.opacity(theme.prefersDarkContent ? 0.22 : 0.14)
    }
}

// MARK: - Buttons

struct SunniePrimaryButton: View {
    @Environment(\.sunnieTheme) private var theme

    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(SunnieFont.cardTitle)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: Radius.button))
        .tint(theme.color.accentPlant)
        .foregroundStyle(theme.color.textPrimary)
    }
}

struct SunnieSecondaryButton: View {
    @Environment(\.sunnieTheme) private var theme

    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(SunnieFont.body)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: Radius.button))
        .tint(theme.color.textSecondary)
    }
}

// MARK: - Empty state

/// Empty states are useful, not merely decorative — each offers the action that
/// resolves it (VISUAL_DESIGN_SYSTEM.md §13).
struct EmptyStateView: View {
    @Environment(\.sunnieTheme) private var theme

    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var visualState: SunnieVisualState = .idle

    var body: some View {
        VStack(spacing: Space.m) {
            SunnieAvatarView(state: visualState.withPresence(.medium))

            VStack(spacing: Space.xs) {
                Text(title)
                    .font(SunnieFont.cardTitle)
                    .foregroundStyle(theme.color.textPrimary)
                Text(message)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                SunnieSecondaryButton(title: actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xl)
    }
}

// MARK: - Loading and error

struct LoadingStateView: View {
    @Environment(\.sunnieTheme) private var theme
    let message: String

    var body: some View {
        HStack(spacing: Space.s) {
            ProgressView()
            Text(message)
                .font(SunnieFont.secondary)
                .foregroundStyle(theme.color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.l)
        .accessibilityElement(children: .combine)
    }
}

/// Error presentation.
///
/// The message says what happened and what is still safe. It never blames the
/// user and never shows a raw framework error string
/// (TONE_COPY_AND_BEHAVIOR.md, error copy).
struct ErrorStateView: View {
    @Environment(\.sunnieTheme) private var theme

    let message: String
    var retryTitle: String?
    var retry: (() -> Void)?

    var body: some View {
        SunnieCard {
            HStack(alignment: .top, spacing: Space.s) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(theme.color.error)
                    .accessibilityHidden(true)
                Text(message)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textPrimary)
            }
            if let retryTitle, let retry {
                SunnieSecondaryButton(title: retryTitle, action: retry)
            }
        }
    }
}
