import Foundation
import SwiftData
import Testing
import SunnieShared
@testable import SunnieDays

/// End-to-end coverage of the Phase 3 flows, against the real composition root.
@MainActor
@Suite("Wellness and journal flows")
struct WellnessFlowTests {

    private static let referenceDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 15
        components.hour = 19
        components.timeZone = TimeZone(identifier: "UTC")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }()

    private func makeDependencies() throws -> AppDependencies {
        AppDependencies(
            modelContainer: try ModelContainerFactory.make(storage: .inMemory),
            clock: FixedClock(now: Self.referenceDate, timeZone: TimeZone(identifier: "UTC")!),
            enableWatchConnectivity: false
        )
    }

    // MARK: - Check-in

    @Test("A check-in saves, acknowledges, and updates the summary")
    func checkInFlow() async throws {
        let dependencies = try makeDependencies()

        let result = try await dependencies.recordWellnessCheckIn(
            mood: .four, energy: .three, note: "Good flight home."
        )

        #expect(result.wasNewlyRecorded)
        #expect(result.checkIn.mood == .four)
        #expect(result.message != nil)
        #expect(result.progression.event != nil)

        let summary = try await dependencies.wellnessSummaryProvider.summary()
        #expect(summary.checkInCount == 1)
        #expect(summary.hasCheckedInToday)
    }

    @Test("An entirely blank check-in is refused")
    func blankCheckInIsRefused() async throws {
        let dependencies = try makeDependencies()

        await #expect(throws: DomainError.self) {
            try await dependencies.recordWellnessCheckIn()
        }
        await #expect(throws: DomainError.self) {
            try await dependencies.recordWellnessCheckIn(note: "   ")
        }
    }

    @Test("Recording one dimension is enough")
    func partialCheckInIsAccepted() async throws {
        let dependencies = try makeDependencies()

        let result = try await dependencies.recordWellnessCheckIn(mood: .two)

        #expect(result.wasNewlyRecorded)
        #expect(result.checkIn.energy == nil)
    }

    @Test("A repeated check-in in the same minute records once")
    func repeatedCheckInIsIdempotent() async throws {
        let dependencies = try makeDependencies()

        let first = try await dependencies.recordWellnessCheckIn(mood: .three)
        let second = try await dependencies.recordWellnessCheckIn(mood: .three)

        #expect(first.wasNewlyRecorded)
        #expect(!second.wasNewlyRecorded)
        #expect(try await dependencies.wellnessSummaryProvider.summary().checkInCount == 1)
    }

    @Test("A harder check-in suppresses the nickname in Sunnie's reply")
    func sensitiveCheckInSoftensTheReply() async throws {
        // Even with the probability turned all the way up, "Noonies" must not
        // land on a low-mood entry (WELLNESS_JOURNAL_AND_CALM.md §3).
        let dependencies = try makeDependencies()
        var preferences = try await dependencies.preferencesRepository.preferences()
        preferences.nicknameProbability = 1.0
        try await dependencies.preferencesRepository.save(preferences)

        let result = try await dependencies.recordWellnessCheckIn(mood: .one, stress: .five)

        let message = try #require(result.message)
        #expect(result.checkIn.suggestsSensitiveMoment)
        #expect(!message.usedNickname)
        #expect(!message.text.contains("Noonies"))
    }

    @Test("A good check-in may still use the nickname")
    func ordinaryCheckInKeepsTheNickname() async throws {
        let dependencies = try makeDependencies()
        var preferences = try await dependencies.preferencesRepository.preferences()
        preferences.nicknameProbability = 1.0
        try await dependencies.preferencesRepository.save(preferences)

        let result = try await dependencies.recordWellnessCheckIn(mood: .five, stress: .one)

        let message = try #require(result.message)
        #expect(!result.checkIn.suggestsSensitiveMoment)
        #expect(message.usedNickname)
    }

    @Test("At most one suggestion is offered")
    func atMostOneSuggestion() async throws {
        // §3: "offer no more than one relevant optional action". The type makes
        // this structural — `suggestion` is a single optional, not a list.
        let dependencies = try makeDependencies()

        let stressed = try await dependencies.recordWellnessCheckIn(
            stress: .five, energy: .one, note: "A lot today"
        )

        #expect(stressed.suggestion != nil)
        if case .breathing = stressed.suggestion {} else {
            Issue.record("High stress should offer breathing first")
        }
    }

    @Test("An even check-in offers nothing at all")
    func neutralCheckInOffersNothing() async throws {
        let dependencies = try makeDependencies()

        let result = try await dependencies.recordWellnessCheckIn(
            mood: .three, energy: .three, stress: .three
        )

        #expect(result.suggestion == nil)
    }

    @Test("Check-ins publish a domain event Today can hear")
    func checkInPublishesEvent() async throws {
        let dependencies = try makeDependencies()
        let recorder = EventRecorder()
        await dependencies.eventBus.subscribe { await recorder.record($0) }

        _ = try await dependencies.recordWellnessCheckIn(mood: .four)

        let events = await recorder.events
        #expect(events.contains { $0.type == .wellnessCheckInRecorded })
    }

    // MARK: - Practices

    @Test("A practice is recorded when it starts and finished when it ends")
    func practiceLifecycle() async throws {
        let dependencies = try makeDependencies()

        let session = try await dependencies.manageWellnessSession.start(
            type: .breathing,
            practiceID: "sunnie.breathing.equal",
            plannedDuration: 80
        )
        #expect(!session.isFinished)

        let finished = try await dependencies.manageWellnessSession.finish(
            session, completion: .completed
        )
        #expect(finished.isFinished)

        let summary = try await dependencies.wellnessSummaryProvider.summary()
        #expect(summary.practiceCount == 1)
    }

    @Test("Stopping early is recorded but does not count toward minutes")
    func abandonedPracticeIsRecordedNotCounted() async throws {
        let dependencies = try makeDependencies()

        let session = try await dependencies.manageWellnessSession.start(
            type: .meditation, practiceID: "sunnie.meditation.silent", plannedDuration: 600
        )
        _ = try await dependencies.manageWellnessSession.finish(
            session, completion: .endedEarly
        )

        let summary = try await dependencies.wellnessSummaryProvider.summary()
        // The session exists in history; it just is not claimed as time spent.
        #expect(summary.practiceCount == 0)
        let stored = try await dependencies.wellnessRepository.session(id: session.id)
        #expect(stored?.completion == .endedEarly)
    }

    // MARK: - Journal

    @Test("A draft is created, autosaved, and published")
    func journalLifecycle() async throws {
        let dependencies = try makeDependencies()

        var draft = try await dependencies.manageJournalEntry.beginOrResumeDraft()
        #expect(draft.isDraft)

        draft.body = "The Monstera put out a new leaf today."
        try await dependencies.manageJournalEntry.autosave(draft)

        let saved = try #require(try await dependencies.journalRepository.entry(id: draft.id))
        #expect(saved.body.contains("new leaf"))
        #expect(saved.isDraft)

        let published = try #require(
            try await dependencies.manageJournalEntry.publish(draft)
        )
        #expect(!published.isDraft)
        #expect(try await dependencies.journalRepository.entries(limit: 10, offset: 0).count == 1)
    }

    @Test("Beginning a draft resumes an unfinished one rather than piling up")
    func draftsAreResumed() async throws {
        let dependencies = try makeDependencies()

        var first = try await dependencies.manageJournalEntry.beginOrResumeDraft()
        first.body = "Half a thought"
        try await dependencies.manageJournalEntry.autosave(first)

        let second = try await dependencies.manageJournalEntry.beginOrResumeDraft()

        #expect(second.id == first.id)
        #expect(try await dependencies.journalRepository.drafts().count == 1)
    }

    @Test("Publishing an empty entry discards it instead of archiving noise")
    func emptyEntryIsDiscarded() async throws {
        let dependencies = try makeDependencies()
        let draft = try await dependencies.manageJournalEntry.beginOrResumeDraft()

        let published = try await dependencies.manageJournalEntry.publish(draft)

        #expect(published == nil)
        #expect(try await dependencies.journalRepository.entries(limit: 10, offset: 0).isEmpty)
    }

    @Test("Autosaving an empty draft writes nothing")
    func autosaveSkipsEmptyDrafts() async throws {
        let dependencies = try makeDependencies()
        let draft = try await dependencies.manageJournalEntry.beginOrResumeDraft()

        try await dependencies.manageJournalEntry.autosave(draft)

        let stored = try await dependencies.journalRepository.entry(id: draft.id)
        #expect(stored?.hasContent == false)
    }

    @Test("A deleted entry can be brought back")
    func deletedEntriesRestore() async throws {
        let dependencies = try makeDependencies()
        var draft = try await dependencies.manageJournalEntry.beginOrResumeDraft()
        draft.body = "Worth keeping"
        let published = try #require(try await dependencies.manageJournalEntry.publish(draft))

        try await dependencies.manageJournalEntry.delete(published)
        #expect(try await dependencies.journalRepository.entries(limit: 10, offset: 0).isEmpty)

        try await dependencies.manageJournalEntry.restore(published)
        let restored = try await dependencies.journalRepository.entries(limit: 10, offset: 0)
        #expect(restored.count == 1)
        #expect(restored.first?.body == "Worth keeping")
    }

    @Test("Housekeeping never touches a recently deleted entry")
    func purgeLeavesRecentDeletionsAlone() async throws {
        let dependencies = try makeDependencies()
        var draft = try await dependencies.manageJournalEntry.beginOrResumeDraft()
        draft.body = "Deleted a moment ago"
        let published = try #require(try await dependencies.manageJournalEntry.publish(draft))
        try await dependencies.manageJournalEntry.delete(published)

        await dependencies.performLaunchHousekeeping()

        #expect(try await dependencies.journalRepository.deletedEntries().count == 1)
    }

    @Test("Gratitude is added to an entry")
    func gratitudeIsAdded() async throws {
        let dependencies = try makeDependencies()
        let draft = try await dependencies.manageJournalEntry.beginOrResumeDraft()

        let updated = try await dependencies.manageJournalEntry
            .addGratitude("The Monstera", to: draft)

        #expect(updated.gratitudeItems.count == 1)
        // Blank input is ignored rather than adding an empty item.
        let unchanged = try await dependencies.manageJournalEntry
            .addGratitude("   ", to: updated)
        #expect(unchanged.gratitudeItems.count == 1)
    }

    // MARK: - Reminders

    @Test("Reminders are not scheduled without permission")
    func remindersRequirePermission() async throws {
        // The service never asks for permission itself — that would be exactly
        // the pressure the tone rules forbid. It simply does nothing until the
        // user grants it in Settings.
        let dependencies = try makeDependencies()

        let plan = await dependencies.reminderScheduler.offer(
            category: .wellnessRoutine,
            sourceEntityID: UUID(),
            messageID: "sunnie.message.gentleReminder.01",
            route: "sunniedays://wellness/checkin",
            desiredFireDate: Self.referenceDate.addingTimeInterval(3600),
            cadenceLevel: .single
        )

        #expect(!plan.isScheduled)
    }
}
