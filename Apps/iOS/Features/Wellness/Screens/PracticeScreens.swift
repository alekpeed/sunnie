import SwiftUI
import SunnieShared

/// The breathing player.
///
/// **Placeholder presentation** — a circle that scales with the breath. What it
/// gets right regardless of the artwork: the animation stops under Reduce Motion
/// and the phase is announced as text, so the practice is followable without
/// seeing the movement at all.
struct BreathingPlayerScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let pattern: BreathingPattern

    @State private var model: PracticePlayerModel?

    var body: some View {
        VStack(spacing: Space.l) {
            Spacer()

            breathCircle

            Text(phaseLabel)
                .font(SunnieFont.sectionTitle)
                .foregroundStyle(theme.color.textPrimary)
                .accessibilityAddTraits(.updatesFrequently)

            Text(String(localized: .init(pattern.descriptionKey)))
                .font(SunnieFont.secondary)
                .foregroundStyle(theme.color.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()

            if let model, model.isRunning {
                Text(remainingLabel(model.remaining))
                    .font(SunnieFont.numeric)
                    .foregroundStyle(theme.color.textSecondary)

                // Stopping early is presented exactly as neutrally as finishing.
                SunnieSecondaryButton(
                    title: String(
                        localized: "practice.stop",
                        defaultValue: "That's enough for now",
                        comment: "Ends a practice early"
                    ),
                    action: { Task { await model.stop(completed: false) } }
                )
            } else {
                SunniePrimaryButton(
                    title: String(
                        localized: "practice.begin",
                        defaultValue: "Begin",
                        comment: "Starts a practice"
                    ),
                    systemImage: "play",
                    action: { Task { await model?.start() } }
                )
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(String(localized: .init(pattern.displayNameKey)))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                model = PracticePlayerModel(pattern: pattern, dependencies: dependencies)
            }
        }
        .onDisappear {
            // Leaving mid-practice records an interrupted session rather than
            // discarding it.
            Task { await model?.abandon() }
        }
    }

    private var breathCircle: some View {
        let scale = circleScale
        return Circle()
            .fill(theme.color.accentCalm.opacity(0.35))
            .overlay(Circle().strokeBorder(theme.color.accentCalm, lineWidth: 2))
            .frame(width: 180, height: 180)
            .scaleEffect(scale)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: animationDuration),
                value: scale
            )
            .accessibilityHidden(true)
    }

    /// Under Reduce Motion the circle holds still and the text carries the
    /// practice on its own.
    private var circleScale: CGFloat {
        guard !reduceMotion else { return 1 }
        switch model?.phase {
        case .inhale, .holdAfterInhale: 1.25
        default: 0.85
        }
    }

    private var animationDuration: Double {
        switch model?.phase {
        case .inhale: pattern.inhaleSeconds
        case .exhale: pattern.exhaleSeconds
        default: 0.4
        }
    }

    private var phaseLabel: String {
        switch model?.phase {
        case .inhale: String(localized: "breathing.phase.inhale", defaultValue: "Breathe in", comment: "Breathing phase")
        case .holdAfterInhale, .holdAfterExhale:
            String(localized: "breathing.phase.hold", defaultValue: "Hold", comment: "Breathing phase")
        case .exhale: String(localized: "breathing.phase.exhale", defaultValue: "Breathe out", comment: "Breathing phase")
        case .finished: String(localized: "practice.done", defaultValue: "Done", comment: "Practice finished")
        default: String(localized: "practice.ready", defaultValue: "Whenever you're ready", comment: "Practice not started")
        }
    }

    private func remainingLabel(_ remaining: TimeInterval) -> String {
        let seconds = Int(remaining.rounded())
        return String(
            localized: "practice.remaining \(seconds / 60) \(seconds % 60)",
            defaultValue: "\(seconds / 60):\(String(format: "%02d", seconds % 60)) left",
            comment: "Time remaining in a practice"
        )
    }
}

