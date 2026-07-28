import SwiftUI
import SunnieShared

/// Theme picker with day-phase preview.
///
/// **Placeholder presentation** — swatches rather than illustrated previews. The
/// behaviour it proves matters more: every theme can be previewed in every phase
/// without waiting for the clock, which is how the three branded presentations
/// get checked (THEMES_AND_TIME_OF_DAY.md §7, §10).
///
/// Audio never previews without an explicit tap, so opening this screen stays
/// silent.
struct ThemesScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                previewCard
                themeListCard
            }
            .padding(Space.m)
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("more.themes", bundle: .main))
        .onDisappear {
            // A preview must never leak into the live presentation.
            appState.previewPhase = nil
        }
    }

    private var previewCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "themes.preview.title",
                    defaultValue: "Preview the day",
                    comment: "Day-phase preview section"
                ),
                subtitle: String(
                    localized: "themes.preview.subtitle",
                    defaultValue: "See how each part of the day looks, whatever time it is now.",
                    comment: "Explains the phase preview"
                )
            )

            SunnieAvatarView(
                state: SunnieVisualState(
                    expression: appState.timeContext.sunnieExpression,
                    pose: .standingNeutral,
                    presence: .prominent,
                    animationIntensity: appState.timeContext.animationIntensity
                )
            )
            .frame(maxWidth: .infinity)

            Text(LocalizationKeys.dayCycle(appState.timeContext.presentation))
                .font(SunnieFont.cardTitle)
                .foregroundStyle(theme.color.textPrimary)
                .frame(maxWidth: .infinity)

            Picker(
                String(
                    localized: "themes.preview.phase",
                    defaultValue: "Time of day",
                    comment: "Phase preview picker"
                ),
                selection: phaseBinding
            ) {
                Text("themes.preview.now", bundle: .main).tag(TimePhase?.none)
                ForEach(TimePhase.allCases, id: \.self) { phase in
                    Text(LocalizationKeys.timePhase(phase))
                        .tag(TimePhase?.some(phase))
                }
            }
            .pickerStyle(.menu)

            paletteStrip
        }
    }

    private var phaseBinding: Binding<TimePhase?> {
        Binding(
            get: { appState.previewPhase },
            set: { appState.previewPhase = $0 }
        )
    }

    /// A quick read on contrast and tone for the current phase.
    private var paletteStrip: some View {
        HStack(spacing: Space.xxs) {
            ForEach(Array(paletteSwatches.enumerated()), id: \.offset) { _, swatch in
                RoundedRectangle(cornerRadius: Radius.image, style: .continuous)
                    .fill(swatch)
                    .frame(height: 28)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(
            "themes.preview.paletteAccessibility",
            bundle: .main,
            comment: "VoiceOver label for the colour strip"
        ))
    }

    private var paletteSwatches: [Color] {
        [
            theme.color.canvas,
            theme.color.surface,
            theme.color.accentPlant,
            theme.color.accentTravel,
            theme.color.accentCalm,
            theme.color.accentSunnie
        ]
    }

    private var themeListCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "themes.list.title",
                    defaultValue: "Themes",
                    comment: "Theme list section"
                ),
                subtitle: nil
            )

            ForEach(dependencies.themeEngine.availableThemes()) { definition in
                Button {
                    Task { await select(definition) }
                } label: {
                    HStack {
                        Text(LocalizationKeys.themeName(definition))
                            .font(SunnieFont.body)
                            .foregroundStyle(theme.color.textPrimary)
                        Spacer()
                        if definition.id == appState.preferences.activeThemeID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(theme.color.success)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(
                    definition.id == appState.preferences.activeThemeID
                        ? [.isButton, .isSelected]
                        : .isButton
                )
            }
        }
    }

    private func select(_ definition: ThemeDefinition) async {
        var preferences = appState.preferences
        preferences.activeThemeID = definition.id
        await appState.update(preferences: preferences)
        dependencies.haptics.selection()
    }
}
