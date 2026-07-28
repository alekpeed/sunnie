import Foundation

/// The single place that decides whether a Sunnie message uses "Noonies".
///
/// Two independent gates must both pass. The category gate is absolute — a
/// permission request or a travel document alert can never carry the nickname no
/// matter what the dice say. The probability gate then makes it an occasional
/// warmth rather than a verbal tic (roughly 1 in 20 eligible messages).
public enum NicknameEligibility {

    public static let defaultProbability = 0.05

    /// Whether this moment is *allowed* to use the nickname, before chance.
    public static func isEligible(
        category: SunnieMessageCategory,
        nickname: String?
    ) -> Bool {
        guard let nickname, !nickname.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        return category.isNicknameEligible
    }

    /// Whether this particular message should use it.
    ///
    /// `random` is injected so tests can assert both branches without flaking.
    public static func shouldUseNickname(
        category: SunnieMessageCategory,
        nickname: String?,
        probability: Double,
        random: some RandomSource
    ) -> Bool {
        guard isEligible(category: category, nickname: nickname) else { return false }
        let clamped = min(max(probability, 0), 1)
        if clamped <= 0 { return false }
        if clamped >= 1 { return true }
        return random.nextUnitValue() < clamped
    }

    /// Substitutes the name into a template.
    ///
    /// Templates carry a `{name}` placeholder rather than being stitched from
    /// fragments, so the surrounding sentence stays translatable. When the
    /// nickname is not used, the placeholder resolves to the display name;
    /// leftover placeholders never reach the screen.
    public static func resolve(
        template: String,
        displayName: String,
        nickname: String?,
        useNickname: Bool
    ) -> String {
        let name = useNickname ? (nickname ?? displayName) : displayName
        return template.replacingOccurrences(of: "{name}", with: name)
    }
}
