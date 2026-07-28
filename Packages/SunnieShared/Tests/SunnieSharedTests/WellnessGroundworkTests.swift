import Foundation
import Testing
@testable import SunnieShared

@Suite("Check-in records")
struct WellnessCheckInTests {

    private func checkIn(
        mood: WellnessScaleValue? = nil,
        stress: WellnessScaleValue? = nil,
        note: String? = nil
    ) -> WellnessCheckIn {
        let recordedAt = TestFixtures.date(2026, 7, 15, 9)
        return WellnessCheckIn(
            recordedAt: recordedAt,
            timeZoneID: TestFixtures.utc.identifier,
            mood: mood,
            stress: stress,
            note: note,
            sourceDeviceID: TestFixtures.phoneDevice,
            actionKey: ActionKeyFactory.wellnessCheckIn(recordedAt: recordedAt),
            createdAt: recordedAt
        )
    }

    @Test("A check-in with only a note is a real entry")
    func noteOnlyEntryIsValid() {
        // The form never demands a complete answer; recording one thing is enough.
        #expect(!checkIn(note: "Long flight, short sleep.").isEmpty)
    }

    @Test("A check-in with nothing at all is empty")
    func untouchedEntryIsEmpty() {
        #expect(checkIn().isEmpty)
        #expect(checkIn(note: "   ").isEmpty)
    }

    @Test("Stress runs the opposite way from mood")
    func dimensionPolarity() {
        #expect(WellnessDimension.mood.polarity == .higherIsEasier)
        #expect(WellnessDimension.energy.polarity == .higherIsEasier)
        #expect(WellnessDimension.sleepQuality.polarity == .higherIsEasier)
        #expect(WellnessDimension.stress.polarity == .lowerIsEasier)
    }

    @Test("Each dimension gets its own scale labels")
    func scaleLabelsAreDimensionSpecific() {
        // "Low" means something different for energy than for stress, so the two
        // must not share a label set.
        let energy = WellnessDimension.energy.scaleLabelKey(for: .one)
        let stress = WellnessDimension.stress.scaleLabelKey(for: .one)
        #expect(energy != stress)
    }

    @Test(
        "A low mood or high stress softens Sunnie's response",
        arguments: [
            (WellnessScaleValue.one, WellnessScaleValue?.none, true),
            (WellnessScaleValue.two, nil, true),
            (WellnessScaleValue.three, nil, false),
            (WellnessScaleValue.five, nil, false)
        ]
    )
    func sensitiveMomentFromMood(
        mood: WellnessScaleValue,
        stress: WellnessScaleValue?,
        expected: Bool
    ) {
        #expect(checkIn(mood: mood, stress: stress).suggestsSensitiveMoment == expected)
    }

    @Test("High stress alone is enough to soften the response")
    func sensitiveMomentFromStress() {
        #expect(checkIn(mood: .four, stress: .five).suggestsSensitiveMoment)
        #expect(!checkIn(mood: .four, stress: .two).suggestsSensitiveMoment)
    }

    @Test("Check-in keys collapse a redelivered entry, sessions do not")
    func actionKeys() {
        let moment = TestFixtures.date(2026, 7, 15, 9, 30)

        // Same minute, same check-in.
        #expect(
            ActionKeyFactory.wellnessCheckIn(recordedAt: moment)
                == ActionKeyFactory.wellnessCheckIn(recordedAt: moment.addingTimeInterval(20))
        )
        // A genuinely later check-in is its own entry.
        #expect(
            ActionKeyFactory.wellnessCheckIn(recordedAt: moment)
                != ActionKeyFactory.wellnessCheckIn(recordedAt: moment.addingTimeInterval(3600))
        )
        // Two short practices in one minute are two real sessions.
        #expect(
            ActionKeyFactory.wellnessSession(sessionID: UUID())
                != ActionKeyFactory.wellnessSession(sessionID: UUID())
        )
    }

    @Test("Session duration comes from the clock, not the plan")
    func sessionDuration() {
        let started = TestFixtures.date(2026, 7, 15, 9)
        var session = WellnessSession(
            type: .breathing,
            practiceID: "sunnie.breathing.equal",
            startedAt: started,
            plannedDuration: 300,
            sourceDeviceID: TestFixtures.phoneDevice,
            actionKey: ActionKeyFactory.wellnessSession(sessionID: UUID())
        )

        #expect(session.actualDuration == nil)
        #expect(!session.isFinished)

        session.endedAt = started.addingTimeInterval(90)
        session.completion = .endedEarly

        #expect(session.actualDuration == 90)
        #expect(session.isFinished)
    }
}

