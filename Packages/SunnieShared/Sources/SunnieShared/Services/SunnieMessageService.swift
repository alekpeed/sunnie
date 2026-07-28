import Foundation

/// Chooses what Sunnie says.
///
/// Selection narrows from most specific to least: messages authored for the
/// current time phase are preferred, then any message in the category. Recently
/// shown messages are avoided so Sunnie does not repeat himself back to back —
/// unless avoiding them would leave nothing to say, in which case repeating is
/// better than silence.
public struct SunnieMessageService: SunnieMessageProviding {

    private let registry: ContentRegistry
    private let random: any RandomSource

    public init(
        registry: ContentRegistry,
        random: any RandomSource = SystemRandomSource()
    ) {
        self.registry = registry
        self.random = random
    }

    public func message(for context: SunnieMessageContext) -> SunnieMessage? {
        let candidates = candidates(for: context)
        guard !candidates.isEmpty else { return nil }

        let definition = candidates[random.nextIndex(upperBound: candidates.count)]

        let useNickname = NicknameEligibility.shouldUseNickname(
            category: context.category,
            nickname: context.nickname,
            probability: context.nicknameProbability,
            isSensitiveMoment: context.isSensitiveMoment,
            random: random
        )

        let text = NicknameEligibility.resolve(
            template: definition.template,
            displayName: context.displayName,
            nickname: context.nickname,
            useNickname: useNickname
        )

        return SunnieMessage(
            id: definition.id,
            text: text,
            category: definition.category,
            visualState: SunnieVisualState(
                expression: definition.expression,
                pose: definition.pose,
                presence: .small,
                outfitID: nil,
                propID: nil,
                animationIntensity: context.timeContext.animationIntensity
            ),
            usedNickname: useNickname
        )
    }

    func candidates(for context: SunnieMessageContext) -> [SunnieMessageDefinition] {
        let all = registry.messages(for: context.category)
        guard !all.isEmpty else { return [] }

        let phase = context.timeContext.phase
        let recent = Set(context.recentlyShownIDs)

        // Authored specifically for this phase, and not just shown.
        let phaseSpecific = all.filter { !$0.phases.isEmpty && $0.matches(phase: phase) }
        let freshPhaseSpecific = phaseSpecific.filter { !recent.contains($0.id) }
        if !freshPhaseSpecific.isEmpty { return freshPhaseSpecific }

        // Anything suitable for this phase, including phase-agnostic messages.
        let suitable = all.filter { $0.matches(phase: phase) }
        let freshSuitable = suitable.filter { !recent.contains($0.id) }
        if !freshSuitable.isEmpty { return freshSuitable }

        // Everything has been seen recently. Saying something warm twice beats
        // saying nothing.
        return suitable.isEmpty ? all : suitable
    }
}
