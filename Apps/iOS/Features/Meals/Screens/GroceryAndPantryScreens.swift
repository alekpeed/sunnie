import SwiftUI
import SunnieShared

/// The grocery list (S-17).
///
/// **Placeholder presentation**, but built for how it is actually used: one
/// hand, in a shop, at arm's length. Big rows, big tap targets. Purchased items
/// fade and sink within their group rather than vanishing — a shopper needs to
/// see what they already have.
struct GroceryScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    @State private var groups: [(category: GroceryCategory, items: [GroceryItem])] = []
    @State private var duplicates: [[GroceryItem]] = []
    @State private var entryTitles: [UUID: String] = [:]
    @State private var newName = ""
    @State private var newCategory: GroceryCategory = .other
    @State private var addedCount: Int?

    var body: some View {
        List {
            if let addedCount {
                Section {
                    Text(
                        "grocery.added \(addedCount)",
                        bundle: .main,
                        comment: "How many items were added from the plan"
                    )
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
                }
            }

            if !duplicates.isEmpty { duplicatesSection }

            addSection

            if groups.isEmpty {
                Section {
                    EmptyStateView(
                        title: String(
                            localized: "grocery.empty.title",
                            defaultValue: "Nothing on the list",
                            comment: "Empty grocery list"
                        ),
                        message: String(
                            localized: "grocery.empty.message",
                            defaultValue: "Add things as you think of them, or pull them in from what you've planned.",
                            comment: "Body of the empty grocery state"
                        ),
                        visualState: SunnieVisualState(
                            expression: .curious, pose: .standingNeutral, presence: .medium
                        )
                    )
                }
            } else {
                ForEach(groups, id: \.category) { group in
                    Section {
                        ForEach(group.items) { item in
                            row(item)
                        }
                    } header: {
                        Text(LocalizedStringKey(group.category.localizationKey))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("meals.grocery", bundle: .main))
        .toolbar { toolbarContent }
        .task { await load() }
    }

    private func row(_ item: GroceryItem) -> some View {
        HStack(spacing: Space.m) {
            Button {
                Task { await togglePurchased(item) }
            } label: {
                Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isPurchased ? theme.color.success : theme.color.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(
                item.isPurchased ? "grocery.unbuy" : "grocery.buy",
                bundle: .main
            ))

            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(item.name)
                    .font(SunnieFont.body)
                    .foregroundStyle(item.isPurchased ? theme.color.textSecondary : theme.color.textPrimary)
                    .strikethrough(item.isPurchased, color: theme.color.textSecondary)

                // Answers "why is this on my list?" without a second screen.
                if let why = reason(for: item) {
                    Text(why)
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }

            Spacer()

            if let amount = item.amount {
                Text(amount)
                    .font(SunnieFont.numeric)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
        .padding(.vertical, Space.xxs)
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    try? await dependencies.manageGrocery.delete(itemID: item.id)
                    await load()
                }
            } label: {
                Label(
                    String(localized: "common.delete", defaultValue: "Delete", comment: "Delete"),
                    systemImage: "trash"
                )
            }
        }
    }

    private var duplicatesSection: some View {
        Section {
            ForEach(Array(duplicates.enumerated()), id: \.offset) { _, group in
                HStack {
                    Text(
                        "grocery.duplicate \(group.first?.name ?? "") \(group.count)",
                        bundle: .main,
                        comment: "Names a duplicated grocery line and how many there are"
                    )
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)

                    Spacer()

                    Button(String(
                        localized: "grocery.merge",
                        defaultValue: "Merge",
                        comment: "Merges duplicate grocery lines"
                    )) {
                        Task {
                            try? await dependencies.manageGrocery.merge(group)
                            await load()
                        }
                    }
                    .font(SunnieFont.caption)
                }
            }
        } header: {
            Text("grocery.duplicates", bundle: .main)
        }
    }

    private var addSection: some View {
        Section {
            HStack {
                TextField(
                    String(
                        localized: "grocery.add",
                        defaultValue: "Add something",
                        comment: "Adds a grocery item"
                    ),
                    text: $newName
                )
                .onSubmit { Task { await add() } }

                Picker("", selection: $newCategory) {
                    ForEach(GroceryCategory.allCases, id: \.self) { category in
                        Text(LocalizedStringKey(category.localizationKey)).tag(category)
                    }
                }
                .labelsHidden()

                Button {
                    Task { await add() }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("grocery.addAction", bundle: .main))
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    Task { await addFromPlan() }
                } label: {
                    Label(
                        String(
                            localized: "grocery.fromPlan",
                            defaultValue: "Add what's planned",
                            comment: "Adds ingredients from planned meals"
                        ),
                        systemImage: "calendar"
                    )
                }

                Button {
                    Task { await moveToPantry() }
                } label: {
                    Label(
                        String(
                            localized: "grocery.toPantry",
                            defaultValue: "Put the bought things away",
                            comment: "Moves purchased items to the pantry"
                        ),
                        systemImage: "cabinet"
                    )
                }
            } label: {
                Label(
                    String(
                        localized: "collection.options",
                        defaultValue: "Options",
                        comment: "Options menu"
                    ),
                    systemImage: "ellipsis.circle"
                )
            }
        }
    }

    private func reason(for item: GroceryItem) -> String? {
        let titles = item.linkedEntryIDs.compactMap { entryTitles[$0] }
        guard !titles.isEmpty else { return nil }
        return String(
            localized: "grocery.for \(titles.joined(separator: ", "))",
            defaultValue: "for \(titles.joined(separator: ", "))",
            comment: "Which meals a grocery line came from"
        )
    }

    private func load() async {
        groups = (try? await dependencies.manageGrocery.grouped()) ?? []
        duplicates = (try? await dependencies.manageGrocery.duplicates()) ?? []

        // Titles for the "why is this here?" line. A fortnight either side
        // covers anything a current list could have come from.
        let now = dependencies.clock.now
        var calendar = dependencies.clock.calendar
        calendar.timeZone = dependencies.clock.timeZone
        let start = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let end = calendar.date(byAdding: .day, value: 14, to: now) ?? now

        let entries = (try? await dependencies.manageMeals.entries(from: start, to: end)) ?? []
        let recipes = Dictionary(
            uniqueKeysWithValues: ((try? await dependencies.manageMeals.recipes()) ?? [])
                .map { ($0.id, $0.title) }
        )
        entryTitles = Dictionary(
            uniqueKeysWithValues: entries.compactMap { entry -> (UUID, String)? in
                guard let title = entry.recipeID.flatMap({ recipes[$0] }) ?? entry.customTitle
                else { return nil }
                return (entry.id, title)
            }
        )
    }

    private func add() async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        _ = try? await dependencies.manageGrocery.add(name: name, category: newCategory)
        newName = ""
        await load()
    }

    private func togglePurchased(_ item: GroceryItem) async {
        dependencies.haptics.selection()
        try? await dependencies.manageGrocery.setPurchased(!item.isPurchased, item: item)
        await load()
    }

    private func addFromPlan() async {
        let now = dependencies.clock.now
        var calendar = dependencies.clock.calendar
        calendar.timeZone = dependencies.clock.timeZone
        let end = calendar.date(byAdding: .day, value: 14, to: now) ?? now

        addedCount = try? await dependencies.manageGrocery.addFromPlan(from: now, to: end)
        await load()
    }

    private func moveToPantry() async {
        _ = try? await dependencies.manageGrocery.movePurchasedToPantry()
        addedCount = nil
        await load()
    }
}

