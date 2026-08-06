import SwiftUI
import Observation
import SunnieShared

/// Feature model for the collection (S-21).
@MainActor
@Observable
final class CollectionsModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var items: [CollectionItem] = []
    private(set) var counts: [RewardCategory: (owned: Int, total: Int)] = [:]
    private(set) var profile = ProgressionProfile()
    private(set) var rhythm: RhythmSummary?
    private(set) var nextUnlock: (reward: RewardDefinition, level: Int)?
    /// Anything the sweep granted this time round, announced once.
    private(set) var justUnlocked: [RewardDefinition] = []

    var filter = CollectionFilter.everything

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    var visibleItems: [CollectionItem] {
        items.filter(filter.matches)
    }

    /// Categories with something in them, so a tab never leads nowhere.
    var availableCategories: [RewardCategory] {
        RewardCategory.allCases.filter { counts[$0] != nil }
    }

    var ownedCount: Int { items.filter(\.isOwned).count }

    func load() async {
        if state != .loaded { state = .loading }

        // The sweep runs on every visit rather than only when something happens.
        // It is idempotent, so the cost of running it needlessly is nothing, and
        // the cost of missing it is a reward that silently never arrives.
        justUnlocked = await dependencies.manageCollection.sweep()

        do {
            items = try await dependencies.manageCollection.items()
            counts = try await dependencies.manageCollection.counts()
            profile = await dependencies.manageCollection.profile()
            nextUnlock = await dependencies.manageCollection.nextUnlock()
            rhythm = await dependencies.manageCollection.rhythm()
            state = .loaded
        } catch {
            state = .failed(String(
                localized: "collection.error.load",
                defaultValue: "I couldn't open your collection just now. Nothing has been lost, and you can try again.",
                comment: "Shown when the collection cannot be loaded"
            ))
        }
    }

    func dismissAnnouncement() {
        justUnlocked = []
    }
}

