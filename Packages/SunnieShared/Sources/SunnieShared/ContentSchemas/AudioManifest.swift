import Foundation

/// The versioned audio manifest (AUDIO_MIDI_AND_SOUNDSCAPES.md §2 step 5, §8).
///
/// Every sound the app can make is registered here, with the semantic contexts it
/// belongs to. Features ask for a context; the manifest decides what plays. That
/// indirection is the whole point of the design: a screen never names a file, so
/// the creator can swap a rendered track for another, or replace a synthesised
/// bed with a recording, without touching a single feature.
///
/// The shape follows §8's worked example field for field — `id`, `version`,
/// `title`, `runtimeAsset`, `sourceType`, `loop`, `contexts`, `defaultGain`,
/// `creator` — with two additions that the specification's other sections require
/// but the example omits: the layer (§4, each layer has its own gain and enable
/// state) and the loop length (§12, "loop gap").

public struct AudioTrackDefinition: Identifiable, Hashable, Sendable, Codable {
    public let id: ContentID
    public let version: Int
    /// A localization key, not a title. §8's example shows literal text because
    /// it is describing the creator's own manifest; anything the app displays
    /// goes through the strings file.
    public let titleKey: String
    /// The bundled file, for rendered tracks. Nil for procedural ones, which
    /// have no file by definition.
    public let runtimeAsset: String?
    public let sourceType: AudioSourceType
    /// Which synthesised voice, for procedural tracks.
    public let proceduralVoice: AmbienceVoice?
    /// Which bell, for procedural bell tracks.
    public let bell: BellPreset?
    public let loops: Bool
    public let layer: AudioLayer
    public let contexts: [AudioContextTag]
    /// 0…1, before the layer gain and the master gain.
    public let defaultGain: Double
    public let licence: AudioLicence

    public init(
        id: ContentID,
        version: Int = 1,
        titleKey: String,
        runtimeAsset: String? = nil,
        sourceType: AudioSourceType,
        proceduralVoice: AmbienceVoice? = nil,
        bell: BellPreset? = nil,
        loops: Bool,
        layer: AudioLayer,
        contexts: [AudioContextTag],
        defaultGain: Double,
        licence: AudioLicence = .createdForThisApp
    ) {
        self.id = id
        self.version = version
        self.titleKey = titleKey
        self.runtimeAsset = runtimeAsset
        self.sourceType = sourceType
        self.proceduralVoice = proceduralVoice
        self.bell = bell
        self.loops = loops
        self.layer = layer
        self.contexts = contexts
        self.defaultGain = defaultGain
        self.licence = licence
    }

    /// Whether this track can make sound on a device that has only what is in
    /// the repository.
    ///
    /// Procedural tracks always can — that is their advantage. A rendered track
    /// can only when its file is present, and the caller supplies that answer
    /// because the shared package has no bundle to look in.
    public func isPlayable(assetExists: (String) -> Bool) -> Bool {
        switch sourceType {
        case .procedural:
            return proceduralVoice != nil || bell != nil
        case .renderedAudio:
            guard let runtimeAsset else { return false }
            return assetExists(runtimeAsset)
        case .runtimeMIDI:
            // Nothing ships on this path (ADR-029). A manifest that claims it is
            // treated as not playable rather than as an error at runtime; the
            // validator is where it is reported.
            return false
        }
    }
}

public struct AudioManifest: Hashable, Sendable, Codable {
    public let version: Int
    public let tracks: [AudioTrackDefinition]

    public init(version: Int, tracks: [AudioTrackDefinition]) {
        self.version = version
        self.tracks = tracks
    }

    public func track(id: ContentID) -> AudioTrackDefinition? {
        tracks.first { $0.id == id }
    }

    public func tracks(on layer: AudioLayer) -> [AudioTrackDefinition] {
        tracks.filter { $0.layer == layer }
    }

    public func tracks(taggedWith context: AudioContextTag) -> [AudioTrackDefinition] {
        tracks.filter { $0.contexts.contains(context) }
    }

    /// Every context any track claims, which is what the validator compares the
    /// known set against.
    public var declaredContexts: Set<AudioContextTag> {
        Set(tracks.flatMap(\.contexts))
    }
}

// MARK: - Validation