/// The pantry.
///
/// **Dates here are the user's own and mean only what they wrote.** They order
/// the list and nothing else. The app has no basis for saying whether food is
/// good, and the spec forbids asserting it (MEALS_AND_PREP.md §7).
struct PantryScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    @State private var items: [PantryItem] = []
    @State private var editing: PantryItem?
    @State private var selection: Set<UUID> = []

    var body: some View {
        List {
            if items.isEmpty {
                Section {
                    EmptyStateView(
                        title: String(
                            localized: "pantry.empty.title",
                            defaultValue: "Nothing recorded",
                            comment: "Empty pantry"
                        ),
                        message: String(
                            localized: "pantry.empty.message",
                            defaultValue: "Things move here when you tick them off the shopping list, or you can add them yourself.",
                            comment: "Body of the empty pantry state"
                        ),
                        visualState: SunnieVisualState(
                            expression: .curious, pose: .standingNeutral, presence: .medium
                        )
                    )
                }
            } else {
                let useFirst = items.filter(\.useBeforeTrip)
                let rest = items.filter { !$0.useBeforeTrip }

                if !useFirst.isEmpty {
                    Section {
                        ForEach(useFirst) { item in
                            row(item)
                        }
                    } header: {
                        Text("pantry.section.useFirst", bundle: .main)
                    } footer: {
                        Text("meals.useFirst.footer", bundle: .main)
                    }
                }

                Section {
                    ForEach(rest) { item in
                        row(item)
                    }
                } header: {
                    Text("pantry.section.everything", bundle: .main)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("meals.pantry", bundle: .main))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = dependencies.manageGrocery.newPantryItem()
                } label: {
                    Label(
                        String(
                            localized: "pantry.add",
                            defaultValue: "Add something",
                            comment: "Adds a pantry item"
                        ),
                        systemImage: "plus"
                    )
                }
            }
        }
        .task { await load() }
        .sheet(item: $editing) { item in
            PantryEditorSheet(item: item) { Task { await load() } }
        }
    }

    private func row(_ item: PantryItem) -> some View {
        Button {
            editing = item
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(item.name)
                        .font(SunnieFont.body)
                        .foregroundStyle(theme.color.textPrimary)
                    if let location = item.storageLocation {
                        Text(location)
                            .font(SunnieFont.caption)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                }
                Spacer()
                if let date = item.bestBefore {
                    // Shown as the user wrote it, with no interpretation.
                    Text(date, format: .dateTime.day().month())
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .leading) {
            Button {
                Task {
                    try? await dependencies.manageGrocery.setUseBeforeTrip(
                        !item.useBeforeTrip, itemIDs: [item.id]
                    )
                    await load()
                }
            } label: {
                Label(
                    String(
                        localized: "pantry.useFirst",
                        defaultValue: "Use first",
                        comment: "Marks an item to use before a trip"
                    ),
                    systemImage: "arrow.up.circle"
                )
            }
            .tint(theme.color.accentWarm)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    try? await dependencies.manageGrocery.deletePantryItem(id: item.id)
                    await load()
                }
            } label: {
                Label(
                    String(localized: "common.delete", defaultValue: "Delete", comment: "Delete"),
                    systemImage: "trash"
                )
            }
        }
    }

    private func load() async {
        items = (try? await dependencies.manageGrocery.pantryItems()) ?? []
    }
}

