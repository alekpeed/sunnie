package days.sunnie.android.game

import days.sunnie.wire.AnswerChainPuzzle
import days.sunnie.wire.AnswerChainStop

/**
 * One route, hardcoded, so the first build has something to play.
 *
 * **This is a placeholder and should not survive.** The iPhone loads authored
 * content packs, validated in CI; nothing equivalent exists on Android yet, and
 * hardcoding game content is exactly what the project rules say not to do. It is
 * here because proving the rules run correctly on a phone is worth doing before
 * building a content pipeline for a second client, not because a route belongs
 * in a source file.
 *
 * Prompts and hints live here rather than on [AnswerChainStop] because the
 * Kotlin stop deliberately carries only what replay reads — the answer and its
 * accepted spellings. Keeping display content out of it means one rule set to
 * hold in step with Swift rather than two content models.
 */
object SamplePuzzle {

    const val title: String = "Word Layover"

    const val blurb: String =
        "Each answer hands you the next clue. Hints cost nothing but a look, " +
            "and skipping never blocks the route."

    val route: AnswerChainPuzzle = AnswerChainPuzzle(
        listOf(
            AnswerChainStop(answer = "Lisbon", alternates = listOf("Lisboa")),
            AnswerChainStop(answer = "Porto", alternates = listOf("Oporto")),
            AnswerChainStop(answer = "Faro"),
        )
    )

    val prompts: List<String> = listOf(
        "A capital on seven hills, where the trams still climb streets built " +
            "before anyone thought about trams.",
        "Further up the same coast, and the city that lent its name to a " +
            "fortified wine.",
        "The southern city whose old town sits inside its walls, at the far " +
            "end of the same country.",
    )

    val hints: List<String> = listOf(
        "Its name in Portuguese ends in a vowel the English spelling drops.",
        "The wine is spelled the same as the city.",
        "Four letters, and the last stop before the Algarve beaches.",
    )
}
