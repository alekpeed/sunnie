import Foundation
import SwiftData
import SunnieShared

/// Check-in and practice-session storage.
///
/// Same check-then-insert discipline as care events, for the same reason: a
/// check-in saved on one device and redelivered must not become two entries in
/// the history (ADR-011).
@ModelActor
actor SwiftDataWellnessRepository: WellnessRepository {

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    func save(_ checkIn: WellnessCheckIn) async throws -> SaveOutcome<WellnessCheckIn> {
        if let existing = try fetchCheckIn(actionKey: checkIn.actionKey.rawValue) {
            return .alreadyExisted(ModelMapping.domain(existing))
        }

        do {
            let model = ModelMapping.model(checkIn)
            modelContext.insert(model)
            try modelContext.save()
            return .created(ModelMapping.domain(model))
        } catch {
            modelContext.rollback()
            // Never log the note itself — journal and check-in text stay out of
            // logs entirely (PROJECT_STRUCTURE_AND_CODING_STANDARDS.md §7).
            log.error("Saving a check-in failed.")
            throw DomainError.persistenceFailed(operation: "saveWellnessCheckIn")
        }
    }

    func checkIn(actionKey: ActionKey) async throws -> WellnessCheckIn? {
        try fetchCheckIn(actionKey: actionKey.rawValue).map { ModelMapping.domain($0) }
    }

    func checkIn(id: UUID) async throws -> WellnessCheckIn? {
        var descriptor = FetchDescriptor<SDWellnessCheckIn>(
            predicate: #Predicate<SDWellnessCheckIn> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { ModelMapping.domain($0) }
    }

    func checkIns(from: Date, to: Date, limit: Int) async throws -> [WellnessCheckIn] {
        var descriptor = FetchDescriptor<SDWellnessCheckIn>(
            predicate: #Predicate<SDWellnessCheckIn> {
                $0.recordedAt >= from && $0.recordedAt <= to
            },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "wellnessCheckIns")
        }
    }

    func mostRecentCheckIn() async throws -> WellnessCheckIn? {
        var descriptor = FetchDescriptor<SDWellnessCheckIn>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { ModelMapping.domain($0) }
    }

    func save(_ session: WellnessSession) async throws -> SaveOutcome<WellnessSession> {
        if let existing = try fetchSession(id: session.id) {
            return .alreadyExisted(ModelMapping.domain(existing))
        }

        do {
            let model = SDWellnessSession()
            ModelMapping.apply(session, to: model)
            modelContext.insert(model)
            try modelContext.save()
            return .created(session)
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveWellnessSession")
        }
    }

    func session(id: UUID) async throws -> WellnessSession? {
        try fetchSession(id: id).map { ModelMapping.domain($0) }
    }

    /// Updates a session in place.
    ///
    /// Sessions are written when a practice *starts*, so a session interrupted by
    /// the app being killed still exists — it simply never gets an end date.
    /// That is why this is an update rather than a save-at-the-end.
    func update(_ session: WellnessSession) async throws {
        guard let model = try fetchSession(id: session.id) else {
            throw DomainError.notFound(entity: "WellnessSession", id: session.id)
        }
        do {
            ModelMapping.apply(session, to: model)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "updateWellnessSession")
        }
    }

    func sessions(from: Date, to: Date, limit: Int) async throws -> [WellnessSession] {
        var descriptor = FetchDescriptor<SDWellnessSession>(
            predicate: #Predicate<SDWellnessSession> {
                $0.startedAt >= from && $0.startedAt <= to
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "wellnessSessions")
        }
    }

    private func fetchCheckIn(actionKey: String) throws -> SDWellnessCheckIn? {
        var descriptor = FetchDescriptor<SDWellnessCheckIn>(
            predicate: #Predicate<SDWellnessCheckIn> { $0.actionKey == actionKey }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchSession(id: UUID) throws -> SDWellnessSession? {
        var descriptor = FetchDescriptor<SDWellnessSession>(
            predicate: #Predicate<SDWellnessSession> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

/// Journal storage.
///
/// Deletion is soft everywhere except `purge`. Writing is easy to regret, so an
/// entry stays restorable for thirty days before anything is destroyed
/// (WELLNESS_JOURNAL_AND_CALM.md §6).
@ModelActor
actor SwiftDataJournalRepository: JournalRepository {

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    func save(_ entry: JournalEntry) async throws {
        do {
            if let existing = try fetchEntry(id: entry.id) {
                ModelMapping.apply(entry, to: existing)
            } else {
                let model = SDJournalEntry()
                ModelMapping.apply(entry, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            log.error("Saving a journal entry failed.")
            throw DomainError.persistenceFailed(operation: "saveJournalEntry")
        }
    }

    func entry(id: UUID) async throws -> JournalEntry? {
        try fetchEntry(id: id).map { ModelMapping.domain($0) }
    }

    func entries(limit: Int, offset: Int) async throws -> [JournalEntry] {
        var descriptor = FetchDescriptor<SDJournalEntry>(
            predicate: #Predicate<SDJournalEntry> { !$0.isDraft && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)
        descriptor.fetchOffset = max(0, offset)
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "journalEntries")
        }
    }

    func drafts() async throws -> [JournalEntry] {
        let descriptor = FetchDescriptor<SDJournalEntry>(
            predicate: #Predicate<SDJournalEntry> { $0.isDraft && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
    }

    func deletedEntries() async throws -> [JournalEntry] {
        let descriptor = FetchDescriptor<SDJournalEntry>(
            predicate: #Predicate<SDJournalEntry> { $0.deletedAt != nil },
            sortBy: [SortDescriptor(\.deletedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
    }

    /// Substring search over title and body.
    ///
    /// Deliberately simple and local. Journal text never leaves the device and is
    /// never indexed by anything external (WELLNESS_JOURNAL_AND_CALM.md §13).
    func entries(matching query: String, limit: Int) async throws -> [JournalEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var descriptor = FetchDescriptor<SDJournalEntry>(
            predicate: #Predicate<SDJournalEntry> {
                $0.deletedAt == nil
                    && ($0.body.localizedStandardContains(trimmed)
                        || ($0.title?.localizedStandardContains(trimmed) ?? false))
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(0, limit)
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "searchJournalEntries")
        }
    }

    func entries(withTag tag: String, limit: Int) async throws -> [JournalEntry] {
        // Tags are a stored array, which SwiftData predicates handle poorly, so
        // this filters after fetching. Fine at journal scale; revisit if the
        // archive grows into the thousands.
        let descriptor = FetchDescriptor<SDJournalEntry>(
            predicate: #Predicate<SDJournalEntry> { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let all = try modelContext.fetch(descriptor)
        return all
            .filter { $0.tags.contains(tag) }
            .prefix(max(0, limit))
            .map { ModelMapping.domain($0) }
    }

    func softDelete(entryID: UUID, at date: Date) async throws {
        guard let model = try fetchEntry(id: entryID) else { return }
        do {
            model.deletedAt = date
            model.modifiedAt = date
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "deleteJournalEntry")
        }
    }

    func restore(entryID: UUID) async throws {
        guard let model = try fetchEntry(id: entryID) else {
            throw DomainError.notFound(entity: "JournalEntry", id: entryID)
        }
        do {
            model.deletedAt = nil
            model.modifiedAt = Date()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "restoreJournalEntry")
        }
    }

    /// The only call that destroys anything.
    ///
    /// Expected to run against entries past the restore window, not on user
    /// request — "delete" in the UI means `softDelete`.
    @discardableResult
    func purge(deletedBefore cutoff: Date) async throws -> Int {
        let descriptor = FetchDescriptor<SDJournalEntry>(
            predicate: #Predicate<SDJournalEntry> {
                if let deletedAt = $0.deletedAt { deletedAt < cutoff } else { false }
            }
        )
        do {
            let doomed = try modelContext.fetch(descriptor)
            for model in doomed {
                modelContext.delete(model)
            }
            try modelContext.save()
            if !doomed.isEmpty {
                log.info("Purged \(doomed.count) journal entries past the restore window.")
            }
            return doomed.count
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "purgeJournalEntries")
        }
    }

    private func fetchEntry(id: UUID) throws -> SDJournalEntry? {
        var descriptor = FetchDescriptor<SDJournalEntry>(
            predicate: #Predicate<SDJournalEntry> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
