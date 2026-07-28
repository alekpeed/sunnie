import Foundation
import Testing
@testable import SunnieShared

@Suite("Nickname eligibility")
struct NicknameEligibilityTests {

    @Test(
        "Warm moments may use the nickname",
        arguments: [
            SunnieMessageCategory.greeting,
            .celebration,
            .casualAffirmation,
            .postcard,
            .homeScene,
            .careCompleted
        ]
    )
    func warmCategoriesAreEligible(category: SunnieMessageCategory) {
        #expect(NicknameEligibility.isEligible(category: category, nickname: "Noonies"))
    }

    @Test(
        "Serious and sensitive moments never may",
        arguments: [
            SunnieMessageCategory.permissionRequest,
            .error,
            .privacyNotice,
            .healthExplanation,
            .travelDocumentAlert,
            .gentleReminder
        ]
    )
    func seriousCategoriesAreIneligible(category: SunnieMessageCategory) {
        #expect(!NicknameEligibility.isEligible(category: category, nickname: "Noonies"))
    }

    @Test("An ineligible category stays ineligible even when chance says yes")
    func categoryGateBeatsProbability() {
        // Probability 1.0 would always pass the dice roll. The category gate must
        // still refuse, because a nickname in a privacy notice is never acceptable.
        let result = NicknameEligibility.shouldUseNickname(
            category: .privacyNotice,
            nickname: "Noonies",
            probability: 1.0,
            random: FixedRandomSource(value: 0)
        )

        #expect(!result)
    }

    @Test("No nickname configured means no nickname used")
    func missingNicknameIsNotUsed() {
        #expect(!NicknameEligibility.shouldUseNickname(
            category: .greeting,
            nickname: nil,
            probability: 1.0,
            random: FixedRandomSource(value: 0)
        ))

        #expect(!NicknameEligibility.shouldUseNickname(
            category: .greeting,
            nickname: "   ",
            probability: 1.0,
            random: FixedRandomSource(value: 0)
        ))
    }

    @Test("The probability gate is honoured at the boundary")
    func probabilityGateBoundary() {
        // Draw below the threshold uses it; a draw at the threshold does not.
        #expect(NicknameEligibility.shouldUseNickname(
            category: .greeting,
            nickname: "Noonies",
            probability: 0.05,
            random: FixedRandomSource(value: 0.049)
        ))

        #expect(!NicknameEligibility.shouldUseNickname(
            category: .greeting,
            nickname: "Noonies",
            probability: 0.05,
            random: FixedRandomSource(value: 0.05)
        ))
    }

    @Test("Roughly one in twenty eligible messages uses the nickname")
    func observedRateMatchesConfiguration() {
        let random = SeededRandomSource(seed: 20_260_715)
        var used = 0
        let trials = 20_000

        for _ in 0..<trials
        where NicknameEligibility.shouldUseNickname(
            category: .greeting,
            nickname: "Noonies",
            probability: NicknameEligibility.defaultProbability,
            random: random
        ) {
            used += 1
        }

        let rate = Double(used) / Double(trials)
        #expect(abs(rate - 0.05) < 0.01)
    }

    @Test("The placeholder resolves to a real name in both branches")
    func placeholderResolution() {
        let template = "Good morning, {name}."

        #expect(NicknameEligibility.resolve(
            template: template,
            displayName: "Vanessa",
            nickname: "Noonies",
            useNickname: true
        ) == "Good morning, Noonies.")

        #expect(NicknameEligibility.resolve(
            template: template,
            displayName: "Vanessa",
            nickname: "Noonies",
            useNickname: false
        ) == "Good morning, Vanessa.")
    }

    @Test("No placeholder ever survives into displayed text")
    func placeholderNeverLeaks() {
        let resolved = NicknameEligibility.resolve(
            template: "Hello, {name}.",
            displayName: "Vanessa",
            nickname: nil,
            useNickname: true
        )

        #expect(!resolved.contains("{name}"))
        #expect(resolved == "Hello, Vanessa.")
    }
}

@Suite("Sunnie message selection")
struct SunnieMessageServiceTests {

    private let registry = ContentRegistry.builtIn()

    private func service(seed: UInt64 = 1) -> SunnieMessageService {
        SunnieMessageService(
            registry: registry,
            random: SeededRandomSource(seed: seed),
            displayName: "Vanessa"
        )
    }

    private func context(
        category: SunnieMessageCategory,
        phase: TimePhase,
        recent: [ContentID] = [],
        probability: Double = 0
    ) -> SunnieMessageContext {
        SunnieMessageContext(
            category: category,
            timeContext: TestFixtures.timeContext(phase: phase),
            nickname: "Noonies",
            nicknameProbability: probability,
            recentlyShownIDs: recent
        )
    }

    @Test("Phase-specific greetings win over generic ones")
    func prefersPhaseSpecificMessages() throws {
        let message = try #require(
            service().message(for: context(category: .greeting, phase: .lateNight))
        )

        let definition = try #require(
            registry.messagePack.messages.first { $0.id == message.id }
        )
        #expect(definition.phases.contains(.lateNight))
    }

    @Test("A recently shown message is avoided when alternatives exist")
    func avoidsRecentlyShown() throws {
        let first = try #require(
            service(seed: 7).message(for: context(category: .careCompleted, phase: .day))
        )

        let second = try #require(
            service(seed: 7).message(
                for: context(category: .careCompleted, phase: .day, recent: [first.id])
            )
        )

        #expect(second.id != first.id)
    }

    @Test("Sunnie still speaks when every message was shown recently")
    func fallsBackRatherThanGoingSilent() throws {
        let allIDs = registry.messages(for: .careCompleted).map(\.id)

        let message = service().message(
            for: context(category: .careCompleted, phase: .day, recent: allIDs)
        )

        #expect(message != nil)
    }

    @Test("Every category can produce a message")
    func everyCategoryResolves() throws {
        for category in SunnieMessageCategory.allCases {
            for phase in TimePhase.allCases {
                let message = service().message(for: context(category: category, phase: phase))
                #expect(message != nil, "No message for \(category.rawValue) in \(phase.rawValue)")
            }
        }
    }

    @Test("Resolved text never leaks a placeholder")
    func resolvedTextIsComplete() throws {
        for category in SunnieMessageCategory.allCases {
            let message = try #require(
                service().message(for: context(category: category, phase: .day, probability: 1))
            )
            #expect(!message.text.contains("{name}"))
            #expect(!message.text.isEmpty)
        }
    }

    @Test("An ineligible category never reports using the nickname")
    func ineligibleCategoriesNeverUseNickname() throws {
        for category in SunnieMessageCategory.allCases where !category.isNicknameEligible {
            let message = try #require(
                service().message(for: context(category: category, phase: .day, probability: 1))
            )
            #expect(!message.usedNickname)
            #expect(!message.text.contains("Noonies"))
        }
    }

    @Test("Message visual state inherits the time context's animation intensity")
    func visualStateFollowsMotionSetting() throws {
        let reducedContext = SunnieMessageContext(
            category: .careCompleted,
            timeContext: TimePhaseEngine(calendar: TestFixtures.calendar).resolve(
                at: TestFixtures.date(2026, 7, 15, 12),
                preferences: TestFixtures.preferences(),
                timeZone: TestFixtures.utc,
                reduceMotion: true
            ),
            nickname: "Noonies",
            nicknameProbability: 0
        )

        let message = try #require(service().message(for: reducedContext))
        #expect(message.visualState.animationIntensity == 0)
    }
}