@Suite("Wellness history is descriptive")
struct WellnessSummaryTests {

    private func checkIn(
        daysAgo: Int,
        mood: WellnessScaleValue?,
        stress: WellnessScaleValue? = nil
    ) -> WellnessCheckIn {
        let recordedAt = TestFixtures.date(2026, 7, 15, 9)
            .addingTimeInterval(-Double(daysAgo) * 86_400)
        return WellnessCheckIn(
            recordedAt: recordedAt,
            timeZoneID: TestFixtures.utc.identifier,
            mood: mood,
            stress: stress,
            sourceDeviceID: TestFixtures.phoneDevice,
            actionKey: ActionKeyFactory.wellnessCheckIn(recordedAt: recordedAt),
            createdAt: recordedAt
        )
    }

    private func summary(
        checkIns: [WellnessCheckIn],
        sessions: [WellnessSession] = []
    ) -> WellnessSummary {
        let now = TestFixtures.date(2026, 7, 15, 12)
        return WellnessSummaryBuilder.build(
            checkIns: checkIns,
            sessions: sessions,
            periodStart: now.addingTimeInterval(-7 * 86_400),
            periodEnd: now,
            now: now,
            calendar: TestFixtures.calendar,
            timeZone: TestFixtures.utc
        )
    }

    @Test("Distributions count what was recorded and nothing else")
    func distributionsCountEntries() throws {
        let result = summary(checkIns: [
            checkIn(daysAgo: 0, mood: .four),
            checkIn(daysAgo: 1, mood: .four),
            checkIn(daysAgo: 2, mood: .two),
            checkIn(daysAgo: 3, mood: nil)
        ])

        let mood = try #require(result.distribution(for: .mood))
        #expect(mood.counts[.four] == 2)
        #expect(mood.counts[.two] == 1)
        // An unanswered dimension contributes nothing rather than a default.
        #expect(mood.totalEntries == 3)
        #expect(result.checkInCount == 4)
    }

    @Test("A tie reports no most-frequent value rather than picking one")
    func tiesAreNotResolvedArbitrarily() throws {
        let result = summary(checkIns: [
            checkIn(daysAgo: 0, mood: .two),
            checkIn(daysAgo: 1, mood: .four)
        ])

        let mood = try #require(result.distribution(for: .mood))
        #expect(mood.mostFrequent == nil)
    }

    @Test("The comfortable end is counted per dimension, not by raw value")
    func easierEndRespectsPolarity() throws {
        // Mood 5 and stress 1 both describe an easier day, at opposite ends of
        // the scale. Counting raw values would call a calm week a bad one.
        let result = summary(checkIns: [
            checkIn(daysAgo: 0, mood: .five, stress: .one),
            checkIn(daysAgo: 1, mood: .one, stress: .five)
        ])

        let mood = try #require(result.distribution(for: .mood))
        let stress = try #require(result.distribution(for: .stress))

        #expect(mood.easierEndCount == 1)
        #expect(stress.easierEndCount == 1)
    }