/// The meditation player.
///
/// **Placeholder presentation.** Guidance lines advance on a timer and the
/// duration is chosen before starting. No recorded voice — that is deferred.
struct MeditationPlayerScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    let meditation: MeditationDefinition

    @State private var model: PracticePlayerModel?

    var body: some View {
        VStack(spacing: Space.l) {
            Spacer()

            SunnieAvatarView(
                state: SunnieVisualState(
                    expression: .calmBreathing,
                    pose: .meditating,
                    presence: .prominent,
                    animationIntensity: 0.3
                )
            )

            if let guidance = currentGuidance {
                Text(LocalizedStringKey(guidance))
                    .font(SunnieFont.body)
                    .foregroundStyle(theme.color.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            Spacer()

            if let model, model.isRunning {
                ProgressView(value: model.progress)
                    .tint(theme.color.accentCalm)
                Text(remainingLabel(model.remaining))
                    .font(SunnieFont.numeric)
                    .foregroundStyle(theme.color.textSecondary)

                SunnieSecondaryButton(
                    title: String(
                        localized: "practice.stop",
                        defaultValue: "That's enough for now",
                        comment: "Ends a practice early"
                    ),
                    action: { Task { await model.stop(completed: false) } }
                )
            } else {
                durationPicker
                SunniePrimaryButton(
                    title: String(localized: "practice.begin", defaultValue: "Begin", comment: "Starts a practice"),
                    systemImage: "play",
                    action: { Task { await model?.start() } }
                )
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(String(localized: .init(meditation.displayNameKey)))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                model = PracticePlayerModel(meditation: meditation, dependencies: dependencies)
            }
        }
        .onDisappear {
            Task { await model?.abandon() }
        }
    }

    @ViewBuilder
    private var durationPicker: some View {
        if let model {
            Picker(
                String(
                    localized: "practice.duration",
                    defaultValue: "How long",
                    comment: "Duration picker"
                ),
                selection: Binding(
                    get: { model.selectedDuration },
                    set: { model.selectedDuration = $0 }
                )
            ) {
                ForEach(meditation.availableDurations, id: \.self) { duration in
                    Text("\(Int(duration / 60)) min").tag(duration)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    /// Guidance lines are spread evenly across the chosen duration, so a longer
    /// session simply holds each line longer rather than running out early.
    private var currentGuidance: String? {
        guard !meditation.guidanceKeys.isEmpty, let model else { return nil }
        guard model.isRunning else { return meditation.guidanceKeys.first }

        let step = model.selectedDuration / Double(meditation.guidanceKeys.count)
        guard step > 0 else { return meditation.guidanceKeys.first }

        let index = min(
            meditation.guidanceKeys.count - 1,
            Int(model.elapsed / step)
        )
        return meditation.guidanceKeys[index]
    }

    private func remainingLabel(_ remaining: TimeInterval) -> String {
        let seconds = Int(remaining.rounded())
        return String(
            localized: "practice.remaining \(seconds / 60) \(seconds % 60)",
            defaultValue: "\(seconds / 60):\(String(format: "%02d", seconds % 60)) left",
            comment: "Time remaining in a practice"
        )
    }
}

/// The calm sound library.
///
/// **Placeholder presentation.** Sounds are listed and selectable; no audio
/// assets ship yet, so playback is a no-op until Phase 10. Nothing auto-plays —
/// opening this screen stays silent until something is tapped.
struct CalmSoundsScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    @State private var playingID: ContentID?

    var body: some View {
        List {
            ForEach(CalmSoundCategory.allCases, id: \.self) { category in
                let sounds = dependencies.affirmationService.calmSounds(in: category)
                if !sounds.isEmpty {
                    Section {
                        ForEach(sounds) { sound in
                            Button {
                                Task { await toggle(sound) }
                            } label: {
                                HStack {
                                    Text(LocalizedStringKey(sound.displayNameKey))
                                        .foregroundStyle(theme.color.textPrimary)
                                    Spacer()
                                    Image(systemName: playingID == sound.id
                                        ? "speaker.wave.2.fill" : "play.circle")
                                        .foregroundStyle(theme.color.accentCalm)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(playingID == sound.id ? [.isButton, .isSelected] : .isButton)
                        }
                    } header: {
                        Text(LocalizedStringKey("calm.category.\(category.rawValue)"))
                    }
                }
            }

            Section {
                Text("calm.comingSoon", bundle: .main)
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("wellness.calm.title", bundle: .main))
        .onDisappear {
            Task { await dependencies.audioService.stopAmbience() }
        }
    }

    private func toggle(_ sound: CalmSoundDefinition) async {
        if playingID == sound.id {
            playingID = nil
            await dependencies.audioService.stopAmbience()
        } else {
            playingID = sound.id
            await dependencies.audioService.startAmbience(sound.audioCueID)
        }
    }
}

/// Wellness history.
///
/// **Placeholder presentation** — counts and simple bars. The language rule
/// matters more than the chart: everything here describes what was recorded, with
/// no causal or diagnostic claim attached (WELLNESS_JOURNAL_AND_CALM.md §10).
struct WellnessHistoryScreen: View {
    @Environment(\.sunnieTheme) private var theme

    let summary: WellnessSummary

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                SunnieCard {
                    SectionHeader(
                        title: String(
                            localized: "wellness.history.summary",
                            defaultValue: "The last month",
                            comment: "History period"
                        ),
                        subtitle: nil
                    )
                    LabeledContent {
                        Text("\(summary.checkInCount)").font(SunnieFont.numeric)
                    } label: {
                        Text("wellness.history.checkIns", bundle: .main)
                    }
                    LabeledContent {
                        Text("\(summary.practiceCount)").font(SunnieFont.numeric)
                    } label: {
                        Text("wellness.history.practices", bundle: .main)
                    }
                    LabeledContent {
                        Text("\(summary.practiceMinutes)").font(SunnieFont.numeric)
                    } label: {
                        Text("wellness.history.minutes", bundle: .main)
                    }
                }

                ForEach(summary.distributions, id: \.dimension) { distribution in
                    distributionCard(distribution)
                }
            }
            .padding(Space.m)
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("wellness.history.title", bundle: .main))
    }

    private func distributionCard(_ distribution: WellnessDistribution) -> some View {
        SunnieCard {
            SectionHeader(
                title: String(localized: .init(distribution.dimension.localizationKey)),
                subtitle: nil
            )

            if distribution.totalEntries == 0 {
                Text("wellness.history.nothingRecorded", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
            } else {
                ForEach(WellnessScaleValue.allCases, id: \.self) { value in
                    let count = distribution.counts[value] ?? 0
                    HStack(spacing: Space.s) {
                        Text(LocalizedStringKey(distribution.dimension.scaleLabelKey(for: value)))
                            .font(SunnieFont.caption)
                            .foregroundStyle(theme.color.textSecondary)
                            .frame(width: 96, alignment: .leading)

                        GeometryReader { proxy in
                            let fraction = distribution.totalEntries == 0
                                ? 0
                                : Double(count) / Double(distribution.totalEntries)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(theme.color.accentCalm.opacity(0.5))
                                .frame(width: max(0, proxy.size.width * fraction))
                        }
                        .frame(height: 14)

                        Text("\(count)")
                            .font(SunnieFont.numeric)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                    // Colour is never the only cue: the label and the count carry
                    // the same information as the bar.
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
