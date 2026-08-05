import SwiftUI
import SunnieShared

/// Editor for one planned meal (S-16).
struct MealEntryEditorSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sunnieTheme) private var theme

    @State var entry: MealPlanEntry
    let onSaved: () -> Void

    @State private var recipes: [Recipe] = []
    @State private var setAside: [(recipe: Recipe, verdict: DietaryFilter.Verdict)] = []
    @State private var hasPrepTime = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        selection: $entry.date,
                        displayedComponents: .date
                    ) {
                        Text("meals.field.day", bundle: .main)
                    }

                    Picker(selection: $entry.slot) {
                        ForEach(MealSlot.allCases, id: \.self) { slot in
                            Text(LocalizedStringKey(slot.localizationKey)).tag(slot)
                        }
                    } label: {
                        Text("meals.field.slot", bundle: .main)
                    }

                    Picker(selection: $entry.context) {
                        ForEach(DayContext.allCases, id: \.self) { context in
                            Text(LocalizedStringKey(context.localizationKey)).tag(context)
                        }
                    } label: {
                        Text("meals.dayContext", bundle: .main)
                    }
                }

                Section {
                    Picker(selection: $entry.recipeID) {
                        Text("meals.recipe.none", bundle: .main).tag(UUID?.none)
                        ForEach(recipes) { recipe in
                            Text(recipe.title).tag(UUID?.some(recipe.id))
                        }
                    } label: {
                        Text("meals.field.recipe", bundle: .main)
                    }

                    TextField(
                        String(
                            localized: "meals.field.custom",
                            defaultValue: "Or just write it",
                            comment: "A one-off meal name"
                        ),
                        text: Binding(
                            get: { entry.customTitle ?? "" },
                            set: { entry.customTitle = $0.isEmpty ? nil : $0 }
                        )
                    )
                } footer: {
                    // Says plainly what was set aside and why, rather than
                    // letting the recipe list quietly shrink.
                    if !setAside.isEmpty {
                        Text(
                            "meals.setAside \(setAside.count)",
                            bundle: .main,
                            comment: "How many recipes the dietary rules set aside"
                        )
                    }
                }

                Section {
                    Toggle(isOn: $entry.isPacked) {
                        Text("meals.field.packed", bundle: .main)
                    }
                    Toggle(isOn: $entry.needsRefrigeration) {
                        Text("meals.field.refrigerate", bundle: .main)
                    }
                    Toggle(isOn: $hasPrepTime) {
                        Text("meals.field.hasPrep", bundle: .main)
                    }
                    if hasPrepTime {
                        DatePicker(
                            selection: Binding(
                                get: { entry.prepAt ?? entry.date },
                                set: { entry.prepAt = $0 }
                            )
                        ) {
                            Text("meals.field.prepAt", bundle: .main)
                        }
                    }
                }

                Section {
                    TextField(
                        String(
                            localized: "meals.field.notes",
                            defaultValue: "Notes",
                            comment: "Notes on a planned meal"
                        ),
                        text: Binding(
                            get: { entry.notes ?? "" },
                            set: { entry.notes = $0.isEmpty ? nil : $0 }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(1...6)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle(Text("meals.editor.title", bundle: .main))
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
                            var toSave = entry
                            if !hasPrepTime { toSave.prepAt = nil }
                            _ = try? await dependencies.manageMeals.save(toSave)
                            onSaved()
                            dismiss()
                        }
                    }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        // Only recipes with nothing matching are offered. The count of what was
        // set aside is shown, so the list never looks mysteriously short.
        let partitioned = try? await dependencies.manageMeals.partitionedRecipes()
        recipes = partitioned?.clear ?? []
        setAside = partitioned?.setAside ?? []
        hasPrepTime = entry.prepAt != nil
    }
}