    @Test("Only completed practices count toward minutes")
    func abandonedSessionsDoNotCountTime() {
        let started = TestFixtures.date(2026, 7, 15, 9)
        func session(
            completion: WellnessSessionCompletion,
            seconds: TimeInterval
        ) -> WellnessSession {
            WellnessSession(
                type: .meditation,
                startedAt: started,
                endedAt: started.addingTimeInterval(seconds),
                plannedDuration: 600,
                completion: completion,
                sourceDeviceID: TestFixtures.phoneDevice,
                actionKey: ActionKeyFactory.wellnessSession(sessionID: UUID())
            )
        }

        let result = summary(checkIns: [], sessions: [
            session(completion: .completed, seconds: 300),
            session(completion: .endedEarly, seconds: 120),
            session(completion: .interrupted, seconds: 60)
        ])

        #expect(result.practiceCount == 1)
        #expect(result.practiceMinutes == 5)
    }

    @Test("Today's check-in is noticed, an older one is not")
    func checkedInTodayIsAccurate() {
        #expect(summary(checkIns: [checkIn(daysAgo: 0, mood: .three)]).hasCheckedInToday)
        #expect(!summary(checkIns: [checkIn(daysAgo: 1, mood: .three)]).hasCheckedInToday)
        #expect(!summary(checkIns: []).hasCheckedInToday)
    }

    @Test("An empty history is a valid state")
    func emptyHistoryIsValid() {
        let result = summary(checkIns: [])

        #expect(result.checkInCount == 0)
        #expect(result.practiceMinutes == 0)
        #expect(result.mostRecentCheckIn == nil)
        // Every dimension is still present, just empty — the chart renders as
        // "nothing recorded yet" rather than disappearing.
        #expect(result.distributions.count == WellnessDimension.allCases.count)
    }
}

@Suite("Affirmation selection")
struct AffirmationServiceTests {

    private var pack: WellnessPack { ContentRegistry.builtIn().wellnessPack }

    private func service(seed: UInt64 = 11) -> AffirmationService {
        AffirmationService(pack: pack, random: SeededRandomSource(seed: seed))
    }

    @Test("A harder moment never returns a bright line")
    func sensitiveMomentsExcludeBrightLines() throws {
        // This filter has no fallback: on a hard day a congratulatory line is
        // worse than a plain one, so running out means returning nothing.
        for _ in 0..<50 {
            let affirmation = try #require(service().affirmation(
                for: .init(phase: .day, isSensitiveMoment: true)
            ))
            #expect(affirmation.suitsSensitiveMoments)
        }
    }

    @Test("A hidden line never returns, even when it is the only match")
    func hiddenLinesAreNeverReturned() throws {
        let all = Set(pack.affirmations.map(\.id))
        let target = try #require(pack.affirmations.first)
        let preferences = AffirmationService.Preferences(
            favoriteIDs: [], hiddenIDs: [target.id]
        )

        for _ in 0..<50 {
            let affirmation = try #require(service().affirmation(
                for: .init(phase: .day, preferences: preferences)
            ))
            #expect(affirmation.id != target.id)
            #expect(all.contains(affirmation.id))
        }
    }

    @Test("Hiding everything returns nothing, which is what was asked for")
    func hidingEverythingReturnsNil() {
        let preferences = AffirmationService.Preferences(
            favoriteIDs: [],
            hiddenIDs: Set(pack.affirmations.map(\.id))
        )

        #expect(service().affirmation(for: .init(phase: .day, preferences: preferences)) == nil)
    }

    @Test("A requested tag is preferred when something matches it")
    func tagsAreHonoured() throws {
        let affirmation = try #require(service().affirmation(
            for: .init(phase: .evening, tags: [.rest])
        ))
        #expect(affirmation.tags.contains(.rest) || affirmation.matches(phase: .evening))
    }

    @Test("A recently shown line is avoided when alternatives exist")
    func avoidsRecentRepetition() throws {
        let first = try #require(service(seed: 5).affirmation(for: .init(phase: .day)))
        let second = try #require(service(seed: 5).affirmation(
            for: .init(phase: .day, recentlyShownIDs: [first.id])
        ))

        #expect(second.id != first.id)
    }

    @Test("Every phase can produce an affirmation, sensitive or not")
    func everyPhaseResolves() {
        for phase in TimePhase.allCases {
            for sensitive in [true, false] {
                let affirmation = service().affirmation(
                    for: .init(phase: phase, isSensitiveMoment: sensitive)
                )
                #expect(affirmation != nil, "no affirmation for \(phase.rawValue), sensitive: \(sensitive)")
            }
        }
    }

    @Test("Box breathing is offered but not suggested by default")
    func advancedPatternsAreNotDefaultSuggestions() throws {
        let suggested = service().suggestedBreathingPatterns

        #expect(!suggested.isEmpty)
        #expect(suggested.allSatisfy { !$0.isAdvanced })
        #expect(service().breathingPattern(id: "sunnie.breathing.box")?.isAdvanced == true)
    }

    @Test("Breathing patterns describe a cycle that actually advances")
    func breathingPatternsAreWellFormed() throws {
        for pattern in pack.breathingPatterns {
            #expect(pattern.isWellFormed, "malformed: \(pattern.id.rawValue)")
            #expect(pattern.cycleDuration > 0)
            #expect(pattern.totalDuration(cycles: 3) == pattern.cycleDuration * 3)
        }

        let equal = try #require(service().breathingPattern(id: "sunnie.breathing.equal"))
        #expect(equal.cycleDuration == 8)
    }
}

