import Foundation
import SwiftData
import SunnieShared

/// Hydration logs.
///
/// Same `@ModelActor` discipline as every other repository: check-then-insert
/// inside the serialized context rather than a uniqueness attribute (ADR-011).
@ModelActor
actor SwiftDataHydrationRepository: HydrationRepository {

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    func save(_ entry: HydrationLog) async throws -> SaveOutcome<HydrationLog> {
        let key = entry.actionKey.rawValue
        var descriptor = FetchDescriptor<SDHydrationLog>(
            predicate: #Predicate<SDHydrationLog> { $0.actionKey == key }
        )
        descriptor.fetchLimit = 1

        do {
            if let existing = try modelContext.fetch(descriptor).first {
                // A double tap on the wrist and a redelivered transfer resolve
                // here. Neither is an error; both are one glass of water.
                return .alreadyExisted(ModelMapping.domain(existing))
            }
            let model = SDHydrationLog()
            ModelMapping.apply(entry, to: model)
            modelContext.insert(model)
            try modelContext.save()
            return .created(ModelMapping.domain(model))
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveHydrationLog")
        }
    }

    func logs(from start: Date, to end: Date) async throws -> [HydrationLog] {
        let descriptor = FetchDescriptor<SDHydrationLog>(
            predicate: #Predicate<SDHydrationLog> {
                $0.loggedAt >= start && $0.loggedAt < end
            },
            sortBy: [SortDescriptor(\.loggedAt, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "hydrationLogs")
        }
    }

    func unwrittenLogs(limit: Int) async throws -> [HydrationLog] {
        // `== ""` rather than `.isEmpty`, which is not the stylistic choice it
        // looks like.
        //
        // The column is a non-empty-by-convention String — empty until the
        // sample is written, never null (SunnieSchemaV8) — so the two are the
        // same question in Swift. They are not the same question in SQL, where
        // `isEmpty` is a Swift property with no column operator behind it. This
        // returned no rows for a store that had them: the fetch succeeded and
        // matched nothing, which is worse than throwing, because a queue that
        // is silently always empty looks exactly like a queue with nothing in
        // it. Water logged while Health was off would never have been caught up
        // once it was turned on.
        //
        // Third of this kind after the journal's `??` and travel's `!=` on a
        // null column. The pattern is the same each time: valid Swift, obvious
        // reading, no equivalent on the other side of the translation.
        var descriptor = FetchDescriptor<SDHydrationLog>(
            predicate: #Predicate<SDHydrationLog> { $0.healthKitSampleID == "" },
            sortBy: [SortDescriptor(\.loggedAt, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "unwrittenHydrationLogs")
        }
    }

    /// Records that an entry reached Health.
    ///
    /// Write-once: an entry that already has a sample identifier is left alone,
    /// so a catch-up pass racing a live write cannot overwrite the real sample
    /// with a second one.
    func markWritten(id: UUID, sampleID: String) async throws {
        var descriptor = FetchDescriptor<SDHydrationLog>(
            predicate: #Predicate<SDHydrationLog> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            guard let model = try modelContext.fetch(descriptor).first,
                  model.healthKitSampleID.isEmpty
            else { return }
            model.healthKitSampleID = sampleID
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "markHydrationWritten")
        }
    }
}
