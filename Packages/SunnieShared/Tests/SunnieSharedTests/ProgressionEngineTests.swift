import Foundation
import Testing
@testable import SunnieShared

@Suite("Progression idempotency and fairness")
struct ProgressionEngineTests {

    private func makeEngine() -> (ProgressionEngine, InMemoryProgressionRepository) {
        let repository = InMemoryProgressionRepository()
        return (ProgressionEngine(repository: repository), repository)
    }

    private func actionKey(at date: Date) -> ActionKey {
        ActionKeyFactory.plantCare(
            plantID: TestFixtures.plantID, careType: .water, performedAt: date
        )
    }

    @Test("A first watering awards experience")
    func firstCareAwardsExperience() async throws {
        let (engine, repository) = makeEngine()
        let performedAt = TestFixtures.date(2026, 7, 15, 9)

        let outcome = try await engine.evaluatePlantCare(
            actionKey: actionKey(at: performedAt),
            plantID: TestFixtures.plantID,
            careType: .water,
            performedAt: performedAt,
            previousCareAt: nil
        )

        #expect(outcome.event?.experienceAwarded == 10)
        let profile = try await repository.profile()
        #expect(profile.experience == 10)
    }

    @Test("Evaluating the same action twice awards once")
    func duplicateEvaluationIsIdempotent() async throws {
        let (engine, repository) = makeEngine()
        let performedAt = TestFixtures.date(2026, 7, 15, 9)
        let key = actionKey(at: performedAt)

        let first = try await engine.evaluatePlantCare(
            actionKey: key,
            plantID: TestFixtures.plantID,
            careType: .water,
            performedAt: performedAt,
            previousCareAt: nil
        )
        let second = try await engine.evaluatePlantCare(
            actionKey: key,
            plantID: TestFixtures.plantID,
            careType: .water,
            performedAt: performedAt,
            previousCareAt: nil
        )

        #expect(first.event != nil)
        if case .skippedAsDuplicate = second {} else {
            Issue.record("Second evaluation should have been skipped as a duplicate")
        }

        let profile = try await repository.profile()
        #expect(profile.experience == 10)
        #expect(await repository.eventCount == 1)
    }

    @Test("Concurrent evaluation of one action still awards once")
    func concurrentEvaluationAwardsOnce() async throws {
        // Both callers pass the optimistic pre-check before either has saved, so
        // the repository's uniqueness constraint is what has to hold the line.
        let (engine, repository) = makeEngine()
        let performedAt = TestFixtures.date(2026, 7, 15, 9)
        let key = actionKey(at: performedAt)

        async let first = engine.evaluatePlantCare(
            actionKey: key,
            plantID: TestFixtures.plantID,
            careType: .water,
            performedAt: performedAt,
            previousCareAt: nil
        )
        async let second = engine.evaluatePlantCare(
            actionKey: key,
            plantID: TestFixtures.plantID,
            careType: .water,
            performedAt: performedAt,
            previousCareAt: nil
        )

        let outcomes = try await [first, second]
        let awarded = outcomes.filter { $0.event != nil }

        #expect(awarded.count == 1)
        #expect(await repository.eventCount == 1)
        let profile = try await repository.profile()
        #expect(profile.experience == 10)
    }

    @Test("Repeated watering minutes apart earns nothing extra")
    func implausibleRepeatEarnsNothing() async throws {
        let (engine, repository) = makeEngine()
        let first = TestFixtures.date(2026, 7, 15, 9)
        let again = first.addingTimeInterval(60 * 5)

        _ = try await engine.evaluatePlantCare(
            actionKey: actionKey(at: first),
            plantID: TestFixtures.plantID,
            careType: .water,
            performedAt: first,
            previousCareAt: nil
        )
        let outcome = try await engine.evaluatePlantCare(
            actionKey: actionKey(at: again),
            plantID: TestFixtures.plantID,
            careType: .water,
            performedAt: again,
            previousCareAt: first
        )

        #expect(outcome == .skippedAsImplausible(reason: .repeatedTooSoon))
        let profile = try await repository.profile()
        #expect(profile.experience == 10)
    }