/// The collection (S-21).
///
/// **Placeholder presentation.** Every item is a labelled row rather than
/// artwork, which is also what §12 asks for when an asset is missing: a neutral
/// placeholder that keeps the ownership visible.
///
/// Locked items are shown with what unlocks them. Hiding them would make the
/// screen a list of things already done, and the point of a collection is
/// partly the things that are not.
struct CollectionsScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.sunnieTheme) private var theme

    @State private var model: CollectionsModel?
    @State private var inspecting: CollectionItem?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                switch model?.state ?? .idle {
                case .idle, .loading:
                    SunnieCard {
                        LoadingStateView(message: String(
                            localized: "collection.rewards.loading",
                            defaultValue: "Looking through the shelves…",
                            comment: "Loading state for the collection"
                        ))
                    }

                case .failed(let message):
                    ErrorStateView(
                        message: message,
                        retryTitle: String(
                            localized: "common.tryAgain",
                            defaultValue: "Try again",
                            comment: "Retry"
                        ),
                        retry: { Task { await model?.load() } }
                    )

                case .loaded:
                    if !(model?.justUnlocked.isEmpty ?? true) { announcementCard }
                    summaryCard
                    if model?.rhythm?.isVisible == true { rhythmCard }
                    filterRow
                    itemsCard
                }
            }
            .padding(Space.m)
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("more.collections", bundle: .main))
        .task {
            if model == nil { model = CollectionsModel(dependencies: dependencies) }
            await model?.load()
        }
        .sheet(item: $inspecting) { item in
            RewardDetailSheet(item: item)
        }
    }

    // MARK: - Announcement

    private var announcementCard: some View {
        SunnieCard {
            SunnieAvatarView(state: SunnieVisualState(
                expression: .excitedDiscovery, pose: .decoratingHome, presence: .medium
            ))
            Text("collection.new.title", bundle: .main)
                .font(SunnieFont.cardTitle)
                .foregroundStyle(theme.color.textPrimary)

            ForEach(model?.justUnlocked ?? []) { reward in
                Label {
                    Text(LocalizedStringKey(reward.displayNameKey))
                } icon: {
                    Image(systemName: "sparkle").accessibilityHidden(true)
                }
                .font(SunnieFont.body)
                .foregroundStyle(theme.color.textPrimary)
            }

            SunnieSecondaryButton(
                title: String(
                    localized: "collection.new.dismiss",
                    defaultValue: "Lovely",
                    comment: "Dismisses the new-unlock announcement"
                )
            ) { model?.dismissAnnouncement() }
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    format: String(
                        localized: "collection.summary.title",
                        defaultValue: "Level %d",
                        comment: "Progression level"
                    ),
                    model?.profile.level ?? 1
                ),
                subtitle: String(
                    format: String(
                        localized: "collection.summary.subtitle",
                        defaultValue: "%1$d of %2$d found",
                        comment: "How much of the collection is owned"
                    ),
                    model?.ownedCount ?? 0,
                    model?.items.count ?? 0
                )
            )

            if let next = model?.nextUnlock {
                Text(String(
                    format: String(
                        localized: "collection.next",
                        defaultValue: "At level %1$d: %2$@",
                        comment: "The next level-gated reward"
                    ),
                    next.level,
                    String(localized: .init(next.reward.displayNameKey))
                ))
                .font(SunnieFont.secondary)
                .foregroundStyle(theme.color.textSecondary)
            }
        }
    }

    /// Repeated activity, said the way §5 requires.
    ///
    /// "3 caring days this week" — never "streak", never a broken one, and never
    /// a comparison against a best the user is currently below.
    private var rhythmCard: some View {
        SunnieCard {
            SectionHeader(title: String(
                localized: "collection.rhythm.title",
                defaultValue: "Your rhythm",
                comment: "Rhythm section heading"
            ))

            if let rhythm = model?.rhythm {
                Text(String(
                    format: String(
                        localized: "collection.rhythm.days",
                        defaultValue: "%d caring days this week",
                        comment: "Days with at least one action this week"
                    ),
                    rhythm.daysThisWeek
                ))
                .font(SunnieFont.body)
                .foregroundStyle(theme.color.textPrimary)

                if rhythm.matchesBest, rhythm.bestWeek > 1 {
                    Text("collection.rhythm.best", bundle: .main)
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }

                Text("collection.rhythm.note", bundle: .main)
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
    }

    // MARK: - Filters

    private var filterRow: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xs) {
                    categoryChip(nil)
                    ForEach(model?.availableCategories ?? [], id: \.self) { category in
                        categoryChip(category)
                    }
                }
                .padding(.horizontal, Space.xxs)
            }

            Picker(
                String(
                    localized: "collection.ownership",
                    defaultValue: "Show",
                    comment: "Owned/locked filter"
                ),
                selection: Binding(
                    get: { model?.filter.ownership ?? .all },
                    set: { model?.filter.ownership = $0 }
                )
            ) {
                ForEach(CollectionFilter.Ownership.allCases, id: \.self) { option in
                    Text(LocalizedStringKey(option.localizationKey)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func categoryChip(_ category: RewardCategory?) -> some View {
        let isSelected = model?.filter.category == category
        let title = category.map { String(localized: .init($0.localizationKey)) }
            ?? String(
                localized: "collection.category.all",
                defaultValue: "Everything",
                comment: "No category filter"
            )
        let count = category.flatMap { model?.counts[$0] }

        return Button {
            model?.filter.category = isSelected ? nil : category
        } label: {
            HStack(spacing: Space.xxs) {
                Text(title)
                if let count {
                    Text("\(count.owned)/\(count.total)")
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }
            .font(SunnieFont.caption)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xxs)
            .background(
                Capsule().fill(
                    isSelected ? theme.color.accentSunnie.opacity(0.2) : theme.color.surface
                )
            )
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Items

    @ViewBuilder
    private var itemsCard: some View {
        if (model?.visibleItems ?? []).isEmpty {
            EmptyStateView(
                title: String(
                    localized: "collection.empty.title",
                    defaultValue: "Nothing here yet",
                    comment: "Empty collection filter"
                ),
                message: String(
                    localized: "collection.empty.message",
                    defaultValue: "Try another filter — there's more in the other categories.",
                    comment: "Empty collection filter message"
                ),
                visualState: SunnieVisualState(
                    expression: .curious, pose: .standingNeutral, presence: .medium
                )
            )
        } else {
            SunnieCard {
                ForEach(model?.visibleItems ?? []) { item in
                    Button {
                        inspecting = item
                    } label: {
                        CollectionRow(item: item)
                    }
                }
            }
        }
    }
}

/// One row of the collection.
///
/// Owned and locked are told apart by a symbol and by the text beside it, never
/// by colour alone.
private struct CollectionRow: View {
    @Environment(\.sunnieTheme) private var theme

    let item: CollectionItem

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: item.isOwned ? "checkmark.seal.fill" : "lock")
                .foregroundStyle(
                    item.isOwned ? theme.color.accentSunnie : theme.color.textSecondary
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(LocalizedStringKey(item.definition.displayNameKey))
                    .font(SunnieFont.body)
                    .foregroundStyle(theme.color.textPrimary)

                Text(UnlockSourceText.describe(item.definition.unlockSource))
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }

            Spacer()

            if item.isOwned {
                Text(LocalizedStringKey(item.definition.category.action.localizationKey))
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
        .padding(.vertical, Space.xxs)
        .accessibilityElement(children: .combine)
    }
}

/// Detail for one collectible (S-21: preview, source of unlock, what to do).
private struct RewardDetailSheet: View {
    @Environment(\.sunnieTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let item: CollectionItem

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text(LocalizedStringKey(item.definition.displayNameKey))
                        .font(SunnieFont.sectionTitle)
                        .foregroundStyle(theme.color.textPrimary)

                    Text(LocalizedStringKey(item.definition.descriptionKey))
                        .font(SunnieFont.body)
                        .foregroundStyle(theme.color.textSecondary)

                    SunnieCard {
                        SectionHeader(title: String(
                            localized: "collection.detail.source",
                            defaultValue: "Where it came from",
                            comment: "Unlock source heading"
                        ))
                        Text(UnlockSourceText.describe(item.definition.unlockSource))
                            .font(SunnieFont.secondary)
                            .foregroundStyle(theme.color.textPrimary)

                        if let grantedAt = item.grantedAt {
                            Text(grantedAt, format: .dateTime.day().month(.wide).year())
                                .font(SunnieFont.caption)
                                .foregroundStyle(theme.color.textSecondary)
                        }
                    }

                    if item.isOrphaned {
                        // Owned, but nothing installed describes it. Said plainly
                        // rather than hidden — the user earned this (§12).
                        SunnieCard {
                            Text("collection.orphan.explanation", bundle: .main)
                                .font(SunnieFont.secondary)
                                .foregroundStyle(theme.color.textSecondary)
                        }
                    } else if item.isOwned, item.definition.category.action == .place {
                        Text("collection.detail.placeHint", bundle: .main)
                            .font(SunnieFont.caption)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.m)
            }
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle(Text("collection.detail.title", bundle: .main))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(
                        localized: "common.done",
                        defaultValue: "Done",
                        comment: "Dismisses a sheet"
                    )) { dismiss() }
                }
            }
        }
    }
}

