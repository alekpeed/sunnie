import Foundation

/// The single place that decides whether a Sunnie message uses "Noonies".
///
/// Three independent gates must all pass.
///
/// The **category** gate is absolute: a permission request or a travel document
/// alert can never carry the nickname, no matter what the dice say.
///
/// The **sensitivity** gate is also absolute, and catches what the category
/// cannot. A celebration is nickname-eligible in general, but the same warm word
/// answering a low-mood check-in reads as trivializing, so a sensitive moment
/// suppresses it regardless of category.
///
/// The **probability** gate then makes it an occasional warmth rather than a
/// verbal tic — roughly 1 in 20 otherwise-eligible messages.
public enum NicknameEligibility {

    public static let defaultProbability = 0.05

    /// Whether this moment is *allowed* to use the nickname, before chance.
    public static func isEligible(
        category: SunnieMessageCategory,
        nickname: String?,
        isSensitiveMoment: Bool = false
    ) -> Bool {
        guard let nickname, !nickname.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        guard !isSensitiveMoment else { return false }
        return category.isNicknameEligible
    }

    /// Whether this particular message should use it.
    ///
    /// `random` is injected so tests can assert both branches without flaking.
    public static func shouldUseNickname(
        category: SunnieMessageCategory,
        nickname: String?,
        probability: Double,
        isSensitiveMoment: Bool = false,
        random: some RandomSource
    ) -> Bool {
        guard isEligible(
            category: category,
            nickname: nickname,
            isSensitiveMoment: isSensitiveMoment
        ) else { return false }
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
