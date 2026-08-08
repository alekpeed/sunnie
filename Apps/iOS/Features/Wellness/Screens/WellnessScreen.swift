import SwiftUI
import SunnieShared

/// The Wellness tab.
///
/// **Placeholder presentation** in plain native controls. The behaviour is real:
/// check-in, affirmations, breathing, meditation, calm sounds, and history all
/// work. Nothing here is required, prompted, or counted — every card is an offer.
struct WellnessScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    @State private var model: WellnessModel?
    @State private var hydrationToday = 0
    @State private var healthDescriptors: [HealthPhrasing.Descriptor] = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                if let acknowledgement = model?.acknowledgement {
                    acknowledgementCard(acknowledgement)
                }

                checkInCard
                affirmationCard
                practicesCard
                calmSoundsCard
                hydrationCard
                if !healthDescriptors.isEmpty { healthCard }
                historyCard
            }
            .padding(Space.m)
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("tab.wellness", bundle: .main))
        .audioContext(.wellness)
        .refreshable { await model?.load() }
        .task {
            if model == nil {
                model = WellnessModel(dependencies: dependencies, appState: appState)
            }
            await model?.onAppear()
            await refreshHealth()
        }
        .onDisappear {
            Task { await model?.onDisappear() }
        }
        .sheet(isPresented: checkInBinding) {
            if let model {
                CheckInSheet { draft in
                    Task {
                        await model.recordCheckIn(
                            draftID: draft.id,
                            mood: draft.mood,
                            energy: draft.energy,
                            stress: draft.stress,
                            sleepQuality: draft.sleepQuality,
                            note: draft.note,
                            hasAttachments: draft.hasAttachments
                        )
                    }
                }
            }
        }
    }

    private var checkInBinding: Binding<Bool> {
        Binding(
            get: { model?.isCheckInPresented ?? false },
            set: { model?.isCheckInPresented = $0 }
        )
    }

    // MARK: - Cards

    /// Sunnie's reply, plus at most one optional next step. Always dismissible
    /// straight away (WELLNESS_JOURNAL_AND_CALM.md §3).
    private func refreshHealth() async {
        hydrationToday = await dependencies.manageHealth.todayHydration()
        healthDescriptors = await dependencies.manageHealth.todayDescriptors()
    }

    /// Hydration (HEALTH_WATCH_WIDGETS_AND_INTENTS.md §3).
    ///
    /// Three round amounts and a running total. No goal, no ring, and no
    /// remaining-to-target: the app records what someone drank, and has no view
    /// about whether it was enough.
    private var hydrationCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(localized: "hydration.title", defaultValue: "Water", comment: "Hydration heading"),
                subtitle: String(
                    format: String(
                        localized: "hydration.today",
                        defaultValue: "%d ml today",
                        comment: "Water logged today"
                    ),
                    hydrationToday
                )
            )

            HStack(spacing: Space.xs) {
                ForEach(HydrationLog.quickAmounts, id: \.self) { amount in
                    SunnieSecondaryButton(
                        title: String(
                            format: String(
                                localized: "hydration.log",
                                defaultValue: "%d ml",
                                comment: "Logs a quantity of water"
                            ),
                            amount
                        )
                    ) {
                        Task {
                            _ = try? await dependencies.manageHealth.logWater(millilitres: amount)
                            await refreshHealth()
                        }
                    }
                }
            }

            Text("hydration.note", bundle: .main)
                .font(SunnieFont.caption)
                .foregroundStyle(theme.color.textSecondary)
        }
    }

    /// What Health recorded, said as plainly as §4 allows.
    ///
    /// Each line is a number and a noun, built by `HealthPhrasing` — which has no
    /// way to express a target, a comparison, or a conclusion. The caveat, when
    /// there is one, says the window is still open rather than presenting a
    /// partial day as a whole one.
    private var healthCard: some View {
        SunnieCard {
            SectionHeader(title: String(
                localized: "settings.section.health",
                defaultValue: "Health",
                comment: "Health section heading"
            ))

            ForEach(healthDescriptors, id: \.type) { descriptor in
                HStack {
                    Text(LocalizedStringKey(descriptor.type.localizationKey))
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)
                    Spacer()
                    HStack(spacing: Space.xxs) {
                        Text(descriptor.formattedValue)
                            .font(SunnieFont.numeric)
                            .foregroundStyle(theme.color.textPrimary)
                        Text(LocalizedStringKey(descriptor.unitKey))
                            .font(SunnieFont.caption)
                            .foregroundStyle(theme.color.textSecondary)
                        if let caveatKey = descriptor.caveatKey {
                            Text(LocalizedStringKey(caveatKey))
                                .font(SunnieFont.caption)
                                .foregroundStyle(theme.color.textSecondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func acknowledgementCard(_ message: SunnieMessage) -> some View {
        SunnieCard {
            SunnieMessageView(message: message, presence: .medium)

            if let suggestion = model?.suggestion {
                suggestionButton(suggestion)
            }

            SunnieSecondaryButton(
                title: String(
                    localized: "common.dismiss",
                    defaultValue: "Thanks",
                    comment: "Dismisses Sunnie's acknowledgement"
                ),
                action: { model?.dismissAcknowledgement() }
            )
        }
    }

    @ViewBuilder
    private func suggestionButton(_ suggestion: RecordWellnessCheckIn.Suggestion) -> some View {
        switch suggestion {
        case .breathing(let patternID):
            NavigationLink {
                if let pattern = dependencies.affirmationService.breathingPattern(id: patternID) {
                    BreathingPlayerScreen(pattern: pattern)
                }
            } label: {
                Text("wellness.suggestion.breathing", bundle: .main)
            }
        case .calmSounds:
            NavigationLink {
                CalmSoundsScreen()
            } label: {
                Text("wellness.suggestion.calmSounds", bundle: .main)
            }
        case .journal:
            Button {
                router.handle(.journal)
            } label: {
                Text("wellness.suggestion.journal", bundle: .main)
            }
        }
    }

    private var checkInCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "wellness.checkIn.title",
                    defaultValue: "How are you right now?",
                    comment: "Check-in card title"
                ),
                subtitle: checkInSubtitle
            )

            SunniePrimaryButton(
                title: String(
                    localized: "wellness.checkIn.action",
                    defaultValue: "Check in",
                    comment: "Opens the check-in sheet"
                ),
                systemImage: "heart",
                action: { model?.isCheckInPresented = true }
            )
        }
    }

    /// Never phrased as a nudge. If they already checked in, that is stated as
    /// fact, not as a reason to stop or to do it again.
    private var checkInSubtitle: String? {
        guard case .loaded(let summary) = model?.state else { return nil }
        if summary.hasCheckedInToday {
            return String(
                localized: "wellness.checkIn.already",
                defaultValue: "You've checked in today. You can add another whenever you like.",
                comment: "Shown when a check-in already exists for today"
            )
        }
        return String(
            localized: "wellness.checkIn.optional",
            defaultValue: "Only if you feel like it.",
            comment: "Makes clear the check-in is optional"
        )
    }

    private var affirmationCard: some View {
        SunnieCard {
            if let affirmation = model?.affirmation {
                Text(affirmation.text)
                    .font(SunnieFont.body)
                    .foregroundStyle(theme.color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SunnieSecondaryButton(
                    title: String(
                        localized: "wellness.affirmation.another",
                        defaultValue: "Another",
                        comment: "Shows a different affirmation"
                    ),
                    systemImage: "arrow.clockwise",
                    action: { model?.refreshAffirmation() }
                )
            } else {
                Text("wellness.affirmation.none", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
    }

    private var practicesCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "wellness.practices.title",
                    defaultValue: "A quiet moment",
                    comment: "Section for breathing and meditation"
                ),
                subtitle: nil
            )

            ForEach(model?.breathingPatterns ?? []) { pattern in
                NavigationLink {
                    BreathingPlayerScreen(pattern: pattern)
                } label: {
                    practiceRow(
                        title: String(localized: .init(pattern.displayNameKey)),
                        detail: String(localized: .init(pattern.descriptionKey)),
                        systemImage: "wind"
                    )
                }
                .buttonStyle(.plain)
            }

            ForEach(model?.meditations ?? []) { meditation in
                NavigationLink {
                    MeditationPlayerScreen(meditation: meditation)
                } label: {
                    practiceRow(
                        title: String(localized: .init(meditation.displayNameKey)),
                        detail: durationLabel(meditation.defaultDuration),
                        systemImage: "moon"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var calmSoundsCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "wellness.calm.title",
                    defaultValue: "Calm sounds",
                    comment: "Section for ambient sound"
                ),
                subtitle: nil
            )
            NavigationLink {
                CalmSoundsScreen()
            } label: {
                practiceRow(
                    title: String(
                        localized: "wellness.calm.browse",
                        defaultValue: "Sound library",
                        comment: "Opens the calm sound library"
                    ),
                    detail: nil,
                    systemImage: "speaker.wave.2"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var historyCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "wellness.history.title",
                    defaultValue: "What you've recorded",
                    comment: "Section for wellness history"
                ),
                subtitle: nil
            )

            switch model?.state ?? .idle {
            case .idle, .loading:
                LoadingStateView(message: String(
                    localized: "wellness.loading",
                    defaultValue: "Gathering this up…",
                    comment: "Loading state"
                ))

            case .failed(let message):
                Text(message)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)

            case .loaded(let summary):
                if summary.checkInCount == 0 && summary.practiceCount == 0 {
                    Text("wellness.history.empty", bundle: .main)
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)
                } else {
                    // Descriptive only. Counts of what was recorded, with no
                    // causal or diagnostic claim (WELLNESS §10).
                    LabeledContent {
                        Text("\(summary.checkInCount)").font(SunnieFont.numeric)
                    } label: {
                        Text("wellness.history.checkIns", bundle: .main)
                    }
                    LabeledContent {
                        Text("\(summary.practiceMinutes)").font(SunnieFont.numeric)
                    } label: {
                        Text("wellness.history.minutes", bundle: .main)
                    }

                    NavigationLink {
                        WellnessHistoryScreen(summary: summary)
                    } label: {
                        Text("wellness.history.seeAll", bundle: .main)
                    }
                }
            }
        }
    }

    private func practiceRow(
        title: String,
        detail: String?,
        systemImage: String
    ) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: systemImage)
                .foregroundStyle(theme.color.accentCalm)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title)
                    .font(SunnieFont.body)
                    .foregroundStyle(theme.color.textPrimary)
                if let detail {
                    Text(detail)
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(SunnieFont.caption)
                .foregroundStyle(theme.color.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Space.xxs)
        .accessibilityElement(children: .combine)
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        String(
            localized: "wellness.duration.minutes",
            defaultValue: "\(Int(duration / 60)) minutes",
            comment: "Duration in minutes"
        )
    }
}

