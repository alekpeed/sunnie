package days.sunnie.wire

import java.text.Normalizer
import java.util.Locale
import kotlin.math.abs

/**
 * Decides whether what the player typed is the answer.
 *
 * A port of `AnswerNormalizer` in the Swift shared package, and the second thing
 * in this feature that exists twice and can drift (ADR-035). The wire format is
 * held together by `Backend/contract/move-fixtures.json`; this is held together
 * by `Backend/contract/answer-fixtures.json`, which both test suites read.
 *
 * Drift here would be worse than drift in the wire format, and quieter. A move
 * that fails to decode is visibly broken. A rule that accepts "cafe" for "café"
 * on one phone and rejects it on the other is a game where one player is simply
 * wrong more often, with nothing on screen to explain why.
 *
 * The intent, unchanged from Swift: remove every difference that is not part of
 * knowing the answer, and no difference that is. `sol` and `sal` stay different
 * words.
 */
object AnswerNormalizer {

    /**
     * Lowercases, folds accents, and strips punctuation and spacing.
     *
     * Mirrors Swift's `folding(options: [.diacriticInsensitive, .caseInsensitive,
     * .widthInsensitive], locale: en_US_POSIX)` in three explicit steps, because
     * the JVM has no single equivalent:
     *
     *  - **NFKD** decomposes accented letters into base plus combining mark, and
     *    is the *compatibility* form, which is what folds full-width characters
     *    to half-width — Swift's `.widthInsensitive`.
     *  - Combining marks (Unicode category Mn) are then dropped, which is the
     *    accent folding itself.
     *  - Lowercasing uses [Locale.ROOT], never the device locale. The answers are
     *    content and must fold identically on every phone; a Turkish locale
     *    lowercases `I` to `ı` and would quietly change what counts as correct.
     *    Swift pins `en_US_POSIX` for the same reason.
     */
    fun normalize(input: String): String {
        val decomposed = Normalizer.normalize(input, Normalizer.Form.NFKD)
        val builder = StringBuilder(decomposed.length)

        for (character in decomposed) {
            if (isIgnored(character)) continue
            builder.append(character)
        }
        return builder.toString().lowercase(Locale.ROOT)
    }

    /**
     * Characters that never distinguish one answer from another.
     *
     * Checked by Unicode category rather than by a regex class, so it means the
     * same thing as Swift's `CharacterSet.punctuationCharacters` — every general
     * category beginning with P — rather than whatever a given regex flavour
     * happens to call punctuation.
     *
     * The backtick is listed separately and is not an oversight: Swift's set
     * unions it in explicitly, and Unicode classifies U+0060 as a modifier
     * symbol (Sk) rather than punctuation, so a category check alone would keep
     * it and the two implementations would disagree on exactly one character.
     */
    private fun isIgnored(character: Char): Boolean {
        if (character.isWhitespace()) return true
        if (character == '`') return true
        // Combining marks: the accent folding.
        if (character.category == CharCategory.NON_SPACING_MARK) return true

        return when (character.category) {
            CharCategory.CONNECTOR_PUNCTUATION,
            CharCategory.DASH_PUNCTUATION,
            CharCategory.START_PUNCTUATION,
            CharCategory.END_PUNCTUATION,
            CharCategory.INITIAL_QUOTE_PUNCTUATION,
            CharCategory.FINAL_QUOTE_PUNCTUATION,
            CharCategory.OTHER_PUNCTUATION,
            -> true

            else -> false
        }
    }

    /** Whether [input] matches any accepted spelling. */
    fun matches(input: String, accepted: List<String>): Boolean {
        val normalized = normalize(input)
        if (normalized.isEmpty()) return false
        return accepted.any { normalize(it) == normalized }
    }

    /**
     * Whether the answer is one edit away from a correct one.
     *
     * Used only to decide whether to say "that's very close" instead of
     * rejecting silently — never to accept an answer the player did not give,
     * and never to score. A typo deserves a nudge, not a mark.
     *
     * The four-character floor is load-bearing rather than arbitrary: below it,
     * one edit is the difference between most short words, and `sol`/`sal` would
     * read as a near miss.
     */
    fun isNearMiss(input: String, accepted: List<String>): Boolean {
        val normalized = normalize(input)
        if (normalized.length < 4) return false

        return accepted.any { candidate ->
            val target = normalize(candidate)
            if (abs(target.length - normalized.length) > 1) return@any false
            editDistance(normalized, target) == 1
        }
    }

    /** Levenshtein distance, two rows at a time. */
    internal fun editDistance(a: String, b: String): Int {
        if (a.isEmpty()) return b.length
        if (b.isEmpty()) return a.length

        var previous = IntArray(b.length + 1) { it }
        var current = IntArray(b.length + 1)

        for (i in 1..a.length) {
            current[0] = i
            for (j in 1..b.length) {
                val substitution = previous[j - 1] + if (a[i - 1] == b[j - 1]) 0 else 1
                current[j] = minOf(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            val swap = previous
            previous = current
            current = swap
        }
        return previous[b.length]
    }
}