/// What can be wrong with a manifest (§2 step 7).
///
/// Separate from `ContentIssue` for the same reason the game and collection packs
/// have their own: an audio manifest fails in ways the other packs cannot — a
/// gain that would clip, a rendered track with no file named, a procedural track
/// naming a voice that does not exist.
public enum AudioContentIssue: Hashable, Sendable, CustomStringConvertible {
    case duplicateTrackID(ContentID)
    case gainOutOfRange(ContentID, Double)
    case renderedTrackWithoutAsset(ContentID)
    case proceduralTrackWithoutVoice(ContentID)
    case proceduralTrackWithAsset(ContentID)
    case trackWithoutContexts(ContentID)
    case runtimeMIDIWithoutApproval(ContentID)
    /// A context in §5's list that nothing is registered against. Not fatal —
    /// silence is a legitimate answer for a screen — but worth surfacing,
    /// because the usual cause is a typo in a tag.
    case contextWithNoTrack(AudioContextTag)
    /// Two tracks on a layer that cannot mix, both claiming the same context.
    /// Whichever wins would be arbitrary.
    case ambiguousMusicForContext(AudioContextTag, [ContentID])
    case bellTrackOnWrongLayer(ContentID)

    public var description: String {
        switch self {
        case .duplicateTrackID(let id):
            "Two audio tracks share the id \(id.rawValue)."
        case .gainOutOfRange(let id, let gain):
            "Track \(id.rawValue) has a default gain of \(gain), which is outside 0…1."
        case .renderedTrackWithoutAsset(let id):
            "Track \(id.rawValue) is rendered audio but names no runtime asset."
        case .proceduralTrackWithoutVoice(let id):
            "Track \(id.rawValue) is procedural but names neither a voice nor a bell."
        case .proceduralTrackWithAsset(let id):
            "Track \(id.rawValue) is procedural but also names a runtime asset."
        case .trackWithoutContexts(let id):
            "Track \(id.rawValue) has no contexts, so nothing can ever ask for it."
        case .runtimeMIDIWithoutApproval(let id):
            "Track \(id.rawValue) uses runtime MIDI, which needs an approval record (ADR-029)."
        case .contextWithNoTrack(let context):
            "No track is registered for the context \(context.rawValue)."
        case .ambiguousMusicForContext(let context, let ids):
            "More than one music track claims \(context.rawValue): "
                + ids.map(\.rawValue).sorted().joined(separator: ", ")
        case .bellTrackOnWrongLayer(let id):
            "Track \(id.rawValue) names a bell but is not on the meditation bell layer."
        }
    }
}

public enum AudioManifestValidator {

    /// The contexts §5 lists, which is what "a context with no track" is
    /// measured against.
    public static let specifiedContexts: [AudioContextTag] = [
        .day, .afternoon, .night,
        .jungle, .travelScrapbook, .today, .plantCare,
        .wellness, .meditation, .breathing, .game, .reward, .sunnieHome
    ]

    public static func validate(_ manifest: AudioManifest) -> [AudioContentIssue] {
        var issues: [AudioContentIssue] = []
        var seen: Set<ContentID> = []

        for track in manifest.tracks {
            if !seen.insert(track.id).inserted {
                issues.append(.duplicateTrackID(track.id))
            }
            if track.defaultGain < 0 || track.defaultGain > 1 {
                issues.append(.gainOutOfRange(track.id, track.defaultGain))
            }
            if track.contexts.isEmpty {
                issues.append(.trackWithoutContexts(track.id))
            }
            if track.bell != nil, track.layer != .meditationBell {
                issues.append(.bellTrackOnWrongLayer(track.id))
            }

            switch track.sourceType {
            case .renderedAudio:
                if track.runtimeAsset?.isEmpty ?? true {
                    issues.append(.renderedTrackWithoutAsset(track.id))
                }
            case .procedural:
                if track.proceduralVoice == nil, track.bell == nil {
                    issues.append(.proceduralTrackWithoutVoice(track.id))
                }
                if track.runtimeAsset != nil {
                    issues.append(.proceduralTrackWithAsset(track.id))
                }
            case .runtimeMIDI:
                issues.append(.runtimeMIDIWithoutApproval(track.id))
            }
        }

        // Music is the one layer where two tracks a request cannot tell apart is
        // a genuine defect rather than a choice: they cannot both play, so the
        // manifest has not actually decided anything.
        //
        // Sharing *a* context is fine and expected — three tracks tagged
        // `theme.jungle` differ by the cycle tag beside it, and the director
        // scores on the whole set. Sharing the *entire* set is the defect: no
        // request can ever prefer one, so which plays is arbitrary.
        var musicByContextSet: [Set<AudioContextTag>: [ContentID]] = [:]
        for track in manifest.tracks where track.layer == .music {
            musicByContextSet[Set(track.contexts), default: []].append(track.id)
        }
        for (contexts, ids) in musicByContextSet where ids.count > 1 {
            let representative = contexts.map(\.rawValue).sorted().first ?? ""
            issues.append(
                .ambiguousMusicForContext(AudioContextTag(representative), ids)
            )
        }

        let declared = manifest.declaredContexts
        for context in specifiedContexts where !declared.contains(context) {
            issues.append(.contextWithNoTrack(context))
        }

        return issues
    }
}
