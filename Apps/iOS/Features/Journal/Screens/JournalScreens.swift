import SwiftUI
import Observation
import SunnieShared

/// Feature model for the journal.
@MainActor
@Observable
final class JournalModel {

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(entries: [JournalEntry], drafts: [JournalEntry])
        case failed(String)
    }

    private(set) var state: LoadState = .idle
    private(set) var searchResults: [JournalEntry] = []
    /// The entry just deleted, so an undo can be offered while it lasts.
    private(set) var recentlyDeleted: JournalEntry?

    var searchQuery = ""

    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    func load() async {
        if case .loaded = state {} else {
            state = .loading
        }

        do {
            async let entries = dependencies.journalRepository.entries(limit: 100, offset: 0)
            async let drafts = dependencies.journalRepository.drafts()
            state = .loaded(
                entries: try await entries,
                drafts: try await drafts.filter(\.hasContent)
            )
        } catch {
            state = .failed(String(
                localized: "journal.error.load",
                defaultValue: "I couldn't open your journal just now. Nothing has been lost, and you can try again.",
                comment: "Shown when the journal cannot be loaded"
            ))
        }
    }

    func search() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        searchResults = (try? await dependencies.journalRepository
            .entries(matching: query, limit: 50)) ?? []
    }

    func newDraft() async -> JournalEntry? {
        try? await dependencies.manageJournalEntry.beginOrResumeDraft()
    }

    /// Deletion is reversible. The entry is kept for thirty days and an undo is
    /// offered immediately.
    func delete(_ entry: JournalEntry) async {
        do {
            try await dependencies.manageJournalEntry.delete(entry)
            recentlyDeleted = entry
            await load()
        } catch {
            state = .failed(String(
                localized: "journal.error.delete",
                defaultValue: "That didn't work just now. Your entry is still here.",
                comment: "Shown when deleting a journal entry fails"
            ))
        }
    }

    func undoDelete() async {
        guard let entry = recentlyDeleted else { return }
        try? await dependencies.manageJournalEntry.restore(entry)
        recentlyDeleted = nil
        await load()
    }

    func dismissUndo() {
        recentlyDeleted = nil
    }
}

/// The journal list.
///
/// **Placeholder presentation.** Entries, drafts, search, and reversible delete
/// all work. Calendar, tags, and export are later.
struct JournalScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.sunnieTheme) private var theme

    @State private var model: JournalModel?
    @State private var editingEntry: JournalEntry?

    var body: some View {
        List {
            if let deleted = model?.recentlyDeleted {
                undoSection(deleted)
            }

            if !(model?.searchQuery.isEmpty ?? true) {
                searchSection
            } else {
                switch model?.state ?? .idle {
                case .idle, .loading:
                    LoadingStateView(message: String(
                        localized: "journal.loading",
                        defaultValue: "Opening your journal…",
                        comment: "Loading state"
                    ))

                case .failed(let message):
                    Text(message)
                        .font(SunnieFont.secondary)
                        .foregroundStyle(theme.color.textSecondary)

                case .loaded(let entries, let drafts):
                    if !drafts.isEmpty {
                        Section {
                            ForEach(drafts) { entry in
                                entryRow(entry, isDraft: true)
                            }
                        } header: {
                            Text("journal.section.drafts", bundle: .main)
                        } footer: {
                            Text("journal.section.drafts.footer", bundle: .main)
                        }
                    }

                    Section {
                        if entries.isEmpty {
                            EmptyStateView(
                                title: String(
                                    localized: "journal.empty.title",
                                    defaultValue: "Nothing written yet",
                                    comment: "Empty journal"
                                ),
                                message: String(
                                    localized: "journal.empty.message",
                                    defaultValue: "Whenever you'd like to write something down, it'll be here.",
                                    comment: "Empty journal body"
                                ),
                                visualState: SunnieVisualState(
                                    expression: .thinking, pose: .reading, presence: .medium
                                )
                            )
                        } else {
                            ForEach(entries) { entry in
                                entryRow(entry, isDraft: false)
                            }
                        }
                    } header: {
                        Text("journal.section.entries", bundle: .main)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.color.canvas.ignoresSafeArea())
        .navigationTitle(Text("more.journal", bundle: .main))
        .searchable(text: searchBinding)
        .task(id: model?.searchQuery) { await model?.search() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { editingEntry = await model?.newDraft() }
                } label: {
                    Label(
                        String(localized: "journal.new", defaultValue: "New entry", comment: "New entry"),
                        systemImage: "square.and.pencil"
                    )
                }
            }
        }
        .task {
            if model == nil {
                model = JournalModel(dependencies: dependencies)
            }
            await model?.load()
        }
        .sheet(item: $editingEntry) { entry in
            JournalEditorScreen(entry: entry) {
                Task { await model?.load() }
            }
        }
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { model?.searchQuery ?? "" },
            set: { model?.searchQuery = $0 }
        )
    }

    private var searchSection: some View {
        Section {
            let results = model?.searchResults ?? []
            if results.isEmpty {
                Text("journal.search.none", bundle: .main)
                    .font(SunnieFont.secondary)
                    .foregroundStyle(theme.color.textSecondary)
            } else {
                ForEach(results) { entry in
                    entryRow(entry, isDraft: entry.isDraft)
                }
            }
        }
    }

    private func undoSection(_ entry: JournalEntry) -> some View {
        Section {
            HStack {
                // States the window rather than implying the entry is gone.
                // ADR-033: a thirty-day undo the user is never told about is its
                // own quiet form of a silent delete.
                Text(
                    "journal.deleted \(JournalEntry.restoreWindowDays)",
                    bundle: .main
                )
                .font(SunnieFont.secondary)
                Spacer()
                Button(String(
                    localized: "journal.undo",
                    defaultValue: "Undo",
                    comment: "Restores a deleted entry"
                )) {
                    Task { await model?.undoDelete() }
                }
            }
        }
    }

    private func entryRow(_ entry: JournalEntry, isDraft: Bool) -> some View {
        Button {
            editingEntry = entry
        } label: {
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack {
                    Text(entry.title ?? previewTitle(entry))
                        .font(SunnieFont.body)
                        .foregroundStyle(theme.color.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if isDraft {
                        StatusChip(
                            text: String(
                                localized: "journal.draft",
                                defaultValue: "Draft",
                                comment: "Marks an unfinished entry"
                            ),
                            style: .neutral
                        )
                    }
                }
                Text(entry.modifiedAt, format: .dateTime.day().month().year())
                    .font(SunnieFont.caption)
                    .foregroundStyle(theme.color.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await model?.delete(entry) }
            } label: {
                Label(
                    String(localized: "common.delete", defaultValue: "Delete", comment: "Delete"),
                    systemImage: "trash"
                )
            }
        }
    }

    /// First line of the body, for entries with no title.
    private func previewTitle(_ entry: JournalEntry) -> String {
        let firstLine = entry.body
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty
            ? String(localized: "journal.untitled", defaultValue: "Untitled", comment: "Untitled entry")
            : String(trimmed.prefix(60))
    }
}