/// The check-in form.
///
/// Every dimension is optional and starts at the middle of its scale so the form
/// implies no expected answer. Options are labelled words, not faces, so they read
/// without imagery and work under VoiceOver (WELLNESS_JOURNAL_AND_CALM.md §2).
struct CheckInSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// What the sheet collected. A struct rather than six positional arguments,
    /// because two of them are the same optional type and swapping them would
    /// compile.
    struct Draft {
        let id: UUID
        let mood: WellnessScaleValue?
        let energy: WellnessScaleValue?
        let stress: WellnessScaleValue?
        let sleepQuality: WellnessScaleValue?
        let note: String?
        let hasAttachments: Bool
    }

    let onSave: (Draft) -> Void

    /// Named before the entry is saved so a photo or voice note can be attached
    /// while the form is still open. If the sheet is dismissed without saving, the
    /// attachments have no owning record and launch housekeeping sweeps them up.
    @State private var draftID = UUID()
    @State private var attachmentCount = 0
    @State private var mood: WellnessScaleValue?
    @State private var energy: WellnessScaleValue?
    @State private var stress: WellnessScaleValue?
    @State private var sleepQuality: WellnessScaleValue?
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                scaleSection(.mood, selection: $mood)
                scaleSection(.energy, selection: $energy)
                scaleSection(.stress, selection: $stress)
                scaleSection(.sleepQuality, selection: $sleepQuality)

                Section {
                    TextField(
                        String(
                            localized: "wellness.checkIn.note",
                            defaultValue: "Anything you want to note? (optional)",
                            comment: "Optional note field"
                        ),
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(1...5)
                } footer: {
                    Text("wellness.checkIn.footer", bundle: .main)
                }

                Section {
                    AttachmentsSection(owner: .checkIn(draftID)) { count in
                        attachmentCount = count
                    }
                } header: {
                    Text("wellness.checkIn.section.attachments", bundle: .main)
                }
            }
            .navigationTitle(Text("wellness.checkIn.title.short", bundle: .main))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel", defaultValue: "Cancel", comment: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(
                        localized: "wellness.checkIn.save",
                        defaultValue: "Save",
                        comment: "Saves the check-in"
                    )) {
                        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(Draft(
                            id: draftID,
                            mood: mood,
                            energy: energy,
                            stress: stress,
                            sleepQuality: sleepQuality,
                            note: trimmed.isEmpty ? nil : trimmed,
                            hasAttachments: attachmentCount > 0
                        ))
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    /// One dimension. "No answer" is a real, selectable option — leaving a
    /// question blank must not require avoiding the control.
    private func scaleSection(
        _ dimension: WellnessDimension,
        selection: Binding<WellnessScaleValue?>
    ) -> some View {
        Section {
            Picker(
                String(localized: .init(dimension.localizationKey)),
                selection: selection
            ) {
                Text("wellness.scale.unanswered", bundle: .main)
                    .tag(WellnessScaleValue?.none)
                ForEach(WellnessScaleValue.allCases, id: \.self) { value in
                    Text(LocalizedStringKey(dimension.scaleLabelKey(for: value)))
                        .tag(WellnessScaleValue?.some(value))
                }
            }
            .pickerStyle(.menu)
        } header: {
            Text(LocalizedStringKey(dimension.localizationKey))
        }
    }
}
