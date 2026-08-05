import SwiftUI
import SunnieShared

/// The result screen (S-20).
///
/// **Placeholder presentation.** The content is the spec's: what happened, the
/// explanation, reward progress, Sunnie's reaction, and what to do next.
///
/// The explanation is the part that matters. A knowledge or logic game that says
/// only "4 of 5" has taught nothing, so every step is listed with the reason
/// behind its answer — including the ones the player got right, because knowing
/// *why* a guess worked is the same lesson (§6).
///
/// Sunnie's reaction never depends on the score. There is no version of this
/// screen where he is disappointed.
struct GameResultView: View {
    @Environment(\.sunnieTheme) private var theme

    let finish: PlayGame.Finish
    let puzzle: PuzzleDefinition?
    let game: GameDefinition?
    let onDone: () -> Void

    private var result: GameResult { finish.result }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.m) {
                summaryCard
                if experienceEarned > 0 { rewardCard }
                explanationCard
                actionsCard
            }
            .padding(Space.m)
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("games.result.title", bundle: .main))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        SunnieCard {
            SunnieAvatarView(state: reaction)

            Text(LocalizedStringKey(result.completion.localizationKey))
                .font(SunnieFont.cardTitle)
                .foregroundStyle(theme.color.textPrimary)

            Text(sunnieLine)
                .font(SunnieFont.body)
                .foregroundStyle(theme.color.textSecondary)

            HStack(spacing: Space.xs) {
                StatusChip(
                    text: String(
                        format: String(
                            localized: "games.result.steps",
                            defaultValue: "%1$d of %2$d",
                            comment: "Steps answered correctly out of the total"
                        ),
                        result.stepsCorrect, result.stepsTotal
                    ),
                    style: .neutral
                )
                StatusChip(
                    text: String(
                        format: String(
                            localized: "games.result.score",
                            defaultValue: "%d points",
                            comment: "Score for a finished puzzle"
                        ),
                        result.score
                    ),
                    style: .neutral
                )
                if result.hintsUsed > 0 {
                    StatusChip(
                        text: String(
                            format: String(
                                localized: "games.hints.count",
                                defaultValue: "%d hints",
                                comment: "Number of hints taken"
                            ),
                            result.hintsUsed
                        ),
                        style: .neutral
                    )
                }
            }

            // Time is reported only where the puzzle says it means something
            // (§6). A deduction puzzle is not improved by being timed.
            if puzzle?.reportsTime == true, result.elapsedSeconds > 0 {
                Text(String(
                    format: String(
                        localized: "games.result.time",
                        defaultValue: "You took about %d minutes.",
                        comment: "Elapsed time on a timed puzzle"
                    ),
                    max(1, result.elapsedSeconds / 60)
                ))
                .font(SunnieFont.caption)
                .foregroundStyle(theme.color.textSecondary)
            }
        }
    }

    /// Sunnie's response, chosen by what happened rather than by how well.
    private var sunnieLine: String {
        switch result.completion {
        case .solvedUnaided:
            String(
                localized: "games.result.line.unaided",
                defaultValue: "You worked all the way through that one on your own.",
                comment: "Sunnie's response to a puzzle solved without hints"
            )
        case .solvedWithHints:
            String(
                localized: "games.result.line.hints",
                defaultValue: "Solved. Taking a nudge is part of playing, not a shortcut.",
                comment: "Sunnie's response to a puzzle solved with hints"
            )
        case .finishedWithHelp:
            String(
                localized: "games.result.line.helped",
                defaultValue: "You got to the end, and the reasons are all below if you'd like to look.",
                comment: "Sunnie's response to a puzzle finished with some steps missed"
            )
        case .setAside:
            String(
                localized: "games.result.line.setAside",
                defaultValue: "Left for later. It'll be exactly where you put it.",
                comment: "Sunnie's response to a puzzle set aside"
            )
        }
    }

    private var reaction: SunnieVisualState {
        SunnieVisualState(
            expression: result.completion == .setAside ? .happyClosedEyed : .celebratingQuietly,
            pose: .playingGame,
            presence: .medium
        )
    }

    // MARK: - Reward

    /// Experience actually awarded, which is zero on a replay.
    ///
    /// Shown only when it was earned. A "+15" that did not happen would be the
    /// app lying about progress, and a player who replays a puzzle they enjoyed
    /// should not be told they gained something they did not.
    private var experienceEarned: Int {
        (finish.outcome?.event?.experienceAwarded ?? 0)
            + (finish.dailyOutcome?.event?.experienceAwarded ?? 0)
    }

    private var rewardCard: some View {
        SunnieCard {
            SectionHeader(title: String(
                localized: "games.result.reward",
                defaultValue: "What that added",
                comment: "Reward section heading"
            ))

            Text(String(
                format: String(
                    localized: "games.result.experience",
                    defaultValue: "%d experience",
                    comment: "Experience earned"
                ),
                experienceEarned
            ))
            .font(SunnieFont.body)
            .foregroundStyle(theme.color.textPrimary)

            let rewards = (finish.outcome?.rewards ?? []) + (finish.dailyOutcome?.rewards ?? [])
            ForEach(rewards) { grant in
                Text(LocalizedStringKey("reward.\(grant.rewardID.rawValue)"))
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
    }

    // MARK: - Explanation

    private var explanationCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "games.result.explanation",
                    defaultValue: "Why the answers are what they are",
                    comment: "Explanation section heading"
                )
            )

            ForEach(result.steps, id: \.stepIndex) { step in
                VStack(alignment: .leading, spacing: Space.xxs) {
                    HStack(alignment: .top, spacing: Space.xs) {
                        Image(systemName: step.wasCorrect
                            ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(step.wasCorrect
                                ? theme.color.success : theme.color.textSecondary)
                            .accessibilityHidden(true)
                        Text(step.prompt.text)
                            .font(SunnieFont.secondary)
                            .foregroundStyle(theme.color.textPrimary)
                    }

                    if !step.expectedAnswer.isEmpty {
                        Text(String(
                            format: String(
                                localized: "games.result.answer",
                                defaultValue: "Answer: %@",
                                comment: "The correct answer for a step"
                            ),
                            step.expectedAnswer
                        ))
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                    }

                    if let explanation = step.explanation {
                        Text(explanation.text)
                            .font(SunnieFont.caption)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                }
                .padding(.vertical, Space.xxs)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Actions

    private var actionsCard: some View {
        SunnieCard {
            SunniePrimaryButton(
                title: String(
                    localized: "games.result.done",
                    defaultValue: "Back to the games",
                    comment: "Leaves the result screen"
                ),
                action: onDone
            )

            if let game {
                Text(LocalizedStringKey(game.summaryKey))
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
    }
}
