import SwiftUI
import SunnieShared

/// Semantic design tokens.
///
/// **This is the seam for the visual design pass.** Every screen references
/// roles — `theme.color.surface`, `Space.m`, `Radius.card` — and never a literal
/// colour or number. Replacing the artwork and palette means changing values
/// here and in the theme content pack, not editing feature views.
///
/// Colours arrive from the resolved theme, which already accounts for the time
/// phase and high-contrast settings, so views make no appearance decisions at all.
extension EnvironmentValues {
    @Entry var sunnieTheme: SunnieTheme = .placeholder
}

/// The rendering-ready form of `ResolvedTheme`.
struct SunnieTheme: Equatable {
    let color: Palette
    let cardCornerRadius: CGFloat
    let timeContext: TimeContext
    let sunnieOutfitID: ContentID?

    struct Palette: Equatable {
        let canvas: Color
        let surface: Color
        let surfaceRaised: Color
        let textPrimary: Color
        let textSecondary: Color
        let accentWarm: Color
        let accentSunnie: Color
        let accentCalm: Color
        let accentPlant: Color
        let accentTravel: Color
        let success: Color
        let attention: Color
        let error: Color
    }

    init(resolved: ResolvedTheme) {
        let palette = resolved.palette
        self.color = Palette(
            canvas: Color(palette.canvas),
            surface: Color(palette.surface),
            surfaceRaised: Color(palette.surfaceRaised),
            textPrimary: Color(palette.textPrimary),
            textSecondary: Color(palette.textSecondary),
            accentWarm: Color(palette.accentWarm),
            accentSunnie: Color(palette.accentSunnie),
            accentCalm: Color(palette.accentCalm),
            accentPlant: Color(palette.accentPlant),
            accentTravel: Color(palette.accentTravel),
            success: Color(palette.success),
            attention: Color(palette.attention),
            error: Color(palette.error)
        )
        self.cardCornerRadius = CGFloat(resolved.cardCornerRadius)
        self.timeContext = resolved.timeContext
        self.sunnieOutfitID = resolved.sunnieOutfitID
    }

    /// Used before the real theme resolves and in previews.
    static let placeholder: SunnieTheme = {
        let engine = ThemeEngine(registry: ContentRegistry.builtIn())
        let time = TimePhaseEngine().resolve(
            at: Date(),
            preferences: .default,
            timeZone: .current,
            reduceMotion: false
        )
        return SunnieTheme(resolved: engine.resolve(
            themeID: ThemeCatalog.lushTropicalJungleID,
            timeContext: time,
            highContrast: false
        ))
    }()

    /// True when the current palette is dark, so components can pick a
    /// contrasting treatment without re-deriving it from the phase.
    var prefersDarkContent: Bool {
        switch timeContext.phase {
        case .evening, .night, .lateNight: true
        case .morning, .day, .afternoon: false
        }
    }
}

extension Color {
    /// Falls back to a visible neutral rather than trapping on a malformed hex.
    /// Content validation catches bad values at test time; at runtime a wrong
    /// colour beats a crash.
    init(_ value: ColorValue) {
        guard let components = value.components else {
            self = .gray
            return
        }
        self = Color(
            .sRGB,
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: components.alpha
        )
    }
}

/// 8-point base grid with 4-point exceptions (VISUAL_DESIGN_SYSTEM.md §5).
enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum Radius {
    /// Cards use 20–28pt continuous corners; the exact value comes from the theme.
    static let chip: CGFloat = 999
    static let button: CGFloat = 16
    static let image: CGFloat = 12
}

/// Type roles. System fonts for the initial build, rounded for headings
/// (VISUAL_DESIGN_SYSTEM.md §4). All sizes scale with Dynamic Type — nothing here
/// is a fixed point size.
enum SunnieFont {
    static let screenTitle = Font.system(.largeTitle, design: .rounded, weight: .semibold)
    static let sectionTitle = Font.system(.title3, design: .rounded, weight: .semibold)
    static let cardTitle = Font.system(.headline, design: .rounded)
    static let body = Font.system(.body)
    static let secondary = Font.system(.subheadline)
    static let caption = Font.system(.caption)
    /// Monospaced digits keep timers and counts from jittering as they change.
    static let numeric = Font.system(.body, design: .monospaced)
}

/// Subtle warm elevation. Shadow never carries meaning on its own
/// (VISUAL_DESIGN_SYSTEM.md §7).
enum Elevation {
    static func card(isDark: Bool) -> (radius: CGFloat, y: CGFloat, opacity: Double) {
        // Dark presentations separate surfaces tonally instead of by shadow.
        isDark ? (radius: 0, y: 0, opacity: 0) : (radius: 8, y: 2, opacity: 0.06)
    }
}
