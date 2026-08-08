import SwiftUI
import SunnieShared

/// The plant slice of Today.
///
/// **Placeholder presentation.** The copy is not placeholder: every string here
/// is deliberately non-judgemental. A task past its date is "waiting", never
/// "overdue" or "late", and the phrasing is "may be ready" rather than "must be
/// watered", because the app schedules reminders without claiming biological
/// certainty (PLANT_CARE.md §4, TONE_COPY_AND_BEHAVIOR.md).
struct PlantTaskCard: View {
    @Environment(\.sunnieTheme) private var theme

    let summary: PlantTodaySummary
    let onOpenDueList: () -> Void
    let onComplete: (DueCareTask) -> Void
    let onOpenPlant: (UUID) -> Void

    /// One task on the card; the rest live behind "See all".
    private var leadTask: DueCareTask? { summary.actionableTasks.first }

    var body: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "today.plants.title",
                    defaultValue: "Your jungle",
                    comment: "Title of the plant card on Today"
                ),
                subtitle: subtitle
            )

            if let leadTask {
                taskRow(leadTask)

                if summary.actionableTasks.count > 1 {
                    SunnieSecondaryButton(
                        title: String(
                            localized: "today.plants.seeAll",
                            defaultValue: "See all \(summary.actionableTasks.count)",
                            comment: "Opens the full due list; parameter is the task count"
                        ),
                        systemImage: "list.bullet",
                        action: onOpenDueList
                    )
                }
            } else if summary.totalActivePlants == 0 {
                EmptyStateView(
                    title: String(
                        localized: "jungle.empty.title",
                        defaultValue: "No plants yet",
                        comment: "Empty state when no plants exist"
                    ),
                    message: String(
                        localized: "jungle.empty.message",
                        defaultValue: "When you add your first plant, I'll keep track of when it might like some water.",
                        comment: "Empty state body when no plants exist"
                    ),
                    visualState: SunnieVisualState(
                        expression: .caringForPlant,
                        pose: .holdingWateringCan,
                        presence: .medium
                    )
                )
            } else {
                nothingDueState
            }
        }
    }

    private var subtitle: String {
        if summary.actionableTasks.isEmpty {
            return String(
                localized: "today.plants.subtitle.clear",
                defaultValue: "\(summary.totalActivePlants) plants, nothing waiting",
                comment: "Plant card subtitle when no care is due"
            )
        }
        return String(
            localized: "today.plants.subtitle.waiting",
            defaultValue: "\(summary.actionableTasks.count) may be ready for a little attention",
            comment: "Plant card subtitle; parameter is the number of tasks"
        )
    }

    private var nothingDueState: some View {
        HStack(spacing: Space.s) {
            SunnieAvatarView(
                state: SunnieVisualState(
                    expression: .happyClosedEyed,
                    pose: .sittingNeutral,
                    presence: .small
                )
            )
            Text(
                "today.plants.allCaredFor",
                bundle: .main,
                comment: "Shown when nothing is due"
            )
            .font(SunnieFont.body)
            .foregroundStyle(theme.color.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private func taskRow(_ task: DueCareTask) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Button {
                onOpenPlant(task.plantID)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(task.plantDisplayName)
                            .font(SunnieFont.cardTitle)
                            .foregroundStyle(theme.color.textPrimary)
                        Text(CareTypeCopy.title(task.careType))
                            .font(SunnieFont.secondary)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                    Spacer()
                    StatusChip(text: statusText(task), style: statusStyle(task))
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text(
                "today.plants.openHint",
                bundle: .main,
                comment: "VoiceOver hint for opening a plant from Today"
            ))

            SunniePrimaryButton(
                title: CareTypeCopy.actionTitle(task.careType),
                systemImage: CareTypeCopy.symbolName(task.careType),
                action: { onComplete(task) }
            )
            .accessibilityLabel(Text(
                "today.plants.completeAction \(CareTypeCopy.actionTitle(task.careType)) \(task.plantDisplayName)"
            ))
        }
    }

    /// Waiting is stated as neutral fact — how long, not how bad.
    private func statusText(_ task: DueCareTask) -> String {
        switch task.urgency {
        case .dueToday:
            String(
                localized: "jungle.status.today",
                defaultValue: "Today",
                comment: "Task is due today"
            )
        case .waiting:
            String(
                localized: "jungle.status.waiting",
                defaultValue: "Waiting \(task.daysWaiting) days",
                comment: "Task has been due for a number of days"
            )
        case .upcoming:
            String(
                localized: "jungle.status.upcoming",
                defaultValue: "Soon",
                comment: "Task is due in the future"
            )
        }
    }

    private func statusStyle(_ task: DueCareTask) -> StatusChip.Style {
        switch task.urgency {
        case .waiting: .attention
        case .dueToday, .upcoming: .neutral
        }
    }
}

/// User-facing copy for care types, in one place so no screen invents its own.
enum CareTypeCopy {

    static func title(_ careType: CareType) -> String {
        switch careType {
        case .water: String(localized: "care.water", defaultValue: "Water", comment: "Care type")
        case .fertilize: String(localized: "care.fertilize", defaultValue: "Fertilize", comment: "Care type")
        case .mist: String(localized: "care.mist", defaultValue: "Mist", comment: "Care type")
        case .rotate: String(localized: "care.rotate", defaultValue: "Rotate", comment: "Care type")
        case .cleanLeaves: String(localized: "care.cleanLeaves", defaultValue: "Clean leaves", comment: "Care type")
        case .prune: String(localized: "care.prune", defaultValue: "Prune", comment: "Care type")
        case .repot: String(localized: "care.repot", defaultValue: "Repot", comment: "Care type")
        case .propagate: String(localized: "care.propagate", defaultValue: "Propagate", comment: "Care type")
        case .pestTreatment: String(localized: "care.pestTreatment", defaultValue: "Pest treatment", comment: "Care type")
        case .healthInspection: String(localized: "care.healthInspection", defaultValue: "Health check", comment: "Care type")
        case .custom: String(localized: "care.custom", defaultValue: "Custom care", comment: "Care type")
        }
    }

    /// The button label. Phrased as the action the user is taking, in the past
    /// tense of a thing they did — never as an instruction.
    static func actionTitle(_ careType: CareType) -> String {
        switch careType {
        case .water: String(localized: "care.action.water", defaultValue: "Mark watered", comment: "Care action button")
        case .fertilize: String(localized: "care.action.fertilize", defaultValue: "Mark fertilized", comment: "Care action button")
        case .mist: String(localized: "care.action.mist", defaultValue: "Mark misted", comment: "Care action button")
        default: String(localized: "care.action.generic", defaultValue: "Mark done", comment: "Generic care action button")
        }
    }

    static func symbolName(_ careType: CareType) -> String {
        switch careType {
        case .water: "drop"
        case .fertilize: "sparkles"
        case .mist: "humidity"
        case .rotate: "arrow.triangle.2.circlepath"
        case .cleanLeaves: "hand.raised"
        case .prune: "scissors"
        case .repot: "shippingbox"
        case .propagate: "leaf.arrow.triangle.circlepath"
        case .pestTreatment: "ant"
        case .healthInspection: "magnifyingglass"
        case .custom: "star"
        }
    }
}
