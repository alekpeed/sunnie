import SwiftUI
import SunnieShared

/// The six boards.
///
/// Each one takes a puzzle, a board rebuilt from the move log, and a closure
/// that reports a new move. None of them holds game state of its own beyond what
/// is being typed right now — the move log is the state, and these draw it.
///
/// **Accessibility is built in here rather than retrofitted**
/// (GAMES_AND_FUTURE_MULTIPLAYER.md §10):
///
/// - Nothing is drag-driven. Every board is taps and text fields.
/// - No state is carried by colour alone; each has a symbol and a label.
/// - Board state reads as text, so VoiceOver describes the grid rather than
///   announcing an image.
/// - Nothing requires sound, and nothing requires beating a clock.

// MARK: - Answer chain

struct AnswerChainBoardView: View {
    @Environment(\.sunnieTheme) private var theme

    let puzzle: AnswerChainPuzzle
    let board: AnswerChainBoard
    let wasNearMiss: Bool
    let onMove: (GameMove.Action, Int) -> Void

    @State private var typed = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ForEach(settledStops, id: \.self) { index in
                settledStop(index)
            }

            if board.stops.indices.contains(board.currentStop) {
                currentStop(board.currentStop)
            }
        }
    }

    private var settledStops: [Int] {
        board.stops.indices.filter { board.stops[$0].isSolved || board.stops[$0].wasSkipped }
    }

    private func settledStop(_ index: Int) -> some View {
        SunnieCard {
            HStack(spacing: Space.xs) {
                Image(systemName: board.stops[index].isSolved
                    ? "checkmark.circle.fill" : "arrow.turn.down.right")
                    .foregroundStyle(board.stops[index].isSolved
                        ? theme.color.success : theme.color.textSecondary)
                    .accessibilityHidden(true)
                Text(puzzle.stops[index].answer)
                    .font(SunnieFont.cardTitle)
                    .foregroundStyle(theme.color.textPrimary)
            }
            Text(puzzle.stops[index].linkExplanation.text)
                .font(SunnieFont.secondary)
                .foregroundStyle(theme.color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func currentStop(_ index: Int) -> some View {
        SunnieCard {
            Text(puzzle.stops[index].prompt.text)
                .font(SunnieFont.body)
                .foregroundStyle(theme.color.textPrimary)

            // The language is stated rather than implied by the clue's wording,
            // so nobody types the right word in the wrong language and is told
            // they are wrong.
            Text(LocalizedStringKey(puzzle.stops[index].language.localizationKey))
                .font(SunnieFont.caption)
                .foregroundStyle(theme.color.textSecondary)

            TextField(
                String(
                    localized: "games.answer.placeholder",
                    defaultValue: "Your answer",
                    comment: "Answer field placeholder"
                ),
                text: $typed
            )
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit { submit(index) }

            if wasNearMiss, !typed.isEmpty {
                Label {
                    Text("games.answer.close", bundle: .main)
                } icon: {
                    Image(systemName: "sparkle").accessibilityHidden(true)
                }
                .font(SunnieFont.caption)
                .foregroundStyle(theme.color.attention)
            }

            HStack(spacing: Space.s) {
                SunniePrimaryButton(
                    title: String(
                        localized: "games.answer.submit",
                        defaultValue: "Try it",
                        comment: "Submits an answer"
                    )
                ) { submit(index) }

                SunnieSecondaryButton(
                    title: String(
                        localized: "games.answer.skip",
                        defaultValue: "Move on",
                        comment: "Skips a stop"
                    )
                ) {
                    typed = ""
                    onMove(.skip, index)
                }
            }
        }
    }

    private func submit(_ index: Int) {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onMove(.answer(trimmed), index)
        // Cleared only on a correct answer, so a near miss stays on screen to be
        // edited rather than retyped from nothing.
        if AnswerNormalizer.matches(trimmed, accepted: puzzle.stops[index].acceptedAnswers) {
            typed = ""
        }
    }
}

// MARK: - Reveal and identify

struct IdentifyBoardView: View {
    @Environment(\.sunnieTheme) private var theme

    let puzzle: IdentifyPuzzle
    let board: IdentifyBoard
    let onMove: (GameMove.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SunnieCard {
                Text(puzzle.prompt.text)
                    .font(SunnieFont.cardTitle)
                    .foregroundStyle(theme.color.textPrimary)
                Text("games.identify.note", bundle: .main)
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }

            SunnieCard {
                SectionHeader(title: String(
                    localized: "games.identify.clues",
                    defaultValue: "The postcard",
                    comment: "Clue list heading"
                ))

                ForEach(puzzle.clues.indices, id: \.self) { index in
                    if board.revealedClues.contains(index) {
                        revealedClue(index)
                    } else if !board.isComplete {
                        unrevealedClue(index)
                    }
                }
            }

            if !board.isComplete {
                SunnieCard {
                    SectionHeader(title: String(
                        localized: "games.identify.options",
                        defaultValue: "Where is it?",
                        comment: "Answer options heading"
                    ))

                    ForEach(puzzle.options.indices, id: \.self) { index in
                        Button {
                            onMove(.choose(index))
                        } label: {
                            HStack {
                                Text(puzzle.options[index].text)
                                    .foregroundStyle(theme.color.textPrimary)
                                Spacer()
                            }
                            .padding(.vertical, Space.xxs)
                        }
                    }

                    SunnieSecondaryButton(
                        title: String(
                            localized: "games.identify.reveal",
                            defaultValue: "Show me the answer",
                            comment: "Ends the round without guessing"
                        )
                    ) { onMove(.skip) }
                }
            }
        }
    }

    private func revealedClue(_ index: Int) -> some View {
        HStack(alignment: .top, spacing: Space.xs) {
            Image(systemName: symbol(for: puzzle.clues[index].kind))
                .foregroundStyle(theme.color.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(LocalizedStringKey(puzzle.clues[index].kind.localizationKey))
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
                Text(puzzle.clues[index].detail.text)
                    .font(SunnieFont.body)
                    .foregroundStyle(theme.color.textPrimary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func unrevealedClue(_ index: Int) -> some View {
        Button {
            onMove(.reveal(clue: index))
        } label: {
            HStack {
                Label {
                    Text(LocalizedStringKey(puzzle.clues[index].kind.localizationKey))
                } icon: {
                    Image(systemName: "eye").accessibilityHidden(true)
                }
                Spacer()
                Text(String(
                    format: String(
                        localized: "games.identify.cost",
                        defaultValue: "−%d",
                        comment: "Score cost of revealing a clue"
                    ),
                    puzzle.clues[index].cost
                ))
                .font(SunnieFont.caption)
                .foregroundStyle(theme.color.textSecondary)
            }
        }
    }

    private func symbol(for kind: RevealClue.Kind) -> String {
        switch kind {
        case .textFragment: "text.quote"
        case .stampMark: "seal"
        case .weather: "cloud.sun"
        case .landmark: "building.columns"
        case .localPhrase: "quote.bubble"
        }
    }
}

// MARK: - Grid assignment

/// Deduction board.
///
/// One row per position, one menu per category. Menus rather than drag: a
/// drag-and-drop grid would need a whole parallel path for VoiceOver and Switch
/// Control, and a menu already works with both.
struct GridBoardView: View {
    @Environment(\.sunnieTheme) private var theme

    let puzzle: GridPuzzle
    let board: GridBoard
    let onMove: (GameMove.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SunnieCard {
                SectionHeader(title: String(
                    localized: "games.grid.clues",
                    defaultValue: "What you know",
                    comment: "Constraint list heading"
                ))
                ForEach(puzzle.constraints.indices, id: \.self) { index in
                    Text(describe(puzzle.constraints[index]))
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textPrimary)
                }
            }

            ForEach(0..<puzzle.positionCount, id: \.self) { position in
                positionCard(position)
            }

            if board.isFullyAssigned, !board.isSubmitted {
                SunniePrimaryButton(
                    title: String(
                        localized: "games.grid.check",
                        defaultValue: "That's my arrangement",
                        comment: "Submits the completed grid"
                    )
                ) { onMove(.advance) }
            }
        }
    }

    private func positionCard(_ position: Int) -> some View {
        SunnieCard {
            Text("\(puzzle.positionLabel.text) \(position + 1)")
                .font(SunnieFont.cardTitle)
                .foregroundStyle(theme.color.textPrimary)

            ForEach(puzzle.categories.indices, id: \.self) { category in
                HStack {
                    Text(puzzle.categories[category].name.text)
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)
                    Spacer()
                    Menu {
                        ForEach(puzzle.categories[category].values.indices, id: \.self) { value in
                            Button(puzzle.categories[category].values[value].text) {
                                onMove(.assign(
                                    item: GridEngine.encode(
                                        category: category,
                                        value: value,
                                        positions: puzzle.positionCount
                                    ),
                                    slot: position
                                ))
                            }
                        }
                        if let current = board.value(category: category, position: position) {
                            Divider()
                            Button(String(
                                localized: "games.grid.clear",
                                defaultValue: "Leave it empty",
                                comment: "Clears a grid assignment"
                            ), role: .destructive) {
                                onMove(.unassign(item: GridEngine.encode(
                                    category: category,
                                    value: current,
                                    positions: puzzle.positionCount
                                )))
                            }
                        }
                    } label: {
                        Text(label(category: category, position: position))
                            .foregroundStyle(theme.color.textPrimary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(
                    "\(puzzle.positionLabel.text) \(position + 1), \(puzzle.categories[category].name.text): \(label(category: category, position: position))"
                ))
            }
        }
    }

    private func label(category: Int, position: Int) -> String {
        guard
            let value = board.value(category: category, position: position),
            puzzle.categories[category].values.indices.contains(value)
        else {
            return String(
                localized: "games.grid.empty",
                defaultValue: "Not decided",
                comment: "An empty grid cell"
            )
        }
        return puzzle.categories[category].values[value].text
    }

    /// Renders a clue as a sentence.
    ///
    /// Built from the puzzle's own value names, so a pack in another language
    /// reads correctly without a second set of authored clue strings.
    private func describe(_ constraint: GridConstraint) -> String {
        func name(_ category: Int, _ value: Int) -> String {
            guard
                puzzle.categories.indices.contains(category),
                puzzle.categories[category].values.indices.contains(value)
            else { return "?" }
            return puzzle.categories[category].values[value].text
        }

        switch constraint {
        case .same(let ca, let va, let cb, let vb):
            return String(
                format: String(
                    localized: "games.grid.clue.same",
                    defaultValue: "%1$@ and %2$@ share a place.",
                    comment: "Grid clue: two values in the same position"
                ),
                name(ca, va), name(cb, vb)
            )
        case .different(let ca, let va, let cb, let vb):
            return String(
                format: String(
                    localized: "games.grid.clue.different",
                    defaultValue: "%1$@ and %2$@ are not together.",
                    comment: "Grid clue: two values in different positions"
                ),
                name(ca, va), name(cb, vb)
            )
        case .atPosition(let category, let value, let position):
            return String(
                format: String(
                    localized: "games.grid.clue.at",
                    defaultValue: "%1$@ is at %2$@ %3$d.",
                    comment: "Grid clue: a value at a fixed position"
                ),
                name(category, value), puzzle.positionLabel.text, position + 1
            )
        case .adjacent(let ca, let va, let cb, let vb):
            return String(
                format: String(
                    localized: "games.grid.clue.adjacent",
                    defaultValue: "%1$@ is right next to %2$@.",
                    comment: "Grid clue: adjacency"
                ),
                name(ca, va), name(cb, vb)
            )
        case .before(let ca, let va, let cb, let vb):
            return String(
                format: String(
                    localized: "games.grid.clue.before",
                    defaultValue: "%1$@ is somewhere before %2$@.",
                    comment: "Grid clue: ordering"
                ),
                name(ca, va), name(cb, vb)
            )
        }
    }
}

// MARK: - Study then quiz

struct StudyBoardView: View {
    @Environment(\.sunnieTheme) private var theme

    let puzzle: StudyPuzzle
    let board: StudyBoard
    let secondsRemaining: Int
    let isUntimed: Bool
    let onUntimed: () -> Void
    let onMove: (GameMove.Action, Int) -> Void

    var body: some View {
        if board.phase == .studying, isUntimed || secondsRemaining > 0 {
            studyPage
        } else if board.phase == .studying {
            // The countdown ran out but the player never said they were ready.
            // The page closes itself and the questions begin — nothing is lost,
            // because the answers are still all in front of them.
            SunnieCard {
                Text("games.study.timeUp", bundle: .main)
                    .font(SunnieFont.body)
                    .foregroundStyle(theme.color.textPrimary)
                SunniePrimaryButton(
                    title: String(
                        localized: "games.study.begin",
                        defaultValue: "Ask me the questions",
                        comment: "Moves from studying to answering"
                    )
                ) { onMove(.advance, 0) }
            }
        } else {
            questions
        }
    }

    private var studyPage: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SunnieCard {
                HStack {
                    Text("games.study.title", bundle: .main)
                        .font(SunnieFont.cardTitle)
                        .foregroundStyle(theme.color.textPrimary)
                    Spacer()
                    if !isUntimed {
                        Text("\(secondsRemaining)")
                            .font(SunnieFont.numeric)
                            .foregroundStyle(theme.color.textSecondary)
                            .accessibilityLabel(Text(String(
                                format: String(
                                    localized: "games.study.remaining",
                                    defaultValue: "%d seconds left",
                                    comment: "Study countdown"
                                ),
                                secondsRemaining
                            )))
                    }
                }

                if !isUntimed {
                    SunnieSecondaryButton(
                        title: String(
                            localized: "games.study.untimed",
                            defaultValue: "Take away the timer",
                            comment: "Removes the study countdown"
                        ),
                        action: onUntimed
                    )
                    Text("games.study.untimed.note", bundle: .main)
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }

            SunnieCard {
                ForEach(0..<puzzle.rows, id: \.self) { row in
                    HStack(alignment: .top, spacing: Space.s) {
                        ForEach(0..<puzzle.columns, id: \.self) { column in
                            cell(row: row, column: column)
                        }
                    }
                }
            }

            SunniePrimaryButton(
                title: String(
                    localized: "games.study.ready",
                    defaultValue: "I've looked",
                    comment: "Finishes studying"
                )
            ) { onMove(.advance, 0) }
        }
    }

    @ViewBuilder
    private func cell(row: Int, column: Int) -> some View {
        let item = puzzle.items.first { $0.row == row && $0.column == column }

        VStack(alignment: .leading, spacing: Space.xxs) {
            if let item {
                Text(item.label.text)
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textPrimary)
                Text(item.detail.text)
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            } else {
                Text(" ")
                    .font(SunnieFont.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(item.map { item in
            String(
                format: String(
                    localized: "games.study.cell",
                    defaultValue: "Row %1$d, column %2$d: %3$@, %4$@",
                    comment: "VoiceOver description of a scrapbook cell"
                ),
                row + 1, column + 1, item.label.text, item.detail.text
            )
        } ?? String(
            format: String(
                localized: "games.study.cell.empty",
                defaultValue: "Row %1$d, column %2$d: empty",
                comment: "VoiceOver description of an empty scrapbook cell"
            ),
            row + 1, column + 1
        )))
    }

    private var questions: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ForEach(puzzle.questions.indices, id: \.self) { index in
                SunnieCard {
                    Text(puzzle.questions[index].prompt.text)
                        .font(SunnieFont.body)
                        .foregroundStyle(theme.color.textPrimary)

                    let answered = board.answers.indices.contains(index)
                        ? board.answers[index] : nil

                    if let answered, answered >= 0,
                       puzzle.questions[index].options.indices.contains(answered) {
                        Label {
                            Text(puzzle.questions[index].options[answered].text)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .accessibilityHidden(true)
                        }
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)
                    } else if answered == -1 {
                        Text("games.study.skipped", bundle: .main)
                            .font(SunnieFont.caption)
                            .foregroundStyle(theme.color.textSecondary)
                    } else {
                        ForEach(puzzle.questions[index].options.indices, id: \.self) { option in
                            Button {
                                onMove(.choose(option), index)
                            } label: {
                                HStack {
                                    Text(puzzle.questions[index].options[option].text)
                                        .foregroundStyle(theme.color.textPrimary)
                                    Spacer()
                                }
                                .padding(.vertical, Space.xxs)
                            }
                        }
                        SunnieSecondaryButton(
                            title: String(
                                localized: "games.answer.skip",
                                defaultValue: "Move on",
                                comment: "Skips a stop"
                            )
                        ) { onMove(.skip, index) }
                    }
                }
            }
        }
    }
}

// MARK: - Constrained selection

struct SelectionBoardView: View {
    @Environment(\.sunnieTheme) private var theme

    let puzzle: SelectionPuzzle
    let board: SelectionBoard
    let onMove: (GameMove.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SunnieCard {
                Text(puzzle.brief.text)
                    .font(SunnieFont.body)
                    .foregroundStyle(theme.color.textPrimary)
            }

            SunnieCard {
                SectionHeader(title: String(
                    localized: "games.selection.rules",
                    defaultValue: "What has to be true",
                    comment: "Rule list heading"
                ))

                ForEach(puzzle.rules.indices, id: \.self) { index in
                    let holds = SelectionEngine.satisfies(
                        puzzle.rules[index], selection: board.selected, puzzle: puzzle
                    )
                    Label {
                        Text(puzzle.rules[index].explanation.text)
                            .font(SunnieFont.secondary)
                            .foregroundStyle(theme.color.textPrimary)
                    } icon: {
                        // Symbol and colour together, never colour alone.
                        Image(systemName: holds ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(holds ? theme.color.success : theme.color.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(
                        "\(puzzle.rules[index].explanation.text). \(holds ? metRuleLabel : unmetRuleLabel)"
                    ))
                }
            }

            SunnieCard {
                HStack {
                    SectionHeader(title: String(
                        localized: "games.selection.bag",
                        defaultValue: "The bag",
                        comment: "Candidate list heading"
                    ))
                    Spacer()
                    Text("\(SelectionEngine.totalWeight(selection: board.selected, puzzle: puzzle))")
                        .font(SunnieFont.numeric)
                        .foregroundStyle(theme.color.textSecondary)
                }

                ForEach(puzzle.candidates.indices, id: \.self) { index in
                    let isSelected = board.selected.contains(index)
                    Button {
                        onMove(.toggle(item: index, isSelected: !isSelected))
                    } label: {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                .foregroundStyle(isSelected
                                    ? theme.color.accentPlant : theme.color.textSecondary)
                                .accessibilityHidden(true)
                            Text(puzzle.candidates[index].name.text)
                                .foregroundStyle(theme.color.textPrimary)
                            Spacer()
                            Text("\(puzzle.candidates[index].weight)")
                                .font(SunnieFont.numeric)
                                .foregroundStyle(theme.color.textSecondary)
                        }
                    }
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }

            if !board.isSubmitted {
                SunniePrimaryButton(
                    title: String(
                        localized: "games.selection.pack",
                        defaultValue: "Zip it up",
                        comment: "Submits the packing selection"
                    )
                ) { onMove(.advance) }
            }
        }
    }

    private var metRuleLabel: String {
        String(
            localized: "games.selection.rule.met",
            defaultValue: "Met",
            comment: "A packing rule that currently holds"
        )
    }

    private var unmetRuleLabel: String {
        String(
            localized: "games.selection.rule.unmet",
            defaultValue: "Not yet",
            comment: "A packing rule that does not hold yet"
        )
    }
}

// MARK: - Branching choice

struct BranchingBoardView: View {
    @Environment(\.sunnieTheme) private var theme

    let puzzle: BranchingPuzzle
    let board: BranchingBoard
    let onMove: (GameMove.Action, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ForEach(board.visits.indices, id: \.self) { index in
                visitCard(index)
            }

            if let nodeID = board.currentNodeID, let node = puzzle.node(id: nodeID) {
                SunnieCard {
                    Text(node.prompt.text)
                        .font(SunnieFont.body)
                        .foregroundStyle(theme.color.textPrimary)

                    ForEach(node.options.indices, id: \.self) { option in
                        Button {
                            onMove(.choose(option), board.visits.count)
                        } label: {
                            HStack {
                                Text(node.options[option].text.text)
                                    .foregroundStyle(theme.color.textPrimary)
                                Spacer()
                            }
                            .padding(.vertical, Space.xxs)
                        }
                    }

                    SunnieSecondaryButton(
                        title: String(
                            localized: "games.trail.skip",
                            defaultValue: "Keep travelling",
                            comment: "Skips a trail question"
                        )
                    ) { onMove(.skip, board.visits.count) }
                }
            }
        }
    }

    @ViewBuilder
    private func visitCard(_ index: Int) -> some View {
        let visit = board.visits[index]
        if let node = puzzle.node(id: visit.nodeID) {
            let chosen = visit.chosenOption.flatMap { option in
                node.options.indices.contains(option) ? node.options[option] : nil
            }
            SunnieCard {
                Text(node.prompt.text)
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)

                if let chosen {
                    HStack(spacing: Space.xs) {
                        Image(systemName: chosen.isEfficient
                            ? "checkmark.circle.fill" : "arrow.triangle.turn.up.right.diamond")
                            .foregroundStyle(chosen.isEfficient
                                ? theme.color.success : theme.color.textSecondary)
                            .accessibilityHidden(true)
                        Text(chosen.text.text)
                            .font(SunnieFont.body)
                            .foregroundStyle(theme.color.textPrimary)
                    }
                    Text(chosen.explanation.text)
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)
                } else {
                    Text("games.trail.skipped", bundle: .main)
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
