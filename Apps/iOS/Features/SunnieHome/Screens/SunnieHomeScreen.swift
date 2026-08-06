import SwiftUI
import Observation
import SunnieShared

/// Feature model for Sunnie's home (S-22).
@MainActor
@Observable
final class SunnieHomeModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var variant: HomeSceneVariant?
    private(set) var scene = HomeSceneState(updatedAt: Date())
    private(set) var placements: [ContentID: RewardDefinition] = [:]
    private(set) var outfits: [RewardDefinition] = []
    private(set) var sounds: [RewardDefinition] = []
    private(set) var memories: [TravelMemory] = []
    private(set) var plants: [Plant] = []
    private(set) var unreadScenes: [StoryScene] = []
    /// The last refusal, so the reason a placement did not happen is shown where
    /// it happened rather than as a generic failure.
    private(set) var refusal: PlacementRefusal?

    var isEditing = false
    var selectedZone: HomeZone = .cozyRoom

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    var slots: [DecorSlot] {
        dependencies.manageCollection.slots
            .filter { $0.zone == selectedZone }
            .sorted { $0.order < $1.order }
    }

    /// Zones that have something to show or arrange.
    var zones: [HomeZone] {
        HomeZone.allCases.filter { zone in
            zone == .window
                || dependencies.manageCollection.slots.contains { $0.zone == zone }
        }
    }

    func load(phase: TimePhase, themeID: ContentID, reduceMotion: Bool) async {
        if state != .loaded { state = .loading }

        let home = dependencies.manageHome
        scene = (try? await home.sceneState()) ?? HomeSceneState(updatedAt: Date())
        placements = await home.placementsBySlot()
        outfits = await home.ownedOutfits()
        sounds = await home.ownedSounds()
        memories = await home.displayedMemories()
        plants = await home.favoritePlants()
        unreadScenes = await home.unreadStoryScenes()

        variant = await home.variant(
            themeID: themeID,
            phase: phase,
            // Hemisphere from the device's own time zone, which is the only
            // signal available without asking for location. Wrong for someone
            // travelling, and harmless when it is: it changes which season the
            // window shows, nothing else.
            isNorthernHemisphere: Self.isNorthernHemisphere(TimeZone.current),
            reduceMotion: reduceMotion
        )

        state = .loaded
    }

    /// A rough hemisphere guess from the time zone's identifier.
    ///
    /// Deliberately crude and deliberately biased toward north: the app is being
    /// built in the northern hemisphere for someone who travels, and the only
    /// consequence of getting it wrong is a window that shows the wrong season.
    static func isNorthernHemisphere(_ zone: TimeZone) -> Bool {
        let southern = [
            "Australia", "Pacific/Auckland", "America/Argentina", "America/Sao_Paulo",
            "Africa/Johannesburg", "America/Santiago", "America/Montevideo",
            "America/Lima", "America/La_Paz", "Pacific/Fiji"
        ]
        return !southern.contains { zone.identifier.hasPrefix($0) }
    }

    func candidates(for slot: DecorSlot) async -> [RewardDefinition] {
        await dependencies.manageHome.candidates(for: slot)
    }

    func place(_ rewardID: ContentID, in slotID: ContentID) async {
        refusal = await dependencies.manageHome.place(rewardID: rewardID, in: slotID)
        placements = await dependencies.manageHome.placementsBySlot()
    }

    func clear(_ slotID: ContentID) async {
        await dependencies.manageHome.clear(slotID: slotID)
        placements = await dependencies.manageHome.placementsBySlot()
    }

    func equip(_ outfitID: ContentID?) async {
        _ = await dependencies.manageHome.equip(outfitID: outfitID)
        scene = (try? await dependencies.manageHome.sceneState()) ?? scene
    }

    func selectSound(_ rewardID: ContentID?) async {
        _ = await dependencies.manageHome.selectSound(rewardID)
        scene = (try? await dependencies.manageHome.sceneState()) ?? scene
    }

    func stopSound() async {
        await dependencies.manageHome.stopSound()
    }

    func markSceneRead(_ id: ContentID) async {
        await dependencies.manageHome.markSceneRead(id)
        unreadScenes = await dependencies.manageHome.unreadStoryScenes()
    }

    func clearRefusal() {
        refusal = nil
    }
}