/// The recipe list.
///
/// Recipes matching an active dietary rule are set aside rather than hidden.
/// **What is shown says what was matched, not that anything is safe** — this is
/// text matching over ingredient names, and the app has no ingredient database
/// (MEALS_AND_PREP.md §2).
struct RecipeListScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    @State private var clear: [Recipe] = []
    @State private var setAside: [(recipe: Recipe, verdict: DietaryFilter.Verdict)] = []
    @State private var editing: Recipe?
    @State private var showsSetAside = false
    @State private var searchText = ""

    var body: some View {
        List {
            if clear.isEmpty && setAside.isEmpty {
                Section {
                    EmptyStateView(
                        title: String(
                            localized: "recipes.empty.title",
                            defaultValue: "No recipes yet",
                            comment: "Empty recipe list"
                        ),
                        message: String(
                            localized: "recipes.empty.message",
                            defaultValue: "Write down the things you actually cook. Sunnie will only ever suggest from these.",
                            comment: "Body of the empty recipe state"
                        ),
                        visualState: SunnieVisualState(
                            expression: .happyOpenEyed, pose: .holdingMug, presence: .medium
                        )
                    )
                }
            } else {
                Section {
                    ForEach(visible) { recipe in
                        row(recipe)
                    }
                }

                if !setAside.isEmpty {
                    setAsideSection
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("meals.recipes", bundle: .main))
        .searchable(text: $searchText)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = dependencies.manageMeals.newRecipe()
                } label: {
                    Label(
                        String(
                            localized: "recipes.add",
                            defaultValue: "Add a recipe",
                            comment: "Adds a recipe"
                        ),
                        systemImage: "plus"
                    )
                }
            }
        }
        .task { await load() }
        .sheet(item: $editing) { recipe in
            RecipeEditorSheet(recipe: recipe) { Task { await load() } }
        }
    }

    private var visible: [Recipe] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return clear }
        return clear.filter {
            $0.title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// The recipes an active rule matched.
    ///
    /// Collapsed by default and openable — the user knows they saved them, and a
    /// list that silently shrinks is worse than one that explains itself. The
    /// copy describes what was *found in the text*, never a safety claim.
    private var setAsideSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showsSetAside) {
                ForEach(setAside, id: \.recipe.id) { entry in
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Button {
                            editing = entry.recipe
                        } label: {
                            Text(entry.recipe.title)
                                .font(SunnieFont.body)
                                .foregroundStyle(theme.color.textPrimary)
                        }
                        .buttonStyle(.plain)

                        Text(
                            "recipes.setAside.because \(entry.verdict.matchingIngredients.joined(separator: ", "))",
                            bundle: .main,
                            comment: "Which ingredients matched a dietary rule"
                        )
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } label: {
                Text(
                    "recipes.setAside \(setAside.count)",
                    bundle: .main,
                    comment: "How many recipes were set aside"
                )
                .font(SunnieFont.body)
            }
        } footer: {
            // The disclaimer the spec requires, in plain words.
            Text("recipes.setAside.footer", bundle: .main)
        }
    }

    private func row(_ recipe: Recipe) -> some View {
        Button {
            editing = recipe
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(recipe.title)
                        .font(SunnieFont.body)
                        .foregroundStyle(theme.color.textPrimary)
                    if let minutes = recipe.totalMinutes {
                        Text(
                            "recipes.minutes \(minutes)",
                            bundle: .main,
                            comment: "How long a recipe takes"
                        )
                        .font(SunnieFont.caption)
                        .foregroundStyle(theme.color.textSecondary)
                    }
                }
                Spacer()
                if recipe.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(theme.color.accentWarm)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    try? await dependencies.manageMeals.deleteRecipe(id: recipe.id)
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
        let partitioned = try? await dependencies.manageMeals.partitionedRecipes()
        clear = partitioned?.clear ?? []
        setAside = partitioned?.setAside ?? []
    }
}

