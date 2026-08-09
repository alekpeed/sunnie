import SwiftUI
import SunnieShared

/// Keeps the existing reward collection intact while exposing the broader
/// personal-world layer from the same destination. The container reads
/// `AppState.worldContext`; it never creates its own copy of reward or travel data.
struct SunnieWorldCollectionContainer<Content: View>: View {
    @Environment(AppState.self) private var appState
    @Environment(\.sunnieTheme) private var theme

    @State private var showsWorld = false

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .safeAreaInset(edge: .top) {
                Button {
                    showsWorld = true
                } label: {
                    HStack(spacing: Space.s) {
                        Image(systemName: appState.worldContext.environment.symbol)
                            .font(.title3)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sunnie's World")
                                .font(SunnieFont.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(theme.color.textPrimary)

                            Text(worldSummary)
                                .font(.caption2)
                                .foregroundStyle(theme.color.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: Space.s)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(theme.color.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.xs)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Open Sunnie's World. \(appState.worldContext.curios.count) curios and \(appState.worldContext.memories.count) memory chapters."
                )
            }
            .sheet(isPresented: $showsWorld) {
                NavigationStack {
                    SunnieWorldScreen()
                }
            }
            .task {
                await appState.refreshCurrentContext()
            }
    }

    private var worldSummary: String {
        let curios = appState.worldContext.curios.count
        let memories = appState.worldContext.memories.count
        return "\(curios) curios · \(memories) memory chapter\(memories == 1 ? "" : "s")"
    }
}

/// User-facing home for the cross-feature world layer: permanent curios,
/// longitudinal memories, contextual language, preference recall, presentation
/// unlocks, surprises, and photo interpretation all meet here.
struct SunnieWorldScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(\.sunnieTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var inspectingCurio: CurioItem?
    @State private var inspectingMemory: MemoryChapter?
    @State private var showsPhotoIntelligence = false

    private var snapshot: SunnieWorldSnapshot { appState.worldContext }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Space.m) {
                environmentCard

                if let surprise = snapshot.surprise {
                    surpriseCard(surprise)
                }

                curioCabinet
                memoryBook

                if let languageMoment = snapshot.languageMoment {
                    languageCard(languageMoment)
                }

                if let preferenceHint = snapshot.preferenceHint {
                    preferenceCard(preferenceHint)
                }

                presentationCard
                photoIntelligenceCard
            }
            .padding(Space.m)
        }
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle("Sunnie's World")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            await appState.refreshCurrentContext()
        }
        .sheet(item: $inspectingCurio) { curio in
            WorldCurioDetailSheet(curio: curio)
        }
        .sheet(item: $inspectingMemory) { memory in
            WorldMemoryDetailSheet(memory: memory)
        }
        .sheet(isPresented: $showsPhotoIntelligence) {
            NavigationStack {
                PhotoIntelligenceScreen()
            }
        }
    }

    private var environmentCard: some View {
        SunnieCard {
            HStack(alignment: .top, spacing: Space.s) {
                Image(systemName: snapshot.environment.symbol)
                    .font(.title2)
                    .foregroundStyle(theme.color.accentSunnie)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(snapshot.environment.title)
                        .font(SunnieFont.cardTitle)
                        .foregroundStyle(theme.color.textPrimary)
                    Text(snapshot.environment.detail)
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)
                }
            }
        }
    }

    private func surpriseCard(_ surprise: WorldSurprise) -> some View {
        SunnieCard {
            Label {
                Text(surprise.title)
                    .font(SunnieFont.cardTitle)
                    .foregroundStyle(theme.color.textPrimary)
            } icon: {
                Image(systemName: surprise.symbol)
                    .foregroundStyle(theme.color.accentSunnie)
            }

            Text(surprise.detail)
                .font(SunnieFont.secondary)
                .foregroundStyle(theme.color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var curioCabinet: some View {
        SunnieCard {
            SectionHeader(
                title: "Curio Cabinet",
                subtitle: snapshot.curios.isEmpty
                    ? "Permanent keepsakes will appear here."
                    : "Every object here stays yours."
            )

            if snapshot.curios.isEmpty {
                Text("Your first keepsake will appear as your Sunnie world grows.")
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 118), spacing: Space.s)],
                    spacing: Space.s
                ) {
                    ForEach(snapshot.curios) { curio in
                        Button {
                            inspectingCurio = curio
                        } label: {
                            VStack(spacing: Space.xs) {
                                Image(systemName: curio.symbol)
                                    .font(.title2)
                                    .foregroundStyle(theme.color.accentSunnie)
                                    .accessibilityHidden(true)
                                Text(curio.title)
                                    .font(SunnieFont.caption)
                                    .foregroundStyle(theme.color.textPrimary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 86)
                            .padding(Space.xs)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(theme.color.surface)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var memoryBook: some View {
        SunnieCard {
            SectionHeader(
                title: "Memory Book",
                subtitle: snapshot.memories.isEmpty
                    ? "Trips become chapters here."
                    : "Your travel history, newest first."
            )

            if snapshot.memories.isEmpty {
                Text("When a trip begins, Sunnie can compose a chapter from the trip record without moving or duplicating it.")
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
            } else {
                ForEach(snapshot.memories.prefix(8)) { memory in
                    Button {
                        inspectingMemory = memory
                    } label: {
                        HStack(spacing: Space.s) {
                            Image(systemName: memory.symbol)
                                .foregroundStyle(theme.color.accentSunnie)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(memory.title)
                                    .font(SunnieFont.body)
                                    .foregroundStyle(theme.color.textPrimary)
                                Text(memory.subtitle ?? "Memory chapter")
                                    .font(SunnieFont.caption)
                                    .foregroundStyle(theme.color.textSecondary)
                            }

                            Spacer(minLength: Space.s)

                            Text(memory.occurredAt, format: .dateTime.month(.abbreviated).year())
                                .font(.caption2)
                                .foregroundStyle(theme.color.textSecondary)
                        }
                        .padding(.vertical, Space.xxs)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func languageCard(_ moment: LanguageMoment) -> some View {
        SunnieCard {
            SectionHeader(
                title: "Language Moment",
                subtitle: "Optional and tied to your current destination."
            )

            Text(moment.phrase)
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.color.textPrimary)
            Text(moment.translation)
                .font(SunnieFont.body)
                .foregroundStyle(theme.color.textSecondary)
            if let note = moment.note {
                Text(note)
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
    }

    private func preferenceCard(_ hint: WorldPreferenceHint) -> some View {
        SunnieCard {
            Label(hint.title, systemImage: hint.symbol)
                .font(SunnieFont.cardTitle)
                .foregroundStyle(theme.color.textPrimary)
            Text(hint.detail)
                .font(SunnieFont.secondary)
                .foregroundStyle(theme.color.textSecondary)
        }
    }

    private var presentationCard: some View {
        SunnieCard {
            SectionHeader(
                title: "Sunnie Presentation",
                subtitle: "Permanent presentation packs unlocked by progression."
            )

            ForEach(snapshot.presentationPacks) { pack in
                HStack(spacing: Space.s) {
                    Image(systemName: pack.symbol)
                        .foregroundStyle(theme.color.accentSunnie)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Space.xs) {
                            Text(pack.title)
                                .font(SunnieFont.body)
                                .foregroundStyle(theme.color.textPrimary)
                            if snapshot.activePresentationPack?.id == pack.id {
                                Text("Active")
                                    .font(.caption2)
                                    .foregroundStyle(theme.color.textSecondary)
                            }
                        }
                        Text(pack.detail)
                            .font(SunnieFont.caption)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                }
                .padding(.vertical, Space.xxs)
            }
        }
    }

    private var photoIntelligenceCard: some View {
        SunnieCard {
            SectionHeader(
                title: "Photo Intelligence",
                subtitle: "Use a photo to find the right place in Sunnie Days."
            )

            Text("Choose an image and Sunnie will classify it on-device, then suggest an existing feature to use. Nothing is changed until you choose what to do.")
                .font(SunnieFont.secondary)
                .foregroundStyle(theme.color.textSecondary)

            SunniePrimaryButton(title: "Choose a photo") {
                showsPhotoIntelligence = true
            }
        }
    }
}

private struct WorldCurioDetailSheet: View {
    @Environment(\.sunnieTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let curio: CurioItem

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    Image(systemName: curio.symbol)
                        .font(.system(size: 56))
                        .foregroundStyle(theme.color.accentSunnie)
                        .accessibilityHidden(true)

                    Text(curio.title)
                        .font(SunnieFont.sectionTitle)
                        .foregroundStyle(theme.color.textPrimary)
                    Text(curio.detail)
                        .font(SunnieFont.body)
                        .foregroundStyle(theme.color.textSecondary)

                    SunnieCard {
                        Text("Permanent keepsake")
                            .font(SunnieFont.cardTitle)
                            .foregroundStyle(theme.color.textPrimary)
                        Text("Unlocked at level \(curio.unlockedAtLevel). Once it appears, it is never removed for inactivity or missed days.")
                            .font(SunnieFont.secondary)
                            .foregroundStyle(theme.color.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.m)
            }
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle("Curio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct WorldMemoryDetailSheet: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.sunnieTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let memory: MemoryChapter

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    Label(memory.title, systemImage: memory.symbol)
                        .font(SunnieFont.sectionTitle)
                        .foregroundStyle(theme.color.textPrimary)

                    if let destination = memory.destinationName {
                        Text(destination)
                            .font(SunnieFont.body)
                            .foregroundStyle(theme.color.textSecondary)
                    }

                    Text(memory.occurredAt, format: .dateTime.weekday(.wide).month(.wide).day().year())
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)

                    Text("This chapter is composed from the original trip record. Archiving the trip does not erase the chapter.")
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)

                    if let tripID = memory.tripID {
                        SunniePrimaryButton(title: "Open original trip") {
                            dismiss()
                            router.handle(.trip(tripID))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.m)
            }
            .background(theme.color.canvas.ignoresSafeArea())
            .navigationTitle("Memory Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
