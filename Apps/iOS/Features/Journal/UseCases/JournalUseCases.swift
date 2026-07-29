import Foundation
import SunnieShared

/// Creating, autosaving, and publishing journal entries.
///
/// The design rule throughout: never lose someone's writing. Drafts exist from
/// the first keystroke and autosave as they go; deletion is reversible; an entry
/// that fails to publish stays a draft rather than evaporating.
struct ManageJournalEntry: Sendable {

    private let repository: any JournalRepository
    private let eventPublisher: any DomainEventPublishing
    private let clock: any SunnieClock

    /// How often the editor writes while typing. Long enough not to thrash
    /// storage, short enough that an interruption costs a sentence at most.
    static let autosaveInterval: TimeInterval = 3

    init(
        repository: any JournalRepository,
        eventPublisher: any DomainEventPublishing,
        clock: any SunnieClock
    ) {
        self.repository = repository
        self.eventPublisher = eventPublisher
        self.clock = clock
    }

    /// Begins a new draft, or resumes the most recent unfinished one.
    ///
    /// Resuming rather than always starting fresh means an interrupted entry is
    /// picked back up instead of quietly accumulating as a second empty draft.
    func beginOrResumeDraft(links: JournalLinks = .none) async throws -> JournalEntry {
        let existing = try await repository.drafts()
        if let resumable = existing.first(where: { $0.hasContent }) {
            return resumable
        }
        if let empty = existing.first {
            return empty
        }

        let now = clock.now
        let draft = JournalEntry(
            isDraft: true,
            links: links,
            createdAt: now,
            modifiedAt: now
        )
        try await repository.save(draft)
        return draft
    }

    /// Autosave. Called on a timer while the editor is open.
    ///
    /// An empty draft is not written repeatedly; there is nothing to preserve and
    /// it would only churn the store.
    func autosave(_ entry: JournalEntry) async throws {
        guard entry.hasContent else { return }
        var updated = entry
        updated.modifiedAt = clock.now
        updated.isDraft = true
        try await repository.save(updated)
    }

    /// Publishes a draft.
    ///
    /// An entry with nothing in it is discarded rather than published — an empty
    /// entry in the archive is noise, not a memory.
    @discardableResult
    func publish(_ entry: JournalEntry) async throws -> JournalEntry? {
        guard entry.hasContent else {
            try await repository.softDelete(entryID: entry.id, at: clock.now)
            return nil
        }

        var published = entry
        published.isDraft = false
        published.modifiedAt = clock.now
        try await repository.save(published)

        await eventPublisher.publish(
            DomainEvent(
                type: .wellnessCheckInRecorded,
                occurredAt: published.modifiedAt,
                sourceEntityID: published.id,
                deterministicKey: "journal.published|\(published.id.uuidString)"
            )
        )

        return published
    }

    /// Removes an entry from view without destroying it.
    ///
    /// Recoverable for thirty days. `JournalEntry.isRestorable(at:)` is what the
    /// UI should ask before offering an undo.
    func delete(_ entry: JournalEntry) async throws {
        try await repository.softDelete(entryID: entry.id, at: clock.now)
    }

    func restore(_ entry: JournalEntry) async throws {
        try await repository.restore(entryID: entry.id)
    }

    /// Adds a gratitude item to an entry.
    func addGratitude(_ text: String, to entry: JournalEntry) async throws -> JournalEntry {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entry }

        var updated = entry
        updated.gratitudeItems.append(
            GratitudeItem(text: trimmed, createdAt: clock.now)
        )
        updated.modifiedAt = clock.now
        try await repository.save(updated)
        return updated
    }

    /// Housekeeping for entries past the restore window.
    ///
    /// Run at launch rather than on a schedule; the window is thirty days, so
    /// precision does not matter and a background task would be overkill.
    @discardableResult
    func purgeExpired() async throws -> Int {
        let cutoff = clock.now.addingTimeInterval(-JournalEntry.restoreWindow)
        return try await repository.purge(deletedBefore: cutoff)
    }
}
