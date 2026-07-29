import Foundation
import SwiftData
import SunnieShared

/// Where photo and voice-note bytes actually live.
///
/// Files sit outside the database, in Application Support, addressed by an opaque
/// token. Nothing outside this type ever sees a path: a container URL changes
/// between installs and devices, so a stored absolute path would break silently
/// and a synced one would be meaningless on the other end.
///
/// Excluded from iCloud *document* backup — media sync is a Phase 11 decision
/// with its own policy, and quietly uploading photos before that decision is made
/// would be the wrong default.
struct MediaFileStore: Sendable {

    private let directory: URL
    private let log = SunnieLog(category: .persistence)

    init(directoryName: String = "SunnieMedia") {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())

        self.directory = base.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// For tests, which need an isolated directory they can delete afterwards.
    init(directory: URL) {
        self.directory = directory
    }

    func makeToken(for kind: MediaKind) -> String {
        let ext = kind == .photo ? "jpg" : "m4a"
        return "\(UUID().uuidString).\(ext)"
    }

    func write(_ data: Data, token: String) throws {
        try ensureDirectory()
        do {
            try data.write(to: url(for: token), options: .atomic)
        } catch {
            log.error("Writing a media file failed.")
            throw DomainError.persistenceFailed(operation: "writeMedia")
        }
    }

    func read(token: String) -> Data? {
        try? Data(contentsOf: url(for: token))
    }

    func delete(token: String) {
        try? FileManager.default.removeItem(at: url(for: token))
    }

    func exists(token: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: token).path)
    }

    /// Tokens present on disk. Used to find files whose record has gone.
    func allTokens() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    private func url(for token: String) -> URL {
        // Tokens are generated here and are always plain UUID filenames, but a
        // path component is stripped anyway so a token from elsewhere can never
        // escape the directory.
        directory.appendingPathComponent((token as NSString).lastPathComponent)
    }

    private func ensureDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        var directoryURL = directory
        try FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directoryURL.setResourceValues(values)
    }
}

