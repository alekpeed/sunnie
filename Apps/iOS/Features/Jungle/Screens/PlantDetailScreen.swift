import SwiftUI
import SunnieShared

/// One plant's detail screen (S-04).
///
/// **Placeholder presentation.** The hero photo and illustrated treatment come
/// with the visual pass; the behaviour is complete — identity, quick care,
/// schedules, history, health, growth, photos, and the QR label.
struct PlantDetailScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    private let plantID: UUID

    @State private var model: PlantDetailModel?
    @State private var isEditing = false
    @State private var editingSchedule: PlantCareSchedule?
    @State private var isScheduleNew = false
    @State private var isShowingQR = false
    @State private var isConfirmingArchive = false
    @State private var isConfirmingRegenerate = false

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
                    recordsCard(loaded)
                    scheduleCard(loaded)
                    historyCard(loaded)
                    photosCard(loaded)
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
        .toolbar { toolbarContent }
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
        .sheet(isPresented: $isEditing) {
            if case .loaded(let loaded) = model?.state {
                PlantEditorScreen(existing: loaded.plant) { _ in
                    Task { await model?.load() }
                }
            }
        }
        .sheet(item: $editingSchedule) { schedule in
            ScheduleEditorSheet(schedule: schedule, isNew: isScheduleNew) {
                Task { await model?.load() }
            }
        }
        .sheet(isPresented: $isShowingQR) {
            if case .loaded(let loaded) = model?.state {
                qrSheet(loaded.plant)
            }
        }
        .confirmationDialog(
            Text("plant.archive.confirm", bundle: .main),
            isPresented: $isConfirmingArchive,
            titleVisibility: .visible
        ) {
            Button(String(
                localized: "plant.archive.action",
                defaultValue: "Archive it",
                comment: "Archives the plant"
            )) {
                Task {
                    try? await dependencies.managePlant.archive(plantID: plantID)
                    await model?.load()
                }
            }
        } message: {
            // Says plainly what archiving does and does not do, so it never reads
            // as deletion.
            Text("plant.archive.message", bundle: .main)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    isEditing = true
                } label: {
                    Label(
                        String(localized: "common.edit", defaultValue: "Edit", comment: "Edit"),
                        systemImage: "pencil"
                    )
                }

                Button {
                    isShowingQR = true
                } label: {
                    Label(
                        String(
                            localized: "plant.qr.show",
                            defaultValue: "Its label",
                            comment: "Shows the plant's QR label"
                        ),
                        systemImage: "qrcode"
                    )
                }

                Button {
                    addSchedule()
                } label: {
                    Label(
                        String(
                            localized: "schedule.add",
                            defaultValue: "Add a care rhythm",
                            comment: "Adds a care schedule"
                        ),
                        systemImage: "calendar.badge.plus"
                    )
                }

                Divider()

                Button {
                    isConfirmingArchive = true
                } label: {
                    Label(
                        String(
                            localized: "plant.archive",
                            defaultValue: "Archive",
                            comment: "Archives the plant"
                        ),
                        systemImage: "archivebox"
                    )
                }
            } label: {
                Label(
                    String(
                        localized: "plant.options",
                        defaultValue: "Options",
                        comment: "Plant options menu"
                    ),
                    systemImage: "ellipsis.circle"
                )
            }
        }
    }

    /// The printable label, plus the one control that invalidates it.
    private func qrSheet(_ plant: Plant) -> some View {
        NavigationStack {
            VStack(spacing: Space.l) {
                PlantQRCodeView(token: plant.qrToken, plantName: plant.displayName)

                Text("plant.qr.explain", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.l)

                ShareLink(item: PlantQRIdentity.payload(token: plant.qrToken)) {
                    Label(
                        String(
                            localized: "plant.qr.share",
                            defaultValue: "Share the link",
                            comment: "Shares the plant's QR payload"
                        ),
                        systemImage: "square.and.arrow.up"
                    )
                }

                Spacer()

                Button(role: .destructive) {
                    isConfirmingRegenerate = true
                } label: {
                    Text("plant.qr.regenerate", bundle: .main)
                        .font(SunnieFont.secondary)
                }
            }
            .padding(Space.m)
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle(Text("plant.qr.title", bundle: .main))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(
                        localized: "common.done",
                        defaultValue: "Done",
                        comment: "Done"
                    )) { isShowingQR = false }
                }
            }
            .confirmationDialog(
                Text("plant.qr.regenerate.confirm", bundle: .main),
                isPresented: $isConfirmingRegenerate,
                titleVisibility: .visible
            ) {
                Button(String(
                    localized: "plant.qr.regenerate.action",
                    defaultValue: "Make a new one",
                    comment: "Issues a new QR token"
                ), role: .destructive) {
                    Task {
                        _ = try? await dependencies.managePlant
                            .regenerateQRToken(plantID: plantID)
                        await model?.load()
                    }
                }
            } message: {
                // Anyone who has already stuck a label on a pot needs to know it
                // will stop working before they tap this.
                Text("plant.qr.regenerate.message", bundle: .main)
            }
        }
    }

    private func addSchedule() {
        isScheduleNew = true
        editingSchedule = PlantCareSchedule(
            plantID: plantID, careType: .water, recurrence: .everyDays(7)
        )
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

    /// Links to the records that belong to this plant.
    ///
    /// Health and growth are their own screens rather than sections here — a
    /// detail screen that tried to hold a year of observations and a photo
    /// timeline would become a miniature app (VISUAL_DESIGN_SYSTEM.md §9).
    private func recordsCard(_ loaded: PlantDetailModel.Loaded) -> some View {
        SunnieCard {
            NavigationLink(value: AppRoute.plantHealth(plantID)) {
                HStack {
                    Label(
                        String(
                            localized: "health.title",
                            defaultValue: "What you've noticed",
                            comment: "Health observations screen"
                        ),
                        systemImage: "eye"
                    )
                    .font(SunnieFont.body)
                    .foregroundStyle(theme.color.textPrimary)

                    Spacer()

                    if model?.openObservationCount ?? 0 > 0 {
                        StatusChip(
                            text: String(
                                localized: "collection.chip.watching",
                                defaultValue: "Watching",
                                comment: "Marks an unresolved observation"
                            ),
                            style: .attention
                        )
                    }
                }
            }

            NavigationLink(value: AppRoute.plantGrowth(plantID)) {
                Label(
                    String(
                        localized: "growth.title",
                        defaultValue: "How it's grown",
                        comment: "Growth timeline screen"
                    ),
                    systemImage: "ruler"
                )
                .font(SunnieFont.body)
                .foregroundStyle(theme.color.textPrimary)
            }
        }
    }

    /// Photos of the plant itself, separate from the dated growth timeline.
    private func photosCard(_ loaded: PlantDetailModel.Loaded) -> some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "plant.section.photos",
                    defaultValue: "Photos",
                    comment: "Section for plant photos"
                ),
                subtitle: nil
            )
            AttachmentsSection(owner: .plant(plantID))
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
                    Button {
                        isScheduleNew = false
                        editingSchedule = schedule
                    } label: {
                        HStack {
                            Label(
                                CareTypeCopy.title(schedule.careType),
                                systemImage: CareTypeCopy.symbolName(schedule.careType)
                            )
                            .font(SunnieFont.body)
                            .foregroundStyle(theme.color.textPrimary)

                            Spacer()

                            if !schedule.isEnabled {
                                StatusChip(
                                    text: String(
                                        localized: "schedule.paused",
                                        defaultValue: "Paused",
                                        comment: "A disabled schedule"
                                    ),
                                    style: .neutral
                                )
                            } else if let days = schedule.recurrence.intervalDays {
                                Text(
                                    "plant.schedule.everyDays \(days)",
                                    bundle: .main,
                                    comment: "Recurrence description; parameter is a day count"
                                )
                                .font(SunnieFont.caption)
                                .foregroundStyle(theme.color.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
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
