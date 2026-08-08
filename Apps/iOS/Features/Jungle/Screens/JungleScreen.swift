import SwiftUI
import SunnieShared

/// Jungle landing screen, and the due-only list reached from Today.
///
/// **Placeholder presentation.** Search, filters, sorting, bulk care, and
/// collection statistics are Phase 4 (PLANT_CARE.md §6); this shows the sections
/// that the vertical slice needs.
struct JungleScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    private let showsDueOnly: Bool

    @State private var model: JungleModel?
    @State private var isAddingPlant = false
    @State private var isScanning = false

    init(showsDueOnly: Bool = false) {
        self.showsDueOnly = showsDueOnly
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                switch model?.state ?? .idle {
                case .idle, .loading:
                    SunnieCard {
                        LoadingStateView(message: String(
                            localized: "jungle.loading",
                            defaultValue: "Gathering your plants…",
                            comment: "Loading state for the plant list"
                        ))
                    }

                case .failed(let message):
                    ErrorStateView(
                        message: message,
                        retryTitle: String(localized: "common.tryAgain", defaultValue: "Try again", comment: "Retry"),
                        retry: { Task { await model?.load() } }
                    )

                case .loaded(let summary, let rows):
                    content(summary: summary, rows: rows)
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
        .navigationTitle(Text(showsDueOnly ? "jungle.title.due" : "jungle.title", bundle: .main))
        .audioContext(.plantCare)
        .refreshable { await model?.load() }
        .task {
            if model == nil {
                model = JungleModel(dependencies: dependencies, showsDueOnly: showsDueOnly)
            }
            await model?.onAppear()
        }
        .onDisappear {
            Task { await model?.onDisappear() }
        }
        .toolbar {
            if !showsDueOnly {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isAddingPlant = true
                        } label: {
                            Label(
                                String(
                                    localized: "collection.add",
                                    defaultValue: "Add a plant",
                                    comment: "Adds a plant"
                                ),
                                systemImage: "plus"
                            )
                        }

                        Button {
                            isScanning = true
                        } label: {
                            Label(
                                String(
                                    localized: "plant.scan",
                                    defaultValue: "Scan a label",
                                    comment: "Opens the QR scanner"
                                ),
                                systemImage: "qrcode.viewfinder"
                            )
                        }

                        Button {
                            router.push(.collection)
                        } label: {
                            Label(
                                String(
                                    localized: "collection.title",
                                    defaultValue: "All plants",
                                    comment: "Opens the full collection"
                                ),
                                systemImage: "square.grid.2x2"
                            )
                        }
                    } label: {
                        Label(
                            String(
                                localized: "jungle.options",
                                defaultValue: "Options",
                                comment: "Jungle options menu"
                            ),
                            systemImage: "ellipsis.circle"
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $isAddingPlant) {
            PlantEditorScreen(existing: nil) { _ in
                Task { await model?.load() }
            }
        }
        .sheet(isPresented: $isScanning) {
            PlantScannerSheet { plant in
                router.push(.plant(plant.id))
            }
        }
    }

    @ViewBuilder
    private func content(
        summary: PlantTodaySummary,
        rows: [JungleModel.PlantRow]
    ) -> some View {
        if !summary.waiting.isEmpty {
            taskSection(
                title: String(
                    localized: "jungle.section.waiting",
                    defaultValue: "Still waiting",
                    comment: "Section for tasks past their due date"
                ),
                subtitle: String(
                    localized: "jungle.section.waiting.subtitle",
                    defaultValue: "These have been patient. No rush.",
                    comment: "Reassuring subtitle for the waiting section"
                ),
                tasks: summary.waiting
            )
        }

        if !summary.dueToday.isEmpty {
            taskSection(
                title: String(
                    localized: "jungle.section.today",
                    defaultValue: "Due today",
                    comment: "Section for tasks due today"
                ),
                subtitle: nil,
                tasks: summary.dueToday
            )
        }

        if !showsDueOnly {
            if !summary.upcoming.isEmpty {
                taskSection(
                    title: String(
                        localized: "jungle.section.upcoming",
                        defaultValue: "Coming up",
                        comment: "Section for upcoming tasks"
                    ),
                    subtitle: nil,
                    tasks: summary.upcoming
                )
            }

            collectionSection(rows: rows, totalPlants: summary.totalActivePlants)
        }

        if summary.actionableTasks.isEmpty && showsDueOnly {
            SunnieCard {
                EmptyStateView(
                    title: String(
                        localized: "jungle.due.empty.title",
                        defaultValue: "Nothing waiting",
                        comment: "Empty state for the due list"
                    ),
                    message: String(
                        localized: "jungle.due.empty.message",
                        defaultValue: "Your jungle is looking cared for.",
                        comment: "Empty state body for the due list"
                    ),
                    visualState: SunnieVisualState(
                        expression: .happyClosedEyed,
                        pose: .sittingNeutral,
                        presence: .medium
                    )
                )
            }
        }
    }

    private func taskSection(
        title: String,
        subtitle: String?,
        tasks: [DueCareTask]
    ) -> some View {
        SunnieCard {
            SectionHeader(title: title, subtitle: subtitle)
            ForEach(tasks) { task in
                PlantTaskRow(
                    task: task,
                    onOpen: { router.handle(.plant(task.plantID)) },
                    onComplete: { Task { await model?.completeCare(task: task) } }
                )
                if task.id != tasks.last?.id {
                    Divider().overlay(theme.color.textSecondary.opacity(0.2))
                }
            }
        }
    }

    private func collectionSection(
        rows: [JungleModel.PlantRow],
        totalPlants: Int
    ) -> some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "jungle.section.collection",
                    defaultValue: "Your collection",
                    comment: "Section listing every plant"
                ),
                subtitle: String(
                    localized: "jungle.section.collection.subtitle",
                    defaultValue: "\(totalPlants) plants",
                    comment: "Plant count"
                )
            )

            if rows.isEmpty {
                EmptyStateView(
                    title: String(localized: "jungle.empty.title", defaultValue: "No plants yet", comment: "Empty state"),
                    message: String(
                        localized: "jungle.empty.message",
                        defaultValue: "When you add your first plant, I'll keep track of when it might like some water.",
                        comment: "Empty state body"
                    ),
                    visualState: SunnieVisualState(
                        expression: .caringForPlant,
                        pose: .holdingWateringCan,
                        presence: .medium
                    )
                )
            } else {
                ForEach(rows) { row in
                    Button {
                        router.handle(.plant(row.id))
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text(row.displayName)
                                    .font(SunnieFont.body)
                                    .foregroundStyle(theme.color.textPrimary)
                                if let species = row.speciesName {
                                    Text(species)
                                        .font(SunnieFont.caption)
                                        .foregroundStyle(theme.color.textSecondary)
                                }
                            }
                            Spacer()
                            if row.nextTask != nil {
                                StatusChip(
                                    text: String(
                                        localized: "jungle.status.waitingShort",
                                        defaultValue: "Waiting",
                                        comment: "Short status for a plant with a due task"
                                    ),
                                    style: .attention
                                )
                            }
                            Image(systemName: "chevron.right")
                                .font(SunnieFont.caption)
                                .foregroundStyle(theme.color.textSecondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// A single due task with its completion action.
struct PlantTaskRow: View {
    @Environment(\.sunnieTheme) private var theme

    let task: DueCareTask
    let onOpen: () -> Void
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: Space.s) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(task.plantDisplayName)
                        .font(SunnieFont.cardTitle)
                        .foregroundStyle(theme.color.textPrimary)
                    Text(CareTypeCopy.title(task.careType))
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)

            Button(action: onComplete) {
                Image(systemName: CareTypeCopy.symbolName(task.careType))
                    .font(.title3)
                    .padding(Space.xs)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(theme.color.accentPlant)
            .accessibilityLabel(Text(
                "today.plants.completeAction \(CareTypeCopy.actionTitle(task.careType)) \(task.plantDisplayName)"
            ))
        }
        .padding(.vertical, Space.xxs)
    }
}