/// Photo and voice-note records, paired with their files.
///
/// Record and file are written together and deleted together. When they diverge
/// anyway — an interrupted write, a restore from backup — `deleteOrphans` is the
/// repair, because media outliving its owner is the normal way storage silently
/// fills up.
@ModelActor
actor SwiftDataMediaRepository: MediaRepository {

    /// Defaults to the real Application Support directory. `@ModelActor`
    /// generates `init(modelContainer:)`, so there is nowhere to inject this at
    /// construction — tests point it at a temporary directory instead, which
    /// keeps them from leaving files on the machine.
    private var injectedFileStore: MediaFileStore?
    private var fileStore: MediaFileStore { injectedFileStore ?? MediaFileStore() }
    private var log: SunnieLog { SunnieLog(category: .persistence) }

    func useFileStore(_ store: MediaFileStore) {
        injectedFileStore = store
    }

    func save(_ attachment: MediaAttachment, data: Data) async throws -> MediaAttachment {
        // File first: a file with no record is recoverable garbage, whereas a
        // record pointing at nothing shows the user a broken photo.
        try fileStore.write(data, token: attachment.localToken)

        do {
            let model = ModelMapping.model(attachment)
            modelContext.insert(model)
            try modelContext.save()
            return attachment
        } catch {
            modelContext.rollback()
            fileStore.delete(token: attachment.localToken)
            log.error("Saving a media attachment failed.")
            throw DomainError.persistenceFailed(operation: "saveMediaAttachment")
        }
    }

    func attachment(id: UUID) async throws -> MediaAttachment? {
        try fetch(id: id).map { ModelMapping.domain($0) }
    }

    func attachments(for owner: MediaOwner) async throws -> [MediaAttachment] {
        let kind = MediaOwnerKind(owner: owner).rawValue
        let ownerID = MediaOwnerKind.id(of: owner)

        let descriptor = FetchDescriptor<SDMediaAttachment>(
            predicate: #Predicate<SDMediaAttachment> {
                $0.ownerKindRaw == kind && $0.ownerID == ownerID
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
    }

    func data(for attachmentID: UUID) async throws -> Data? {
        guard let model = try fetch(id: attachmentID) else { return nil }
        return fileStore.read(token: model.localToken)
    }

    func delete(attachmentID: UUID) async throws {
        guard let model = try fetch(id: attachmentID) else { return }
        let token = model.localToken
        let thumbnail = model.thumbnailToken

        do {
            modelContext.delete(model)
            try modelContext.save()
            fileStore.delete(token: token)
            if let thumbnail { fileStore.delete(token: thumbnail) }
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "deleteMediaAttachment")
        }
    }

    /// Removes files with no record, and records whose owner is gone.
    ///
    /// Owner kinds whose feature does not exist yet are left alone — a trip
    /// attachment must not be swept up merely because trips are not built.
    @discardableResult
    func deleteOrphans() async throws -> Int {
        var removed = 0

        let attachments = try modelContext.fetch(FetchDescriptor<SDMediaAttachment>())
        var liveTokens = Set<String>()

        for attachment in attachments {
            let kind = MediaOwnerKind(rawValue: attachment.ownerKindRaw)
            let ownerExists: Bool

            switch kind {
            case .journalEntry:
                ownerExists = try recordExists(SDJournalEntry.self, id: attachment.ownerID)
            case .checkIn:
                ownerExists = try recordExists(SDWellnessCheckIn.self, id: attachment.ownerID)
            case .plant:
                ownerExists = try recordExists(SDPlant.self, id: attachment.ownerID)
            case .trip, .meal, .none:
                // Not implemented yet; leaving these alone is the safe default.
                ownerExists = true
            }

            if ownerExists {
                liveTokens.insert(attachment.localToken)
                if let thumbnail = attachment.thumbnailToken {
                    liveTokens.insert(thumbnail)
                }
            } else {
                fileStore.delete(token: attachment.localToken)
                if let thumbnail = attachment.thumbnailToken {
                    fileStore.delete(token: thumbnail)
                }
                modelContext.delete(attachment)
                removed += 1
            }
        }

        // Files with no record at all, e.g. an interrupted write.
        for token in fileStore.allTokens() where !liveTokens.contains(token) {
            let stillReferenced = attachments.contains {
                $0.localToken == token || $0.thumbnailToken == token
            }
            if !stillReferenced {
                fileStore.delete(token: token)
                removed += 1
            }
        }

        if removed > 0 {
            try modelContext.save()
            log.info("Removed \(removed) orphaned media items.")
        }
        return removed
    }

    private func fetch(id: UUID) throws -> SDMediaAttachment? {
        var descriptor = FetchDescriptor<SDMediaAttachment>(
            predicate: #Predicate<SDMediaAttachment> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Fetching and filtering keeps this generic over the owner types.
    ///
    /// A predicate cannot be written generically here, and orphan sweeps are rare
    /// and off the interactive path, so the cost is acceptable.
    private func recordExists<T: PersistentModel & HasIdentifier>(
        _ type: T.Type, id: UUID
    ) throws -> Bool {
        try modelContext.fetch(FetchDescriptor<T>()).contains { $0.identifier == id }
    }
}

/// Lets the orphan sweep look up "does a record with this id exist" generically.
protocol HasIdentifier {
    var identifier: UUID { get }
}

extension SDJournalEntry: HasIdentifier {
    var identifier: UUID { id }
}

extension SDWellnessCheckIn: HasIdentifier {
    var identifier: UUID { id }
}

extension SDPlant: HasIdentifier {
    var identifier: UUID { id }
}

/// Scheduled reminder storage.
@ModelActor
actor SwiftDataReminderRepository: ReminderRepository {

    func scheduled(category: ReminderCategory) async throws -> [ScheduledReminderRecord] {
        let raw = category.rawValue
        let descriptor = FetchDescriptor<SDScheduledReminder>(
            predicate: #Predicate<SDScheduledReminder> {
                $0.categoryRaw == raw && $0.isEnabled
            },
            sortBy: [SortDescriptor(\.scheduledAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor).compactMap { ModelMapping.domain($0) }
    }

    func record(_ reminder: ScheduledReminderRecord) async throws {
        do {
            if let existing = try fetch(id: reminder.id) {
                ModelMapping.apply(reminder, to: existing)
            } else {
                let model = SDScheduledReminder()
                ModelMapping.apply(reminder, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "recordReminder")
        }
    }

    func markResponse(
        reminderID: UUID,
        response: ReminderResponse,
        at date: Date
    ) async throws {
        guard let model = try fetch(id: reminderID) else { return }
        do {
            model.responseRaw = response.rawValue
            model.respondedAt = date
            // A completed or skipped reminder is finished; leaving it enabled
            // would let it be re-offered for a task that is already done.
            if response == .completed || response == .skippedForToday {
                model.isEnabled = false
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "markReminderResponse")
        }
    }

    func firedToday(
        sourceEntityID: UUID,
        category: ReminderCategory,
        now: Date
    ) async throws -> [Date] {
        let raw = category.rawValue
        let descriptor = FetchDescriptor<SDScheduledReminder>(
            predicate: #Predicate<SDScheduledReminder> {
                $0.categoryRaw == raw && $0.sourceEntityID == sourceEntityID
            }
        )
        let calendar = Calendar.current
        return try modelContext.fetch(descriptor)
            .map(\.scheduledAt)
            .filter { calendar.isDate($0, inSameDayAs: now) && $0 <= now }
    }

    func cancelAll(sourceEntityID: UUID) async throws {
        let descriptor = FetchDescriptor<SDScheduledReminder>(
            predicate: #Predicate<SDScheduledReminder> {
                $0.sourceEntityID == sourceEntityID && $0.isEnabled
            }
        )
        do {
            for model in try modelContext.fetch(descriptor) {
                model.isEnabled = false
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "cancelReminders")
        }
    }

    private func fetch(id: UUID) throws -> SDScheduledReminder? {
        var descriptor = FetchDescriptor<SDScheduledReminder>(
            predicate: #Predicate<SDScheduledReminder> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