    @Test("Watering again a week later earns normally")
    func plausibleRepeatEarnsAgain() async throws {
        let (engine, repository) = makeEngine()
        let first = TestFixtures.date(2026, 7, 15, 9)
        let later = TestFixtures.date(2026, 7, 22, 9)

        _ = try await engine.evaluatePlantCare(
            actionKey: actionKey(at: first),
            plantID: TestFixtures.plantID,
            careType: .water,
            performedAt: first,
            previousCareAt: nil
        )
        let outcome = try await engine.evaluatePlantCare(
            actionKey: actionKey(at: later),
            plantID: TestFixtures.plantID,
            careType: .water,
            performedAt: later,
            previousCareAt: first
        )

        #expect(outcome.event != nil)
        let profile = try await repository.profile()
        #expect(profile.experience == 20)
    }

    @Test("A first-time reward is granted once, not on every care action")
    func firstTimeRewardIsGrantedOnce() async throws {
        let (engine, repository) = makeEngine()
        let first = TestFixtures.date(2026, 7, 15, 9)
        let later = TestFixtures.date(2026, 7, 22, 9)

        let firstOutcome = try await engine.evaluatePlantCare(
            actionKey: actionKey(at: first),
            plantID: TestFixtures.plantID,
            careType: .water,
            performedAt: first,
            previousCareAt: nil
        )
        let secondOutcome = try await engine.evaluatePlantCare(
            actionKey: actionKey(at: later),
            plantID: TestFixtures.plantID,
            careType: .water,
            performedAt: later,
            previousCareAt: first
        )

        #expect(firstOutcome.rewards.count == 1)
        #expect(secondOutcome.rewards.isEmpty)
        #expect(await repository.rewardCount == 1)
    }

    @Test("Progression never decreases")
    func progressionNeverDecreases() async throws {
        let (engine, repository) = makeEngine()
        var previousExperience = 0

        // Includes duplicates and implausible repeats, which must leave the
        // total unchanged rather than reducing it.
        let dates = [
            TestFixtures.date(2026, 7, 15, 9),
            TestFixtures.date(2026, 7, 15, 9),
            TestFixtures.date(2026, 7, 15, 10),
            TestFixtures.date(2026, 7, 22, 9),
            TestFixtures.date(2026, 8, 1, 9)
        ]
        var lastCare: Date?

        for date in dates {
            _ = try await engine.evaluatePlantCare(
                actionKey: actionKey(at: date),
                plantID: TestFixtures.plantID,
                careType: .water,
                performedAt: date,
                previousCareAt: lastCare
            )
            let experience = try await repository.profile().experience
            #expect(experience >= previousExperience)
            previousExperience = experience
            if CareScheduleCalculator.isPlausibleRepeat(
                careType: .water, lastPerformedAt: lastCare, candidate: date
            ) {
                lastCare = date
            }
        }
    }

    @Test("Levels start at one and rise with experience")
    func levelCalculation() {
        let (engine, _) = makeEngine()

        #expect(engine.level(forExperience: 0) == 1)
        #expect(engine.level(forExperience: 99) == 1)
        #expect(engine.level(forExperience: 100) == 2)
        #expect(engine.level(forExperience: 250) == 3)
    }

    @Test("A different care type on the same plant is evaluated independently")
    func differentCareTypesAreIndependent() async throws {
        let (engine, repository) = makeEngine()
        let performedAt = TestFixtures.date(2026, 7, 15, 9)

        _ = try await engine.evaluatePlantCare(
            actionKey: ActionKeyFactory.plantCare(
                plantID: TestFixtures.plantID, careType: .water, performedAt: performedAt
            ),
            plantID: TestFixtures.plantID,
            careType: .water,
            performedAt: performedAt,
            previousCareAt: nil
        )
        let mistOutcome = try await engine.evaluatePlantCare(
            actionKey: ActionKeyFactory.plantCare(
                plantID: TestFixtures.plantID, careType: .mist, performedAt: performedAt
            ),
            plantID: TestFixtures.plantID,
            careType: .mist,
            performedAt: performedAt,
            previousCareAt: nil
        )

        #expect(mistOutcome.event != nil)
        #expect(await repository.eventCount == 2)
    }
}