/// Editor for one pantry item.
struct PantryEditorSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sunnieTheme) private var theme

    @State var item: PantryItem
    let onSaved: () -> Void

    @State private var hasBestBefore = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        String(
                            localized: "pantry.field.name",
                            defaultValue: "What it is",
                            comment: "A pantry item's name"
                        ),
                        text: $item.name
                    )
                    TextField(
                        String(
                            localized: "pantry.field.amount",
                            defaultValue: "How much",
                            comment: "A pantry item's amount"
                        ),
                        text: Binding(
                            get: { item.amount ?? "" },
                            set: { item.amount = $0.isEmpty ? nil : $0 }
                        )
                    )
                    Picker(selection: $item.category) {
                        ForEach(GroceryCategory.allCases, id: \.self) { category in
                            Text(LocalizedStringKey(category.localizationKey)).tag(category)
                        }
                    } label: {
                        Text("pantry.field.category", bundle: .main)
                    }
                    TextField(
                        String(
                            localized: "pantry.field.location",
                            defaultValue: "Where it lives",
                            comment: "Storage location"
                        ),
                        text: Binding(
                            get: { item.storageLocation ?? "" },
                            set: { item.storageLocation = $0.isEmpty ? nil : $0 }
                        )
                    )
                }

                Section {
                    Toggle(isOn: $hasBestBefore) {
                        Text("pantry.field.hasBestBefore", bundle: .main)
                    }
                    if hasBestBefore {
                        DatePicker(
                            selection: Binding(
                                get: { item.bestBefore ?? Date() },
                                set: { item.bestBefore = $0 }
                            ),
                            displayedComponents: .date
                        ) {
                            Text("pantry.field.bestBefore", bundle: .main)
                        }
                    }

                    Toggle(isOn: $item.useBeforeTrip) {
                        Text("pantry.field.useFirst", bundle: .main)
                    }
                } footer: {
                    // The disclaimer the spec requires, stated plainly rather
                    // than implied.
                    Text("pantry.field.bestBefore.footer", bundle: .main)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle(Text("pantry.editor.title", bundle: .main))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(
                        localized: "common.cancel",
                        defaultValue: "Cancel",
                        comment: "Cancel"
                    )) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(
                        localized: "common.save",
                        defaultValue: "Save",
                        comment: "Save"
                    )) {
                        Task {
                            var toSave = item
                            if !hasBestBefore { toSave.bestBefore = nil }
                            _ = try? await dependencies.manageGrocery.save(toSave)
                            onSaved()
                            dismiss()
                        }
                    }
                    .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task { hasBestBefore = item.bestBefore != nil }
        }
    }
}
