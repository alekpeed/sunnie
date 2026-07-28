import Foundation

/// An sRGB colour expressed as hex. The shared package must not import SwiftUI,
/// so themes travel as data and the app's design system converts them.
public struct ColorValue: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let hex: String

    public init(stringLiteral value: String) {
        self.hex = value
    }

    public init(hex: String) {
        self.hex = hex
    }

    /// Returns nil for malformed input rather than trapping. Content validation
    /// catches bad values at test time; at runtime the design system falls back
    /// to a safe token instead of crashing.
    public var components: (red: Double, green: Double, blue: Double, alpha: Double)? {
        var cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if cleaned.count == 6 { cleaned += "FF" }
        guard cleaned.count == 8, let value = UInt32(cleaned, radix: 16) else { return nil }
        return (
            red: Double((value >> 24) & 0xFF) / 255,
            green: Double((value >> 16) & 0xFF) / 255,
            blue: Double((value >> 8) & 0xFF) / 255,
            alpha: Double(value & 0xFF) / 255
        )
    }

    public var isWellFormed: Bool { components != nil }
}

/// The semantic colour roles every theme must supply.
///
/// Screens reference roles, never raw hex — that is what lets a new theme drop in
/// without touching feature code (VISUAL_DESIGN_SYSTEM.md §2).
public struct SemanticPalette: Hashable, Sendable, Codable {
    public var canvas: ColorValue
    public var surface: ColorValue
    public var surfaceRaised: ColorValue
    public var textPrimary: ColorValue
    public var textSecondary: ColorValue
    public var accentWarm: ColorValue
    public var accentSunnie: ColorValue
    public var accentCalm: ColorValue
    public var accentPlant: ColorValue
    public var accentTravel: ColorValue
    public var success: ColorValue
    public var attention: ColorValue
    public var error: ColorValue

    public init(
        canvas: ColorValue,
        surface: ColorValue,
        surfaceRaised: ColorValue,
        textPrimary: ColorValue,
        textSecondary: ColorValue,
        accentWarm: ColorValue,
        accentSunnie: ColorValue,
        accentCalm: ColorValue,
        accentPlant: ColorValue,
        accentTravel: ColorValue,
        success: ColorValue,
        attention: ColorValue,
        error: ColorValue
    ) {
        self.canvas = canvas
        self.surface = surface
        self.surfaceRaised = surfaceRaised
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.accentWarm = accentWarm
        self.accentSunnie = accentSunnie
        self.accentCalm = accentCalm
        self.accentPlant = accentPlant
        self.accentTravel = accentTravel
        self.success = success
        self.attention = attention
        self.error = error
    }

    public var allValues: [ColorValue] {
        [canvas, surface, surfaceRaised, textPrimary, textSecondary,
         accentWarm, accentSunnie, accentCalm, accentPlant, accentTravel,
         success, attention, error]
    }
}

/// Per-phase overrides. A variant supplies only what changes; anything omitted
/// falls back to the theme's base palette.
public struct ThemePhaseVariant: Hashable, Sendable, Codable {
    public var phase: TimePhase
    public var canvas: ColorValue?
    public var surface: ColorValue?
    public var textPrimary: ColorValue?
    public var textSecondary: ColorValue?
    public var backgroundAssetID: ContentID?
    public var ambientAudioCueID: ContentID?
    public var sunnieOutfitID: ContentID?

    public init(
        phase: TimePhase,
        canvas: ColorValue? = nil,
        surface: ColorValue? = nil,
        textPrimary: ColorValue? = nil,
        textSecondary: ColorValue? = nil,
        backgroundAssetID: ContentID? = nil,
        ambientAudioCueID: ContentID? = nil,
        sunnieOutfitID: ContentID? = nil
    ) {
        self.phase = phase
        self.canvas = canvas
        self.surface = surface
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.backgroundAssetID = backgroundAssetID
        self.ambientAudioCueID = ambientAudioCueID
        self.sunnieOutfitID = sunnieOutfitID
    }
}

/// A complete theme package (THEMES_AND_TIME_OF_DAY.md §6).
public struct ThemeDefinition: Identifiable, Hashable, Sendable, Codable {
    public let id: ContentID
    public var version: Int
    public var displayNameKey: String
    public var basePalette: SemanticPalette
    /// Overrides applied when the user or system requests increased contrast.
    public var highContrastPalette: SemanticPalette?
    public var phaseVariants: [ThemePhaseVariant]
    public var cardCornerRadius: Double
    public var isUnlockedByDefault: Bool
    /// Explains how a locked theme is earned. Never phrased as a loss.
    public var unlockHintKey: String?
    public var minimumAppVersion: String

    public init(
        id: ContentID,
        version: Int,
        displayNameKey: String,
        basePalette: SemanticPalette,
        highContrastPalette: SemanticPalette? = nil,
        phaseVariants: [ThemePhaseVariant] = [],
        cardCornerRadius: Double = 24,
        isUnlockedByDefault: Bool = true,
        unlockHintKey: String? = nil,
        minimumAppVersion: String = "0.1.0"
    ) {
        self.id = id
        self.version = version
        self.displayNameKey = displayNameKey
        self.basePalette = basePalette
        self.highContrastPalette = highContrastPalette
        self.phaseVariants = phaseVariants
        self.cardCornerRadius = cardCornerRadius
        self.isUnlockedByDefault = isUnlockedByDefault
        self.unlockHintKey = unlockHintKey
        self.minimumAppVersion = minimumAppVersion
    }

    public func variant(for phase: TimePhase) -> ThemePhaseVariant? {
        phaseVariants.first { $0.phase == phase }
    }
}

/// The fully resolved appearance for one theme at one moment. This is what the
/// design system renders — no further decisions remain.
public struct ResolvedTheme: Hashable, Sendable {
    public let themeID: ContentID
    public let palette: SemanticPalette
    public let timeContext: TimeContext
    public let backgroundAssetID: ContentID?
    public let ambientAudioCueID: ContentID?
    public let sunnieOutfitID: ContentID?
    public let cardCornerRadius: Double

    public init(
        themeID: ContentID,
        palette: SemanticPalette,
        timeContext: TimeContext,
        backgroundAssetID: ContentID?,
        ambientAudioCueID: ContentID?,
        sunnieOutfitID: ContentID?,
        cardCornerRadius: Double
    ) {
        self.themeID = themeID
        self.palette = palette
        self.timeContext = timeContext
        self.backgroundAssetID = backgroundAssetID
        self.ambientAudioCueID = ambientAudioCueID
        self.sunnieOutfitID = sunnieOutfitID
        self.cardCornerRadius = cardCornerRadius
    }
}

public struct ThemeSelection: Hashable, Sendable, Codable {
    public var activeThemeID: ContentID
    public var selectedAt: Date
    /// Preview overrides do not persist as the active presentation.
    public var previewPhase: TimePhase?

    public init(activeThemeID: ContentID, selectedAt: Date, previewPhase: TimePhase? = nil) {
        self.activeThemeID = activeThemeID
        self.selectedAt = selectedAt
        self.previewPhase = previewPhase
    }
}

/// Stable IDs for the three initial theme families (MASTER_SOURCE_OF_TRUTH.md §7).
public enum ThemeCatalog {
    public static let lushTropicalJungleID: ContentID = "sunnie.theme.lushTropicalJungle"
    public static let travelScrapbookID: ContentID = "sunnie.theme.travelScrapbook"
    public static let dayCycleID: ContentID = "sunnie.theme.dayCycle"
}