@Suite("Wellness content rules")
struct WellnessContentTests {

    @Test("The shipped wellness pack decodes and validates")
    func wellnessPackIsValid() throws {
        let pack = try #require(
            ContentRegistry.decode(WellnessPack.self, resource: "wellness.v1"),
            "The wellness pack failed to decode; the app would fall back to minimal content."
        )

        let issues = ContentValidator.validate(pack)
        #expect(issues.isEmpty, "Issues: \(issues.map(\.description))")
        #expect(!pack.affirmations.isEmpty)
        #expect(pack.meditations.count >= 4)
    }

    @Test("The fallback wellness pack is itself valid")
    func fallbackWellnessPackIsValid() {
        let issues = ContentValidator.validate(FallbackContent.wellnessPack)
        #expect(issues.isEmpty, "Issues: \(issues.map(\.description))")
    }

    @Test("Medical and diagnostic claims are rejected")
    func claimGateCatchesMedicalLanguage() {
        let samples = [
            "Your heart rate proves you are anxious.",
            "This is a symptom of stress.",
            "This breathing exercise will cure your insomnia.",
            "Clinically proven to help.",
            "Guaranteed to make today better."
        ]

        for sample in samples {
            #expect(
                !ContentValidator.claimIssues(in: sample, contentID: "test").isEmpty,
                "claim gate missed: \(sample)"
            )
        }
    }

    @Test("Honest health copy is not mistaken for a claim")
    func claimGateAvoidsFalsePositives() {
        // The app must be able to say what it is *not* doing, and plant care
        // legitimately involves the word "treatment".
        let samples = [
            "This shows what you recorded. It isn't medical advice.",
            "Sunnie Days doesn't diagnose anything.",
            "Pest treatment",
            "Your Health data may be incomplete."
        ]

        for sample in samples {
            let issues = ContentValidator.claimIssues(in: sample, contentID: "test")
            #expect(issues.isEmpty, "false positive on \(sample): \(issues.map(\.description))")
        }
    }

    @Test("No shipped affirmation promises an outcome")
    func shippedAffirmationsMakeNoPromises() {
        let pack = ContentRegistry.builtIn().wellnessPack

        for affirmation in pack.affirmations {
            let issues = ContentValidator.claimIssues(
                in: affirmation.text, contentID: affirmation.id.rawValue
            ) + ContentValidator.toneIssues(
                in: affirmation.text, contentID: affirmation.id.rawValue
            )
            #expect(issues.isEmpty, "\(affirmation.id.rawValue): \(issues.map(\.description))")
        }
    }

    @Test("Enough affirmations survive the sensitive-moment filter")
    func sensitiveLibraryIsNotThin() {
        // If the filtered library ran dry, the card would be blank exactly when
        // it matters most.
        let pack = ContentRegistry.builtIn().wellnessPack
        let suitable = pack.affirmations.filter(\.suitsSensitiveMoments)

        #expect(suitable.count >= 5)
    }

    @Test("A malformed breathing pattern is reported")
    func malformedBreathingPatternIsReported() {
        let pack = WellnessPack(
            manifest: FallbackContent.manifest,
            affirmations: FallbackContent.wellnessPack.affirmations,
            breathingPatterns: [
                .init(
                    id: "sunnie.breathing.broken",
                    displayNameKey: "x",
                    descriptionKey: "y",
                    inhaleSeconds: 0,
                    holdAfterInhaleSeconds: 0,
                    exhaleSeconds: 0,
                    holdAfterExhaleSeconds: 0,
                    defaultCycles: 0
                )
            ],
            meditations: FallbackContent.wellnessPack.meditations,
            calmSounds: []
        )

        let issues = ContentValidator.validate(pack)
        #expect(issues.contains {
            if case .malformedBreathingPattern = $0.kind { return true }
            return false
        })
    }

    @Test("A library with no gentle affirmations is reported")
    func libraryWithoutGentleLinesIsReported() {
        let pack = WellnessPack(
            manifest: FallbackContent.manifest,
            affirmations: [
                .init(
                    id: "sunnie.affirmation.bright.only",
                    text: "What a fantastic day this is.",
                    localizationKey: "x",
                    suitsSensitiveMoments: false
                )
            ],
            breathingPatterns: FallbackContent.wellnessPack.breathingPatterns,
            meditations: FallbackContent.wellnessPack.meditations,
            calmSounds: []
        )

        let issues = ContentValidator.validate(pack)
        #expect(issues.contains {
            if case .emptyCategory = $0.kind { return true }
            return false
        })
    }
}

