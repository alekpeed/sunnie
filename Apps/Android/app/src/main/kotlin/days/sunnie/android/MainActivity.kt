package days.sunnie.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import days.sunnie.android.game.AnswerChainScreen

/**
 * The whole app, for now.
 *
 * This first build plays an answer chain locally against the rules in `:wire` —
 * the same rules the iPhone runs, in a second implementation held to them by the
 * fixtures under `Backend/contract`. It talks to nothing.
 *
 * That is the deliberate first slice. The rules are the part that has to be
 * right before a second player is worth adding, and proving they run correctly
 * on a phone needs no server, no account, and no pairing code. Multiplayer is
 * the next slice, not this one.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface { AnswerChainScreen() }
            }
        }
    }
}