/// Renders an unlock source as a sentence.
///
/// Every reward has one and every one is shown, because §7 requires a reward to
/// explain where it came from. Kept out of the domain type so the shared package
/// stays free of localization plumbing.
enum UnlockSourceText {
    static func describe(_ source: UnlockSource) -> String {
        switch source {
        case .fromTheStart:
            return String(
                localized: "unlock.source.fromTheStart",
                defaultValue: "Yours from the beginning",
                comment: "A reward owned from first launch"
            )
        case .level(let level):
            return String(
                format: String(
                    localized: "unlock.source.level",
                    defaultValue: "Reaching level %d",
                    comment: "A reward unlocked at a level"
                ),
                level
            )
        case .firstTime(let type):
            return String(
                format: String(
                    localized: "unlock.source.firstTime",
                    defaultValue: "The first time you %@",
                    comment: "A reward unlocked by doing something once"
                ),
                String(localized: .init("progression.event.\(type.rawValue)"))
            )
        case .milestone(let type, let count):
            return String(
                format: String(
                    localized: "unlock.source.milestone",
                    defaultValue: "%1$@, %2$d times",
                    comment: "A reward unlocked by a count"
                ),
                String(localized: .init("progression.event.\(type.rawValue)")),
                count
            )
        case .destination:
            return String(
                localized: "unlock.source.destination",
                defaultValue: "Somewhere you've been",
                comment: "A reward unlocked by visiting a place"
            )
        case .travelMemory:
            return String(
                localized: "unlock.source.travelMemory",
                defaultValue: "Saving a memory from a trip",
                comment: "A reward unlocked by saving a travel memory"
            )
        case .game:
            return String(
                localized: "unlock.source.game",
                defaultValue: "Finishing a puzzle",
                comment: "A reward unlocked by a game"
            )
        }
    }
}
