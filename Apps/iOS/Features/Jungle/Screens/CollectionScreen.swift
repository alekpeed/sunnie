import SwiftUI
import SunnieShared

/// The plant collection (S-03).
///
/// **Placeholder presentation** — native list and grid rather than illustrated
/// cards. The behaviour is real: search, six filters, four sort orders,
/// grid/list, multi-select, and bulk care, with filter state that survives
/// leaving the screen.
struct CollectionScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.sunnieTheme) private var theme

    @State private var model: CollectionModel?
    @State private var isEditingPlant = false
    @State private var editingPlant: Plant?
    @State private var isShowingFilters = false
    @State private var isShowingBulkCare = false

    private let gridColumns = [
        GridItem(.adaptive(minimum: 150), spacing: Space.s)
    ]

    var body: some View {
        Group {
            switch model?.state ?? .idle {
            case .idle, .loading:
                LoadingStateView(message: String(
                    localized: "collection.loading",
                    defaultValue: "Gathering your plants…",
                    comment: "Loading state for the collection"
                ))

            case .failed(let message):
                Text(message)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
                    .padding(Space.m)

            case .loaded:
                content
            }
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("collection.title", bundle: .main))
        .searchable(text: searchBinding)
        .toolbar { toolbarContent }
        .task {
            if model == nil { model = CollectionModel(dependencies: dependencies) }
            await model?.load()
        }
        .sheet(isPresented: $isEditingPlant) {
            PlantEditorScreen(existing: editingPlant) { _ in
                Task { await model?.load() }
            }
        }
        .sheet(isPresented: $isShowingFilters) {
            if let model {
                CollectionFiltersSheet(model: model)
            }
        }
        .sheet(isPresented: $isShowingBulkCare) {
            if let model {
                BulkCareSheet(items: model.selectedItems) { recorded in
                    model.clearSelection()
                    if recorded { Task { await model.load() } }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let items = model?.visibleItems ?? []

        if items.isEmpty {
            emptyState
        } else if model?.query.mode == .grid {
            ScrollView {
                filterBanner
                LazyVGrid(columns: gridColumns, spacing: Space.s) {
                    ForEach(items) { item in
                        gridCell(item)
                    }
                }
                .padding(Space.m)
            }
        } else {
            List {
                if model?.query.isFiltering == true {
                    Section { filterBanner }
                }
                ForEach(items) { item in
                    listRow(item)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
        }
    }

    /// Says plainly that results are narrowed, and offers one tap to undo it.
    ///
    /// Without this, a filter left on from a previous session looks like a
    /// collection that lost half its plants.
    @ViewBuilder
    private var filterBanner: some View {
        if let model, model.query.isFiltering {
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(theme.color.accentPlant)
                    .accessibilityHidden(true)
                Text(
                    "collection.filtered \(model.visibleItems.count) \(model.allItems.count)",
                    bundle: .main,
                    comment: "Shows how many plants are visible out of the total"
                )
                .font(SunnieFont.caption)
                .foregroundStyle(theme.color.textSecondary)

                Spacer()

                Button(String(
                    localized: "collection.clearFilters",
                    defaultValue: "Show all",
                    comment: "Clears every filter"
                )) {
                    model.clearFilters()
                }
                .font(SunnieFont.caption)
            }
            .padding(.vertical, Space.xxs)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model?.query.isFiltering == true {
            // A filter that matches nothing is never a dead end: the way out is
            // in the empty state itself.
            EmptyStateView(
                title: String(
                    localized: "collection.empty.filtered.title",
                    defaultValue: "Nothing matches that",
                    comment: "Empty state when filters exclude everything"
                ),
                message: String(
                    localized: "collection.empty.filtered.message",
                    defaultValue: "Your plants are all still here — the filters just don't match any of them right now.",
                    comment: "Body of the filtered empty state"
                ),
                actionTitle: String(
                    localized: "collection.clearFilters",
                    defaultValue: "Show all",
                    comment: "Clears every filter"
                ),
                action: { model?.clearFilters() },
                visualState: SunnieVisualState(
                    expression: .thinking, pose: .standingNeutral, presence: .medium
                )
            )
        } else {
            EmptyStateView(
                title: String(
                    localized: "collection.empty.title",
                    defaultValue: "No plants yet",
                    comment: "Empty collection"
                ),
                message: String(
                    localized: "collection.empty.message",
                    defaultValue: "Whenever you'd like to add one, Sunnie will help you look after it.",
                    comment: "Body of the empty collection state"
                ),
                actionTitle: String(
                    localized: "collection.add",
                    defaultValue: "Add a plant",
                    comment: "Adds a plant"
                ),
                action: { addPlant() },
                visualState: SunnieVisualState(
                    expression: .happyOpenEyed, pose: .holdingWateringCan, presence: .prominent
                )
            )
        }
    }

    // MARK: - Rows

    private func listRow(_ item: PlantCollectionItem) -> some View {
        Button {
            if model?.isSelecting == true {
                model?.toggleSelection(item.id)
            } else {
                router.push(.plant(item.plant.id))
            }
        } label: {
            HStack(spacing: Space.s) {
                if model?.isSelecting == true {
                    Image(systemName: model?.selection.contains(item.id) == true
                        ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(theme.color.accentPlant)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(item.plant.displayName)
                        .font(SunnieFont.body)
                        .foregroundStyle(theme.color.textPrimary)
                        .lineLimit(1)

                    if let subtitle = subtitle(for: item) {
                        Text(subtitle)
                            .font(SunnieFont.caption)
                            .foregroundStyle(theme.color.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                statusChips(item)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(
            model?.selection.contains(item.id) == true ? [.isButton, .isSelected] : .isButton
        )
        .swipeActions(edge: .trailing) {
            Button {
                editingPlant = item.plant
                isEditingPlant = true
            } label: {
                Label(
                    String(localized: "common.edit", defaultValue: "Edit", comment: "Edit"),
                    systemImage: "pencil"
                )
            }
            .tint(theme.color.accentCalm)
        }
        .swipeActions(edge: .leading) {
            Button {
                model?.toggleSelection(item.id)
            } label: {
                Label(
                    String(
                        localized: "collection.select",
                        defaultValue: "Select",
                        comment: "Adds a plant to the selection"
                    ),
                    systemImage: "checkmark.circle"
                )
            }
            .tint(theme.color.accentPlant)
        }
    }

    private func gridCell(_ item: PlantCollectionItem) -> some View {
        Button {
            if model?.isSelecting == true {
                model?.toggleSelection(item.id)
            } else {
                router.push(.plant(item.plant.id))
            }
        } label: {
            VStack(alignment: .leading, spacing: Space.xs) {
                // Placeholder for the hero photo the visual pass will supply.
                RoundedRectangle(cornerRadius: theme.cardCornerRadius, style: .continuous)
                    .fill(theme.color.surface)
                    .frame(height: 110)
                    .overlay {
                        Image(systemName: "leaf")
                            .font(.title)
                            .foregroundStyle(theme.color.accentPlant)
                    }
                    .overlay(alignment: .topTrailing) {
                        if model?.isSelecting == true {
                            Image(systemName: model?.selection.contains(item.id) == true
                                ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(theme.color.accentPlant)
                                .padding(Space.xs)
                        }
                    }
                    .accessibilityHidden(true)

                Text(item.plant.displayName)
                    .font(SunnieFont.body)
                    .foregroundStyle(theme.color.textPrimary)
                    .lineLimit(1)

                if let subtitle = subtitle(for: item) {
                    Text(subtitle)
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// Chips carry an icon and a word, never colour alone.
    @ViewBuilder
    private func statusChips(_ item: PlantCollectionItem) -> some View {
        HStack(spacing: Space.xxs) {
            if item.openObservationCount > 0 {
                StatusChip(
                    text: String(
                        localized: "collection.chip.watching",
                        defaultValue: "Watching",
                        comment: "Marks a plant with an unresolved observation"
                    ),
                    style: .attention
                )
            }
            if item.plant.status == .archived {
                StatusChip(
                    text: String(
                        localized: "plantStatus.archived",
                        defaultValue: "Archived",
                        comment: "Archived plant"
                    ),
                    style: .neutral
                )
            }
        }
    }

    private func subtitle(for item: PlantCollectionItem) -> String? {
        var parts: [String] = []
        if let location = item.locationName { parts.append(location) }
        if let species = item.plant.speciesName { parts.append(species) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if model?.isSelecting == true {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(
                    localized: "common.done",
                    defaultValue: "Done",
                    comment: "Leaves selection mode"
                )) {
                    model?.clearSelection()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingBulkCare = true
                } label: {
                    Label(
                        String(
                            localized: "collection.bulkCare \(model?.selection.count ?? 0)",
                            defaultValue: "Care for \(model?.selection.count ?? 0)",
                            comment: "Opens bulk care for the selected plants"
                        ),
                        systemImage: "drop"
                    )
                }
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        addPlant()
                    } label: {
                        Label(
                            String(localized: "collection.add", defaultValue: "Add a plant", comment: "Adds a plant"),
                            systemImage: "plus"
                        )
                    }

                    Button {
                        isShowingFilters = true
                    } label: {
                        Label(
                            String(
                                localized: "collection.filters",
                                defaultValue: "Filters",
                                comment: "Opens the filter sheet"
                            ),
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                    }

                    Picker(selection: sortBinding) {
                        ForEach(PlantSortOrder.allCases, id: \.self) { order in
                            Text(LocalizationKeys.sortOrder(order)).tag(order)
                        }
                    } label: {
                        Text("collection.sort", bundle: .main)
                    }

                    Button {
                        toggleMode()
                    } label: {
                        Label(
                            String(
                                localized: model?.query.mode == .grid
                                    ? "collection.mode.list" : "collection.mode.grid",
                                defaultValue: model?.query.mode == .grid ? "As a list" : "As a grid",
                                comment: "Switches between list and grid"
                            ),
                            systemImage: model?.query.mode == .grid
                                ? "list.bullet" : "square.grid.2x2"
                        )
                    }

                    Button {
                        model?.selectAllVisible()
                    } label: {
                        Label(
                            String(
                                localized: "collection.selectAll",
                                defaultValue: "Select plants",
                                comment: "Enters selection mode"
                            ),
                            systemImage: "checkmark.circle"
                        )
                    }
                } label: {
                    Label(
                        String(
                            localized: "collection.options",
                            defaultValue: "Options",
                            comment: "Collection options menu"
                        ),
                        systemImage: "ellipsis.circle"
                    )
                }
            }
        }
    }

    // MARK: - Bindings and actions

    private var searchBinding: Binding<String> {
        Binding(
            get: { model?.query.searchText ?? "" },
            set: { model?.query.searchText = $0 }
        )
    }

    private var sortBinding: Binding<PlantSortOrder> {
        Binding(
            get: { model?.query.sortOrder ?? .name },
            set: { model?.query.sortOrder = $0 }
        )
    }

    private func toggleMode() {
        guard let model else { return }
        model.query.mode = model.query.mode == .grid ? .list : .grid
    }

    private func addPlant() {
        editingPlant = nil
        isEditingPlant = true
    }
}
