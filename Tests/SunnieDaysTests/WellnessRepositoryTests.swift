import Foundation
import SwiftData
import Testing
import SunnieShared
@testable import SunnieDays

@Suite("Wellness and journal storage")
struct WellnessRepositoryTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.make(storage: .inMemory)
    }

    private func checkIn(
        at date: Date,
        mood: WellnessScaleValue? = .three,
        note: String? = nil
    ) -> WellnessCheckIn {
        WellnessCheckIn(
            recordedAt: date,
            timeZoneID: "UTC",
            mood: mood,
            note: note,
            sourceDeviceID: DeviceID(rawValue: "phone"),
            actionKey: ActionKeyFactory.wellnessCheckIn(recordedAt: date),
            createdAt: date
        )
    }

    // MARK: - Check-ins

    @Test("A check-in round-trips with every dimension")
    func checkInRoundTrips() async throws {
        let repository = SwiftDataWellnessRepository(modelContainer: try makeContainer())
        let now = Date()

        var entry = checkIn(at: now, note: "Long flight.")
        entry.energy = .two
        entry.stress = .five
        entry.sleepQuality = .one

        _ = try await repository.save(entry)
        let loaded = try #require(try await repository.checkIn(id: entry.id))

        #expect(loaded.mood == .three)
        #expect(loaded.energy == .two)
        #expect(loaded.stress == .five)
        #expect(loaded.sleepQuality == .one)
        #expect(loaded.note == "Long flight.")
    }

    @Test("An unanswered dimension stays unanswered, not zero")
    func unansweredDimensionsSurvive() async throws {
        let repository = SwiftDataWellnessRepository(modelContainer: try makeContainer())
        let now = Date()

        _ = try await repository.save(checkIn(at: now, mood: .four))
        let loaded = try #require(try await repository.mostRecentCheckIn())

        #expect(loaded.mood == .four)
        // Inventing an answer the user never gave would be worse than a gap.
        #expect(loaded.energy == nil)
        #expect(loaded.stress == nil)
        #expect(loaded.sleepQuality == nil)
    }

    @Test("The same check-in saved twice stores once")
    func checkInsAreIdempotent() async throws {
        let repository = SwiftDataWellnessRepository(modelContainer: try makeContainer())
        let entry = checkIn(at: Date())

        let first = try await repository.save(entry)
        let second = try await repository.save(entry)

        #expect(first.wasCreated)
        #expect(!second.wasCreated)
        #expect(second.value.id == first.value.id)
    }

    @Test("Concurrent saves of one check-in store once")
    func concurrentCheckInSavesStoreOnce() async throws {
        let repository = SwiftDataWellnessRepository(modelContainer: try makeContainer())
        let entry = checkIn(at: Date())

        async let a = repository.save(entry)
        async let b = repository.save(entry)
        let outcomes = try await [a, b]

        #expect(outcomes.filter(\.wasCreated).count == 1)
    }

    @Test("Check-ins come back newest first, within the window")
    func checkInsAreWindowedAndOrdered() async throws {
        let repository = SwiftDataWellnessRepository(modelContainer: try makeContainer())
        let now = Date()

        for day in 0..<5 {
            _ = try await repository.save(
                checkIn(at: now.addingTimeInterval(-Double(day) * 86_400))
            )
        }

        let recent = try await repository.checkIns(
            from: now.addingTimeInterval(-2.5 * 86_400), to: now, limit: 50
        )

        #expect(recent.count == 3)
        #expect(recent[0].recordedAt > recent[1].recordedAt)
    }

    // MARK: - Sessions

    @Test("A session is recorded at the start and updated at the end")
    func sessionLifecycle() async throws {
        let repository = SwiftDataWellnessRepository(modelContainer: try makeContainer())
        let started = Date()
        let id = UUID()

        var session = WellnessSession(
            id: id,
            type: .breathing,
            practiceID: "sunnie.breathing.equal",
            startedAt: started,
            plannedDuration: 300,
            sourceDeviceID: DeviceID(rawValue: "phone"),
            actionKey: ActionKeyFactory.wellnessSession(sessionID: id)
        )
        _ = try await repository.save(session)

        // A session killed here still exists, with no end date.
        let midway = try #require(try await repository.session(id: id))
        #expect(!midway.isFinished)

        session.endedAt = started.addingTimeInterval(180)
        session.completion = .endedEarly
        try await repository.update(session)

        let finished = try #require(try await repository.session(id: id))
        #expect(finished.isFinished)
        #expect(finished.completion == .endedEarly)
        #expect(finished.actualDuration == 180)
    }

    @Test("Updating a session that does not exist reports not-found")
    func updatingMissingSessionThrows() async throws {
        let repository = SwiftDataWellnessRepository(modelContainer: try makeContainer())
        let session = WellnessSession(
            type: .meditation,
            startedAt: Date(),
            plannedDuration: 60,
            sourceDeviceID: DeviceID(rawValue: "phone"),
            actionKey: ActionKey(rawValue: "x")
        )

        await #expect(throws: DomainError.self) {
            try await repository.update(session)
        }
    }

    // MARK: - Journal

    private func entry(body: String, isDraft: Bool = false) -> JournalEntry {
        let now = Date()
        return JournalEntry(
            body: body, isDraft: isDraft, createdAt: now, modifiedAt: now
        )
    }

    @Test("Published entries and drafts are listed separately")
    func draftsAreSeparate() async throws {
        let repository = SwiftDataJournalRepository(modelContainer: try makeContainer())

        try await repository.save(entry(body: "Published thought"))
        try await repository.save(entry(body: "Half a thought", isDraft: true))

        let published = try await repository.entries(limit: 50, offset: 0)
        let drafts = try await repository.drafts()

        #expect(published.count == 1)
        #expect(published.first?.body == "Published thought")
        #expect(drafts.count == 1)
        #expect(drafts.first?.isDraft == true)
    }

    @Test("Deleting hides an entry but keeps it recoverable")
    func deletionIsReversible() async throws {
        let repository = SwiftDataJournalRepository(modelContainer: try makeContainer())
        let written = entry(body: "Something I might regret deleting")
        try await repository.save(written)

        try await repository.softDelete(entryID: written.id, at: Date())

        #expect(try await repository.entries(limit: 50, offset: 0).isEmpty)
        let deleted = try await repository.deletedEntries()
        #expect(deleted.count == 1)
        // Nothing is destroyed — the words are still there.
        #expect(deleted.first?.body == "Something I might regret deleting")

        try await repository.restore(entryID: written.id)
        #expect(try await repository.entries(limit: 50, offset: 0).count == 1)
    }

    @Test("Purge destroys only entries past the restore window")
    func purgeRespectsTheWindow() async throws {
        let repository = SwiftDataJournalRepository(modelContainer: try makeContainer())
        let now = Date()

        let old = entry(body: "Long gone")
        let recent = entry(body: "Deleted yesterday")
        try await repository.save(old)
        try await repository.save(recent)

        try await repository.softDelete(
            entryID: old.id, at: now.addingTimeInterval(-JournalEntry.restoreWindow - 86_400)
        )
        try await repository.softDelete(
            entryID: recent.id, at: now.addingTimeInterval(-86_400)
        )

        let cutoff = now.addingTimeInterval(-JournalEntry.restoreWindow)
        let purged = try await repository.purge(deletedBefore: cutoff)

        #expect(purged == 1)
        let remaining = try await repository.deletedEntries()
        #expect(remaining.count == 1)
        #expect(remaining.first?.body == "Deleted yesterday")
    }

    @Test("Search matches title and body, and skips deleted entries")
    func searchBehaviour() async throws {
        let repository = SwiftDataJournalRepository(modelContainer: try makeContainer())

        var titled = entry(body: "nothing relevant here")
        titled.title = "Tokyo layover"
        try await repository.save(titled)
        try await repository.save(entry(body: "The flight into Tokyo was long"))

        let deletedOne = entry(body: "Tokyo again")
        try await repository.save(deletedOne)
        try await repository.softDelete(entryID: deletedOne.id, at: Date())

        let results = try await repository.entries(matching: "tokyo", limit: 50)

        #expect(results.count == 2)
        #expect(!results.contains { $0.id == deletedOne.id })
    }

    @Test("An empty search returns nothing rather than everything")
    func emptySearchReturnsNothing() async throws {
        let repository = SwiftDataJournalRepository(modelContainer: try makeContainer())
        try await repository.save(entry(body: "Anything"))

        #expect(try await repository.entries(matching: "   ", limit: 50).isEmpty)
    }

    @Test("Gratitude items survive the round trip")
    func gratitudeRoundTrips() async throws {
        let repository = SwiftDataJournalRepository(modelContainer: try makeContainer())
        var written = entry(body: "A good day")
        written.gratitudeItems = [
            GratitudeItem(text: "Coffee that stayed hot", createdAt: Date()),
            GratitudeItem(text: "The Monstera put out a leaf", createdAt: Date())
        ]

        try await repository.save(written)
        let loaded = try #require(try await repository.entry(id: written.id))

        #expect(loaded.gratitudeItems.count == 2)
        #expect(loaded.gratitudeItems.first?.text == "Coffee that stayed hot")
    }

    @Test("An entry with no gratitude decodes to an empty list, not a failure")
    func emptyGratitudeDecodes() async throws {
        let repository = SwiftDataJournalRepository(modelContainer: try makeContainer())
        let written = entry(body: "Plain entry")
        try await repository.save(written)

        let loaded = try #require(try await repository.entry(id: written.id))
        #expect(loaded.gratitudeItems.isEmpty)
    }

    @Test("Corrupted gratitude data loses the items, never the writing")
    func corruptedGratitudeKeepsTheEntry() {
        // Decoding is deliberately forgiving here: losing gratitude items is bad,
        // losing someone's entry would be far worse.
        let items = ModelMapping.decodeGratitude(Data([0x01, 0x02, 0x03]))
        #expect(items.isEmpty)
    }

    // MARK: - Media

    @Test("Media bytes round-trip through the file store")
    func mediaRoundTrips() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SunnieMediaTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = SwiftDataMediaRepository(modelContainer: try makeContainer())
        await repository.useFileStore(MediaFileStore(directory: directory))

        let store = MediaFileStore(directory: directory)
        let entryID = UUID()
        let attachment = MediaAttachment(
            owner: .journalEntry(entryID),
            kind: .photo,
            localToken: store.makeToken(for: .photo),
            createdAt: Date()
        )
        let bytes = Data("pretend this is a photo".utf8)

        _ = try await repository.save(attachment, data: bytes)

        #expect(try await repository.data(for: attachment.id) == bytes)
        let owned = try await repository.attachments(for: .journalEntry(entryID))
        #expect(owned.count == 1)
    }

    @Test("Deleting an attachment removes its file too")
    func deletingAttachmentRemovesFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SunnieMediaTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = SwiftDataMediaRepository(modelContainer: try makeContainer())
        let store = MediaFileStore(directory: directory)
        await repository.useFileStore(store)

        let token = store.makeToken(for: .voiceNote)
        let attachment = MediaAttachment(
            owner: .checkIn(UUID()),
            kind: .voiceNote,
            localToken: token,
            createdAt: Date()
        )
        _ = try await repository.save(attachment, data: Data([0x00]))
        #expect(store.exists(token: token))

        try await repository.delete(attachmentID: attachment.id)

        #expect(!store.exists(token: token))
        #expect(try await repository.attachment(id: attachment.id) == nil)
    }

    @Test("A token cannot escape the media directory")
    func tokensCannotTraverse() throws {
        // Tokens are generated internally, but a path component is stripped
        // anyway so a value from anywhere else stays inside the directory.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SunnieMediaTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MediaFileStore(directory: directory)
        try store.write(Data([0x01]), token: "../escaped.jpg")

        #expect(store.exists(token: "escaped.jpg"))
        let outside = directory.deletingLastPathComponent()
            .appendingPathComponent("escaped.jpg")
        #expect(!FileManager.default.fileExists(atPath: outside.path))
    }
}