/// The journal editor.
///
/// **Placeholder presentation.** The behaviour that matters is the autosave:
/// text is written every few seconds and again on dismiss, so an interruption
/// costs a sentence at most. Nothing here can lose what someone wrote.
struct JournalEditorScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sunnieTheme) private var theme

    let entry: JournalEntry
    let onFinish: () -> Void

    @State private var title: String
    @State private var body_: String
    @State private var gratitude: [GratitudeItem]
    @State private var newGratitude = ""
    @State private var autosaveTask: Task<Void, Never>?

    init(entry: JournalEntry, onFinish: @escaping () -> Void) {
        self.entry = entry
        self.onFinish = onFinish
        _title = State(initialValue: entry.title ?? "")
        _body_ = State(initialValue: entry.body)
        _gratitude = State(initialValue: entry.gratitudeItems)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        String(localized: "journal.title", defaultValue: "Title (optional)", comment: "Title field"),
                        text: $title
                    )
                    TextField(
                        String(localized: "journal.body", defaultValue: "Write anything…", comment: "Body field"),
                        text: $body_,
                        axis: .vertical
                    )
                    .lineLimit(8...30)
                }

                Section {
                    ForEach(gratitude) { item in
                        Text(item.text)
                            .font(SunnieFont.body)
                    }
                    HStack {
                        TextField(
                            String(
                                localized: "journal.gratitude.add",
                                defaultValue: "Something you're glad about",
                                comment: "Gratitude field"
                            ),
                            text: $newGratitude
                        )
                        Button {
                            addGratitude()
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .disabled(newGratitude.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel(Text("journal.gratitude.addAction", bundle: .main))
                    }
                } header: {
                    Text("journal.section.gratitude", bundle: .main)
                }

                Section {
                    AttachmentsSection(owner: .journalEntry(entry.id))
                } header: {
                    Text("journal.section.attachments", bundle: .main)
                } footer: {
                    // Says plainly that attaching is optional, so an entry
                    // without one never reads as unfinished.
                    Text("journal.section.attachments.footer", bundle: .main)
                }
            }
            .navigationTitle(Text("journal.editor.title", bundle: .main))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Not "cancel": the draft is already saved, so leaving loses
                    // nothing and the label should not imply otherwise.
                    Button(String(
                        localized: "journal.close",
                        defaultValue: "Close",
                        comment: "Leaves the editor, keeping the draft"
                    )) {
                        Task { await saveDraft(); finish() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(
                        localized: "journal.done",
                        defaultValue: "Done",
                        comment: "Publishes the entry"
                    )) {
                        Task { await publish(); finish() }
                    }
                }
            }
            .task {
                startAutosave()
            }
            .onDisappear {
                autosaveTask?.cancel()
                Task { await saveDraft() }
            }
        }
    }

    private var composed: JournalEntry {
        var updated = entry
        updated.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? nil : title
        updated.body = body_
        updated.gratitudeItems = gratitude
        return updated
    }

    /// Writes every few seconds while the editor is open.
    private func startAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(ManageJournalEntry.autosaveInterval * 1_000_000_000)
                )
                guard !Task.isCancelled else { return }
                await saveDraft()
            }
        }
    }

    private func saveDraft() async {
        try? await dependencies.manageJournalEntry.autosave(composed)
    }

    private func publish() async {
        _ = try? await dependencies.manageJournalEntry.publish(composed)
    }

    private func addGratitude() {
        let trimmed = newGratitude.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        gratitude.append(GratitudeItem(text: trimmed, createdAt: Date()))
        newGratitude = ""
    }

    private func finish() {
        autosaveTask?.cancel()
        onFinish()
        dismiss()
    }
}
