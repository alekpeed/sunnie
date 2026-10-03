package days.sunnie.android.game

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import days.sunnie.wire.AnswerChainEngine
import days.sunnie.wire.GameMove

/**
 * One answer chain, played locally.
 *
 * The board is never held as state. Only the moves are, and the board is
 * recomputed by replaying them — the same discipline the shared package keeps,
 * and the reason a save from an older build cannot corrupt a game. It also means
 * this screen already works the way the multiplayer version will: moves in,
 * board out, no separate copy of the truth to get out of step.
 */
@Composable
fun AnswerChainScreen() {
    val moves = remember { mutableStateListOf<GameMove>() }
    var typed by remember { mutableStateOf("") }

    val board = AnswerChainEngine.replay(SamplePuzzle.route, moves)
    val stops = SamplePuzzle.route.stops

    fun record(action: GameMove.Action) {
        moves.add(
            GameMove(
                ordinal = moves.size,
                stepIndex = board.currentStop,
                action = action,
                atMillis = System.currentTimeMillis(),
            )
        )
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(SamplePuzzle.title, style = MaterialTheme.typography.headlineSmall)
        Text(SamplePuzzle.blurb, style = MaterialTheme.typography.bodyMedium)

        stops.forEachIndexed { index, stop ->
            val state = board.stops.getOrNull(index)
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        "Stop ${index + 1}",
                        style = MaterialTheme.typography.labelMedium,
                    )
                    Text(SamplePuzzle.prompts[index])

                    when {
                        state?.isSolved == true ->
                            Text("${stop.answer} — got it.")
                        state?.wasSkipped == true ->
                            Text("Skipped. The answer was ${stop.answer}.")
                        // A near miss is told apart from an ordinary miss on
                        // purpose: one edit away deserves a nudge, never a mark.
                        state?.lastAnswerWasNearMiss == true ->
                            Text("Very close. Try that one again?")
                        (state?.wrongAttempts ?: 0) > 0 ->
                            Text("Not that one. Have another go whenever you like.")
                    }

                    if ((state?.hintsRevealed ?: 0) > 0) {
                        Text(
                            SamplePuzzle.hints[index],
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            }
        }

        if (board.isComplete) {
            Text("That is the whole route. Nicely done.")
            TextButton(onClick = { moves.clear(); typed = "" }) {
                Text("Play it again")
            }
        } else {
            OutlinedTextField(
                value = typed,
                onValueChange = { typed = it },
                label = { Text("Your answer") },
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics {
                        contentDescription =
                            "Answer for stop ${board.currentStop + 1}"
                    },
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = {
                        record(GameMove.Action.Answer(typed))
                        typed = ""
                    },
                    enabled = typed.isNotBlank(),
                ) {
                    Text("Answer")
                }
                TextButton(onClick = { record(GameMove.Action.Hint) }) {
                    Text("Hint")
                }
                TextButton(
                    onClick = {
                        record(GameMove.Action.Skip)
                        typed = ""
                    },
                ) {
                    Text("Skip")
                }
            }
        }
    }
}
