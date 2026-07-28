import SwiftUI
import SunnieShared

/// One plant's detail screen.
///
/// **Placeholder presentation.** Editing, health observations, growth photos,
/// travel coverage, and QR display are Phase 4. This carries what the vertical
/// slice needs: identity, schedules, care history, and the Water action.
struct PlantDetailScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    private let plantID: UUID

    @State private var model: PlantDetailModel?

    init(plantID: UUID) {
        self.plantID = plantID
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                switch model?.state ?? .idle {
                case .idle, .loading:
                    SunnieCard {
                        LoadingStateView(message: String(
                            localized: "plant.loading",
                            defaultValue: "Opening this plant…",
                            comment: "Loading state for plant detail"
                        ))
                    }

                case .failed(let message):
                    ErrorStateView(
                        message: message,
                        retryTitle: String(localized: "common.tryAgain", defaultValue: "Try again", comment: "Retry"),
                        retry: { Task { await model?.load() } }
                    )

                case .loaded(let loaded):
                    identityCard(loaded)
                    scheduleCard(loaded)
                    historyCard(loaded)
                }

                if let reaction = model?.lastReaction {
                    SunnieCard {
                        SunnieMessageView(message: reaction, presence: .small)
                    }
                }
            }
            .padding(Space.m)
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.large)
        .task {
            if model == nil {
                model = PlantDetailModel(plantID: plantID, dependencies: dependencies)
            }
            await model?.load()
        }
        .sheet(isPresented: quickCareBinding) {
            if let model {
                QuickCareSheet(
                    careTypes: model.offeredCareTypes,
                    onLog: { careType, performedAt, note in
                        Task { await model.logCare(
                            careType: careType, performedAt: performedAt, note: note
                        ) }
                    }
                )
            }
        }
    }

    private var navigationTitle: String {
        if case .loaded(let loaded) = model?.state {
            return loaded.plant.displayName
        }
        return String(localized: "plant.title", defaultValue: "Plant", comment: "Plant detail title")
    }

    private var quickCareBinding: Binding<Bool> {
        Binding(
            get: { model?.isQuickCarePresented ?? false },
            set: { model?.isQuickCarePresented = $0 }
        )
    }

    // MARK: - Cards

    private func identityCard(_ loaded: PlantDetailModel.Loaded) -> some View {
        SunnieCard {
            HStack(alignment: .top, spacing: Space.m) {
                SunnieAvatarView(
                    state: SunnieVisualState(
                        expression: .caringForPlant,
                        pose: .holdingWateringCan,
                        presence: .medium
                    )
                )
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(loaded.plant.displayName)
                        .font(SunnieFont.sectionTitle)
                        .foregroundStyle(theme.color.textPrimary)
                    if let species = loaded.plant.speciesName {
                        Text(species)
                            .font(SunnieFont.secondary)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            SunniePrimaryButton(
                title: String(
                    localized: "plant.action.logCare",
                    defaultValue: "Log care",
                    comment: "Opens the quick care sheet"
                ),
                systemImage: "drop",
                action: { model?.isQuickCarePresented = true }
            )
        }
    }

    private func scheduleCard(_ loaded: PlantDetailModel.Loaded) -> some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "plant.section.schedules",
                    defaultValue: "Care rhythm",
                    comment: "Section listing care schedules"
                ),
                subtitle: String(
                    localized: "plant.section.schedules.subtitle",
                    defaultValue: "A gentle guide, not a rule.",
                    comment: "Clarifies that schedules are suggestions"
                )
            )

            if loaded.schedules.isEmpty {
                Text(
                    "plant.schedules.none",
                    bundle: .main,
                    comment: "Shown when a plant has no schedules"
                )
                .font(SunnieFont.secondary)
                .foregroundStyle(theme.color.textSecondary)
            } else {
                ForEach(loaded.schedules) { schedule in
                    HStack {
                        Label(
                            CareTypeCopy.title(schedule.careType),
                            systemImage: CareTypeCopy.symbolName(schedule.careType)
                        )
                        .font(SunnieFont.body)
                        .foregroundStyle(theme.color.textPrimary)

                        Spacer()

                        if let days = schedule.recurrence.intervalDays {
                            Text(
                                "plant.schedule.everyDays \(days)",
                                bundle: .main,
                                comment: "Recurrence description; parameter is a day count"
                            )
                            .font(SunnieFont.caption)
                            .foregroundStyle(theme.color.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func historyCard(_ loaded: PlantDetailModel.Loaded) -> some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "plant.section.history",
                    defaultValue: "Recent care",
                    comment: "Section listing recent care events"
                ),
                subtitle: nil
            )

            if loaded.recentEvents.isEmpty {
                Text(
                    "plant.history.none",
                    bundle: .main,
                    comment: "Shown when a plant has no recorded care"
                )
                .font(SunnieFont.secondary)
                .foregroundStyle(theme.color.textSecondary)
            } else {
                ForEach(loaded.recentEvents) { event in
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        HStack {
                            Text(CareTypeCopy.title(event.careType))
                                .font(SunnieFont.body)
                                .foregroundStyle(theme.color.textPrimary)
                            Spacer()
                            Text(event.performedAt, format: .dateTime.day().month().hour().minute())
                                .font(SunnieFont.caption)
                                .foregroundStyle(theme.color.textSecondary)
                        }
                        if let note = event.note, !note.isEmpty {
                            Text(note)
                                .font(SunnieFont.caption)
                                .foregroundStyle(theme.color.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