/// Editor for one recipe.
struct RecipeEditorSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sunnieTheme) private var theme

    @State var recipe: Recipe
    let onSaved: () -> Void

    @State private var newIngredient = ""
    @State private var newIngredientCategory: GroceryCategory = .other
    @State private var newStep = ""
    @State private var flaggedIngredients: Set<String> = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        String(
                            localized: "recipes.field.title",
                            defaultValue: "What it's called",
                            comment: "A recipe's title"
                        ),
                        text: $recipe.title
                    )
                    Toggle(isOn: $recipe.isFavorite) {
                        Text("recipes.field.favorite", bundle: .main)
                    }
                }

                ingredientsSection
                stepsSection
                timingSection
                travelSection
            }
            .scrollContentBackground(.hidden)
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle(Text("recipes.editor.title", bundle: .main))
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
                            _ = try? await dependencies.manageMeals.save(recipe)
                            onSaved()
                            dismiss()
                        }
                    }
                    .disabled(recipe.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task { await refreshFlags() }
        }
    }

    private var ingredientsSection: some View {
        Section {
            ForEach(recipe.ingredients) { ingredient in
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(ingredient.name)
                        if let amount = ingredient.amount {
                            Text(amount)
                                .font(SunnieFont.caption)
                                .foregroundStyle(theme.color.textSecondary)
                        }
                    }
                    Spacer()
                    // Flagged at the point of typing, so the user is not
                    // surprised later by a recipe that disappears from
                    // suggestions.
                    if flaggedIngredients.contains(ingredient.name) {
                        Text("recipes.flagged", bundle: .main)
                            .font(SunnieFont.caption)
                            .foregroundStyle(theme.color.attention)
                    }
                }
            }
            .onDelete { offsets in
                recipe.ingredients.remove(atOffsets: offsets)
                Task { await refreshFlags() }
            }

            HStack {
                TextField(
                    String(
                        localized: "recipes.field.ingredient",
                        defaultValue: "Add an ingredient",
                        comment: "Adds an ingredient"
                    ),
                    text: $newIngredient
                )
                .onSubmit { addIngredient() }

                Picker("", selection: $newIngredientCategory) {
                    ForEach(GroceryCategory.allCases, id: \.self) { category in
                        Text(LocalizedStringKey(category.localizationKey)).tag(category)
                    }
                }
                .labelsHidden()

                Button {
                    addIngredient()
                } label: {
                    Image(systemName: "plus.circle")
                }
                .disabled(newIngredient.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("recipes.addIngredient", bundle: .main))
            }
        } header: {
            Text("recipes.section.ingredients", bundle: .main)
        } footer: {
            if !flaggedIngredients.isEmpty {
                // The precise claim: the text matched. Not that it is unsafe.
                Text("recipes.flagged.footer", bundle: .main)
            }
        }
    }

    private var stepsSection: some View {
        Section {
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                Text("\(index + 1). \(step)")
                    .font(SunnieFont.secondary)
            }
            .onDelete { recipe.steps.remove(atOffsets: $0) }

            HStack {
                TextField(
                    String(
                        localized: "recipes.field.step",
                        defaultValue: "Add a step",
                        comment: "Adds a recipe step"
                    ),
                    text: $newStep,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .onSubmit { addStep() }

                Button {
                    addStep()
                } label: {
                    Image(systemName: "plus.circle")
                }
                .disabled(newStep.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("recipes.addStep", bundle: .main))
            }
        } header: {
            Text("recipes.section.steps", bundle: .main)
        }
    }

    private var timingSection: some View {
        Section {
            Stepper(value: Binding(
                get: { recipe.prepMinutes ?? 0 },
                set: { recipe.prepMinutes = $0 == 0 ? nil : $0 }
            ), in: 0...240, step: 5) {
                Text(
                    "recipes.field.prep \(recipe.prepMinutes ?? 0)",
                    bundle: .main,
                    comment: "Preparation time in minutes"
                )
            }

            Stepper(value: Binding(
                get: { recipe.cookMinutes ?? 0 },
                set: { recipe.cookMinutes = $0 == 0 ? nil : $0 }
            ), in: 0...480, step: 5) {
                Text(
                    "recipes.field.cook \(recipe.cookMinutes ?? 0)",
                    bundle: .main,
                    comment: "Cooking time in minutes"
                )
            }
        } header: {
            Text("recipes.section.timing", bundle: .main)
        }
    }

    private var travelSection: some View {
        Section {
            Picker(selection: $recipe.portability) {
                ForEach(Portability.allCases, id: \.self) { value in
                    Text(LocalizedStringKey(value.localizationKey)).tag(value)
                }
            } label: {
                Text("recipes.field.portability", bundle: .main)
            }

            Toggle(isOn: $recipe.keepsRefrigerated) {
                Text("recipes.field.refrigerated", bundle: .main)
            }

            TextField(
                String(
                    localized: "recipes.field.container",
                    defaultValue: "What to put it in",
                    comment: "Container note"
                ),
                text: Binding(
                    get: { recipe.containerNote ?? "" },
                    set: { recipe.containerNote = $0.isEmpty ? nil : $0 }
                )
            )
        } header: {
            Text("recipes.section.travel", bundle: .main)
        } footer: {
            // The storage estimate carries no guarantee, and the footer says so
            // rather than leaving it implied (MEALS_AND_PREP.md §9).
            Text("recipes.section.travel.footer", bundle: .main)
        }
    }

    private func addIngredient() {
        let name = newIngredient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        recipe.ingredients.append(
            Ingredient(name: name, category: newIngredientCategory)
        )
        newIngredient = ""
        Task { await refreshFlags() }
    }

    private func addStep() {
        let step = newStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !step.isEmpty else { return }
        recipe.steps.append(step)
        newStep = ""
    }

    private func refreshFlags() async {
        let exclusions = await dependencies.manageMeals.activeExclusions()
        flaggedIngredients = Set(
            recipe.ingredients
                .filter { !DietaryFilter.matches(ingredientName: $0.name, against: exclusions).isEmpty }
                .map(\.name)
        )
    }
}