@Suite("Sensitive moments suppress the nickname")
struct SensitiveNicknameTests {

    @Test("A warm category loses the nickname on a harder day")
    func sensitiveMomentBeatsCategoryAndChance() {
        // Celebration is nickname-eligible and probability 1.0 always passes the
        // dice roll, but "Noonies" answering a low-mood check-in trivializes it.
        #expect(!NicknameEligibility.shouldUseNickname(
            category: .celebration,
            nickname: "Noonies",
            probability: 1.0,
            isSensitiveMoment: true,
            random: FixedRandomSource(value: 0)
        ))

        #expect(NicknameEligibility.shouldUseNickname(
            category: .celebration,
            nickname: "Noonies",
            probability: 1.0,
            isSensitiveMoment: false,
            random: FixedRandomSource(value: 0)
        ))
    }

    @Test("The message service honours the sensitivity flag")
    func serviceHonoursSensitiveMoment() throws {
        let service = SunnieMessageService(
            registry: ContentRegistry.builtIn(),
            random: FixedRandomSource(value: 0)
        )

        let message = try #require(service.message(for: SunnieMessageContext(
            category: .careCompleted,
            timeContext: TestFixtures.timeContext(phase: .day),
            displayName: "Vanessa",
            nickname: "Noonies",
            nicknameProbability: 1.0,
            isSensitiveMoment: true
        )))

        #expect(!message.usedNickname)
        #expect(!message.text.contains("Noonies"))
    }

    @Test("Sensitivity defaults to off, so existing behaviour is unchanged")
    func defaultsToNotSensitive() {
        let context = SunnieMessageContext(
            category: .greeting,
            timeContext: TestFixtures.timeContext(phase: .day),
            displayName: "Vanessa",
            nickname: "Noonies",
            nicknameProbability: 1.0
        )

        #expect(!context.isSensitiveMoment)
    }
}
