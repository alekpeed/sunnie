import Foundation

/// Resolves a theme plus a time context into the single value the design system
/// renders (THEMES_AND_TIME_OF_DAY.md §§1, 6).
///
/// The universal time engine and the branded Day-Cycle theme are separate
/// concerns and stay that way here: *every* theme receives phase treatment, and
/// the Day-Cycle theme is simply the one that leans into it hardest.
public struct ThemeEngine: ThemeResolving {

    private let registry: ContentRegistry

    public init(registry: ContentRegistry) {
        self.registry = registry
    }

    public func availableThemes() -> [ThemeDefinition] {
        registry.themePack.themes
    }

    public func theme(id: ContentID) -> ThemeDefinition? {
        registry.theme(id: id)
    }

    public func resolve(
        themeID: ContentID,
        timeContext: TimeContext,
        highContrast: Bool
    ) -> ResolvedTheme {
        // Falling back to the first available theme keeps a stale or removed
        // theme ID from leaving the app unstyled.
        let definition = registry.theme(id: themeID)
            ?? registry.themePack.themes.first
            ?? FallbackContent.themePack.themes[0]

        let variant = definition.variant(for: timeContext.phase)

        // High contrast wins over phase tinting. Night must stay readable, so a
        // decorative variant never overrides a contrast-critical palette
        // (THEMES_AND_TIME_OF_DAY.md §9).
        let palette: SemanticPalette
        if highContrast, let contrastPalette = definition.highContrastPalette {
            palette = contrastPalette
        } else {
            palette = applying(variant: variant, to: definition.basePalette)
        }

        return ResolvedTheme(
            themeID: definition.id,
            palette: palette,
            timeContext: timeContext,
            backgroundAssetID: variant?.backgroundAssetID,
            ambientAudioCueID: timeContext.isQuietHours ? nil : variant?.ambientAudioCueID,
            sunnieOutfitID: variant?.sunnieOutfitID,
            cardCornerRadius: definition.cardCornerRadius
        )
    }

    /// A variant supplies only what changes; everything else comes from the base.
    func applying(
        variant: ThemePhaseVariant?,
        to base: SemanticPalette
    ) -> SemanticPalette {
        guard let variant else { return base }
        var palette = base
        if let canvas = variant.canvas { palette.canvas = canvas }
        if let surface = variant.surface { palette.surface = surface }
        if let textPrimary = variant.textPrimary { palette.textPrimary = textPrimary }
        if let textSecondary = variant.textSecondary { palette.textSecondary = textSecondary }
        return palette
    }
}