/// Sunnie's home (S-22).
///
/// **Placeholder presentation.** Zones are sections and slots are rows; the
/// scene canvas arrives with the art. What is not placeholder is the structure:
/// zones, constrained slots, an explicit edit mode, the outfit, the sound, the
/// travel nook, and inspection of what is displayed.
///
/// On the static fallback S-22 asks for: reduced motion pins the visual state's
/// animation intensity to zero rather than merely slowing it, so the scene is a
/// still picture rather than a gentler moving one.
struct SunnieHomeScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.sunnieTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model: SunnieHomeModel?
    @State private var editingSlot: DecorSlot?
    @State private var readingScene: StoryScene?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                switch model?.state ?? .idle {
                case .idle, .loading:
                    SunnieCard {
                        LoadingStateView(message: String(
                            localized: "home.loading",
                            defaultValue: "Tidying up…",
                            comment: "Loading state for Sunnie's home"
                        ))
                    }

                case .failed(let message):
                    ErrorStateView(message: message)

                case .loaded:
                    sceneCard
                    if !(model?.unreadScenes.isEmpty ?? true) { storyCard }
                    zonePicker
                    zoneContent
                    outfitCard
                    soundCard
                }
            }
            .padding(Space.m)
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("more.sunnieHome", bundle: .main))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(
                    (model?.isEditing ?? false)
                        ? String(
                            localized: "home.edit.done",
                            defaultValue: "Done",
                            comment: "Leaves decor edit mode"
                        )
                        : String(
                            localized: "home.edit.start",
                            defaultValue: "Arrange",
                            comment: "Enters decor edit mode"
                        )
                ) {
                    model?.isEditing.toggle()
                }
            }
        }
        .task {
            if model == nil { model = SunnieHomeModel(dependencies: dependencies) }
            await model?.load(
                phase: appState.timeContext.phase,
                themeID: appState.preferences.activeThemeID,
                reduceMotion: reduceMotion || appState.preferences.accessibility.forceReducedMotion
            )
        }
        .onDisappear {
            // The selection stays; only the sound stops. Leaving the room should
            // not forget what the user chose to have on in it.
            Task { [model] in await model?.stopSound() }
        }
        .sheet(item: $editingSlot) { slot in
            SlotEditorSheet(slot: slot, model: model)
        }
        .sheet(item: $readingScene) { scene in
            StorySceneSheet(scene: scene) {
                Task { await model?.markSceneRead(scene.id) }
            }
        }
        .alert(
            Text("home.refusal.title", bundle: .main),
            isPresented: Binding(
                get: { model?.refusal != nil },
                set: { if !$0 { model?.clearRefusal() } }
            )
        ) {
            Button(String(
                localized: "common.ok",
                defaultValue: "OK",
                comment: "Dismisses an alert"
            )) { model?.clearRefusal() }
        } message: {
            if let refusal = model?.refusal {
                Text(LocalizedStringKey(refusal.localizationKey))
            }
        }
    }

    // MARK: - Scene

    private var sceneCard: some View {
        SunnieCard {
            if let variant = model?.variant {
                SunnieAvatarView(state: variant.visualState)

                HStack(spacing: Space.xs) {
                    StatusChip(
                        text: String(
                            localized: .init(variant.phase.brandedPresentation.localizationKey)
                        ),
                        style: .neutral
                    )
                    StatusChip(
                        text: String(localized: .init(variant.season.localizationKey)),
                        style: .neutral
                    )
                    if variant.destinationID != nil {
                        StatusChip(
                            text: String(
                                localized: "home.away",
                                defaultValue: "Away",
                                comment: "Shown while a trip is on"
                            ),
                            style: .neutral
                        )
                    }
                }

                if let highlighted = variant.highlightedRewardID,
                   let reward = dependencies.manageCollection.reward(id: highlighted) {
                    Text(String(
                        format: String(
                            localized: "home.recentUnlock",
                            defaultValue: "New in here: %@",
                            comment: "Points at a recently unlocked reward"
                        ),
                        String(localized: .init(reward.displayNameKey))
                    ))
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
                }
            }
        }
    }

    // MARK: - Story

    private var storyCard: some View {
        SunnieCard {
            SectionHeader(
                title: String(
                    localized: "home.story.title",
                    defaultValue: "A short story",
                    comment: "Story scene section"
                ),
                subtitle: String(
                    localized: "home.story.subtitle",
                    defaultValue: "Whenever you feel like it.",
                    comment: "Story scenes are optional"
                )
            )
            ForEach(model?.unreadScenes ?? []) { scene in
                Button {
                    readingScene = scene
                } label: {
                    HStack {
                        Text(LocalizedStringKey(scene.titleKey))
                            .foregroundStyle(theme.color.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(theme.color.textSecondary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    // MARK: - Zones

    private var zonePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs) {
                ForEach(model?.zones ?? [], id: \.self) { zone in
                    let isSelected = model?.selectedZone == zone
                    Button {
                        model?.selectedZone = zone
                    } label: {
                        Text(LocalizedStringKey(zone.localizationKey))
                            .font(SunnieFont.caption)
                            .padding(.horizontal, Space.s)
                            .padding(.vertical, Space.xxs)
                            .background(
                                Capsule().fill(
                                    isSelected
                                        ? theme.color.accentSunnie.opacity(0.2)
                                        : theme.color.surface
                                )
                            )
                    }
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, Space.xxs)
        }
    }

    @ViewBuilder
    private var zoneContent: some View {
        switch model?.selectedZone ?? .cozyRoom {
        case .window:
            windowCard
        case .travelNook:
            slotsCard
            travelNookCard
        case .indoorJungle:
            slotsCard
            plantsCard
        default:
            slotsCard
        }
    }

    private var slotsCard: some View {
        SunnieCard {
            SectionHeader(title: String(
                localized: "home.slots.title",
                defaultValue: "What's out",
                comment: "Decor slots heading"
            ))

            ForEach(model?.slots ?? []) { slot in
                Button {
                    guard model?.isEditing == true else { return }
                    editingSlot = slot
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(LocalizedStringKey(slot.displayNameKey))
                                .font(SunnieFont.caption)
                                .foregroundStyle(theme.color.textSecondary)
                            Text(placementLabel(for: slot))
                                .font(SunnieFont.body)
                                .foregroundStyle(theme.color.textPrimary)
                        }
                        Spacer()
                        if model?.isEditing == true {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(theme.color.textSecondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.vertical, Space.xxs)
                }
                .disabled(model?.isEditing != true)
                .accessibilityElement(children: .combine)
            }

            if model?.isEditing != true {
                Text("home.slots.hint", bundle: .main)
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
    }

    private func placementLabel(for slot: DecorSlot) -> String {
        guard let reward = model?.placements[slot.id] else {
            return String(
                localized: "home.slot.empty",
                defaultValue: "Empty",
                comment: "An empty decor slot"
            )
        }
        return String(localized: .init(reward.displayNameKey))
    }

    private var windowCard: some View {
        SunnieCard {
            SectionHeader(title: String(
                localized: "home.window.title",
                defaultValue: "The window",
                comment: "Window zone heading"
            ))
            if let variant = model?.variant {
                Text(String(
                    format: String(
                        localized: "home.window.body",
                        defaultValue: "%1$@, and it looks like %2$@ out there.",
                        comment: "Describes the day cycle and season through the window"
                    ),
                    String(localized: .init(variant.phase.brandedPresentation.localizationKey)),
                    String(localized: .init(variant.season.localizationKey))
                ))
                .font(SunnieFont.body)
                .foregroundStyle(theme.color.textPrimary)
            }
            Text("home.window.note", bundle: .main)
                .font(SunnieFont.caption)
                .foregroundStyle(theme.color.textSecondary)
        }
    }

    private var travelNookCard: some View {
        SunnieCard {
            SectionHeader(title: String(
                localized: "home.nook.title",
                defaultValue: "On the board",
                comment: "Travel nook memories heading"
            ))

            if (model?.memories ?? []).isEmpty {
                Text("home.nook.empty", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
            } else {
                ForEach(model?.memories ?? []) { memory in
                    Button {
                        if let tripID = memory.tripID { router.push(.trip(tripID)) }
                    } label: {
                        HStack {
                            Text(memory.title ?? String(
                                localized: "home.nook.untitled",
                                defaultValue: "A memory",
                                comment: "A travel memory with no title"
                            ))
                            .foregroundStyle(theme.color.textPrimary)
                            Spacer()
                            Text(memory.occurredAt, format: .dateTime.month(.abbreviated).year())
                                .font(SunnieFont.caption)
                                .foregroundStyle(theme.color.textSecondary)
                        }
                    }
                    .disabled(memory.tripID == nil)
                }
            }
        }
    }

    private var plantsCard: some View {
        SunnieCard {
            SectionHeader(title: String(
                localized: "home.plants.title",
                defaultValue: "Your plants in here",
                comment: "Favourite plants heading"
            ))

            if (model?.plants ?? []).isEmpty {
                Text("home.plants.empty", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
            } else {
                ForEach(model?.plants ?? []) { plant in
                    Button {
                        router.push(.plant(plant.id))
                    } label: {
                        HStack {
                            Text(plant.name).foregroundStyle(theme.color.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(theme.color.textSecondary)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Outfit and sound

    private var outfitCard: some View {
        SunnieCard {
            SectionHeader(title: String(
                localized: "home.outfit.title",
                defaultValue: "What Sunnie's wearing",
                comment: "Outfit section"
            ))

            Picker(
                String(
                    localized: "home.outfit.picker",
                    defaultValue: "Outfit",
                    comment: "Outfit picker label"
                ),
                selection: Binding<ContentID?>(
                    // Flattened: `model?.scene.equippedOutfitID` is doubly
                    // optional, and the picker binds a single optional.
                    get: { model?.scene.equippedOutfitID ?? nil },
                    set: { newValue in Task { await model?.equip(newValue) } }
                )
            ) {
                Text("home.outfit.none", bundle: .main).tag(ContentID?.none)
                ForEach(model?.outfits ?? []) { outfit in
                    Text(LocalizedStringKey(outfit.displayNameKey))
                        .tag(ContentID?.some(outfit.id))
                }
            }
        }
    }

    private var soundCard: some View {
        SunnieCard {
            SectionHeader(title: String(
                localized: "home.sound.title",
                defaultValue: "What's playing",
                comment: "Sound section"
            ))

            Picker(
                String(
                    localized: "home.sound.picker",
                    defaultValue: "Sound",
                    comment: "Sound picker label"
                ),
                selection: Binding<ContentID?>(
                    get: { model?.scene.selectedSoundRewardID ?? nil },
                    set: { newValue in Task { await model?.selectSound(newValue) } }
                )
            ) {
                Text("home.sound.none", bundle: .main).tag(ContentID?.none)
                ForEach(model?.sounds ?? []) { sound in
                    Text(LocalizedStringKey(sound.displayNameKey))
                        .tag(ContentID?.some(sound.id))
                }
            }

            Text("home.sound.note", bundle: .main)
                .font(SunnieFont.caption)
                .foregroundStyle(theme.color.textSecondary)
        }
    }
}

/// Choosing what goes in one slot.
///
/// A list of what fits, chosen by tapping. Placement is constrained (§8), which
/// means there is no drag path to build a second accessible alternative for.
private struct SlotEditorSheet: View {
    @Environment(\.sunnieTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let slot: DecorSlot
    let model: SunnieHomeModel?

    @State private var candidates: [RewardDefinition] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(role: .destructive) {
                        Task {
                            await model?.clear(slot.id)
                            dismiss()
                        }
                    } label: {
                        Text("home.slot.clear", bundle: .main)
                    }
                }

                Section {
                    if candidates.isEmpty {
                        Text("home.slot.nothingFits", bundle: .main)
                            .font(SunnieFont.secondary)
                            .foregroundStyle(theme.color.textSecondary)
                    } else {
                        ForEach(candidates) { reward in
                            Button {
                                Task {
                                    await model?.place(reward.id, in: slot.id)
                                    dismiss()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: Space.xxs) {
                                    Text(LocalizedStringKey(reward.displayNameKey))
                                        .foregroundStyle(theme.color.textPrimary)
                                    Text(LocalizedStringKey(reward.descriptionKey))
                                        .font(SunnieFont.caption)
                                        .foregroundStyle(theme.color.textSecondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("home.slot.options", bundle: .main)
                }
            }
            .navigationTitle(Text(LocalizedStringKey(slot.displayNameKey)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(
                        localized: "common.cancel",
                        defaultValue: "Cancel",
                        comment: "Cancel"
                    )) { dismiss() }
                }
            }
            .task {
                candidates = await model?.candidates(for: slot) ?? []
            }
        }
    }
}

/// A short story, read one panel at a time.
private struct StorySceneSheet: View {
    @Environment(\.sunnieTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let scene: StoryScene
    let onRead: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    ForEach(scene.panelKeys, id: \.self) { key in
                        Text(LocalizedStringKey(key))
                            .font(SunnieFont.body)
                            .foregroundStyle(theme.color.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.m)
            }
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle(Text(LocalizedStringKey(scene.titleKey)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(
                        localized: "common.done",
                        defaultValue: "Done",
                        comment: "Dismisses a sheet"
                    )) {
                        onRead()
                        dismiss()
                    }
                }
            }
        }
    }
}
