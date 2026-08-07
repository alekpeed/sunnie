import SwiftUI
import SunnieShared

/// Tells the audio layer which screen the user is on
/// (AUDIO_MIDI_AND_SOUNDSCAPES.md §5).
///
/// A modifier rather than a call in each screen's `.task`, because the thing that
/// most often goes wrong with context-driven audio is a screen that announces
/// itself on the way in and forgets to on the way out — leaving the game's bed
/// playing over the plants. Attached to the view's lifetime, that cannot happen:
/// appearing sets the context and the next screen replaces it.
///
/// Sets a context; does not start anything. With autoplay off — the default (§6)
/// — this only ever *stops* what a previous screen started, which is exactly the
/// behaviour someone who never turned sound on should get.
private struct AudioContextModifier: ViewModifier {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppState.self) private var appState

    let contexts: [AudioContextTag]

    func body(content: Content) -> some View {
        content
            .task(id: appState.timeContext.presentation) {
                await dependencies.audioService.setContexts(
                    contexts,
                    cycle: appState.timeContext.presentation,
                    themeID: appState.preferences.activeThemeID
                )
            }
    }
}

extension View {
    /// Declares the audio contexts this screen is in.
    ///
    /// The branded cycle and the active theme are added for you, so a screen
    /// names only what is specific to it. That also means a screen can never
    /// spell a cycle tag wrong, or reach for one the product does not have —
    /// there is no Sunnie Morning to pass.
    func audioContext(_ contexts: AudioContextTag...) -> some View {
        modifier(AudioContextModifier(contexts: contexts))
    }
}
