import Foundation

/// Decides whether what the player typed is the answer.
///
/// The games ask for words in four languages, so a strict string comparison
/// would reject `cafe` for `café` and `EL SOL` for `el sol` — accents and case
/// the player may not be able to type on the keyboard they have. Everything here
/// removes a difference that is not part of knowing the answer, and nothing
/// removes a difference that is: `sol` and `sal` stay different words.
public enum AnswerNormalizer {

    /// Punctuation and separators that never distinguish one answer from another.
    private static let ignored = CharacterSet.punctuationCharacters
        .union(.whitespacesAndNewlines)
        .union(CharacterSet(charactersIn: "'’`-–—"))

    /// Lowercases, folds accents, and strips punctuation and spacing.
    ///
    /// Accent folding is done with `.diacriticInsensitive` against a fixed
    /// `Locale(identifier: "en_US_POSIX")` rather than the user's locale: the
    /// answers are content, and folding must give the same result on every
    /// device regardless of the region the phone is set to.
    public static func normalize(_ input: String) -> String {
        let folded = input.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return String(
            folded.unicodeScalars
                .filter { !ignored.contains($0) }
                .map(Character.init)
        )
    }

    /// Whether `input` matches any accepted spelling.
    public static func matches(_ input: String, accepted: [String]) -> Bool {
        let normalized = normalize(input)
        guard !normalized.isEmpty else { return false }
        return accepted.contains { normalize($0) == normalized }
    }

    /// How close a near-miss is, as a count of single-character edits.
    ///
    /// Used only to decide whether to say "that's very close" rather than
    /// silently rejecting — never to accept an answer the player did not give,
    /// and never to score. A typo deserves a nudge, not a mark.
    public static func isNearMiss(_ input: String, accepted: [String]) -> Bool {
        let normalized = normalize(input)
        guard normalized.count >= 4 else { return false }
        return accepted.contains { candidate in
            let target = normalize(candidate)
            guard abs(target.count - normalized.count) <= 1 else { return false }
            return editDistance(normalized, target) == 1
        }
    }

    /// Levenshtein distance, two rows at a time.
    ///
    /// Only ever called on short words, and only to distinguish "1" from
    /// "more than 1", so it exits early once the distance cannot be 1.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let left = Array(a)
        let right = Array(b)
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }

        var previous = Array(0...right.count)
        var current = [Int](repeating: 0, count: right.count + 1)

        for i in 1...left.count {
            current[0] = i
            for j in 1...right.count {
                let substitution = previous[j - 1] + (left[i - 1] == right[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }
}
