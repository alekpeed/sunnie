import Foundation
import SwiftData
import SunnieShared

/// SwiftData schema version 6 — games.
///
/// **Additive, like V2 through V5.** Saved sessions and finished results are new
/// models; nothing existing changes shape.
///
/// Five additive versions in a row. As noted on `SunnieSchemaV5`, this is a
/// streak rather than a policy: the namespace freeze in ADR-017 is still owed
/// the first time an existing model has to change, and it grows slightly larger
/// each phase that avoids it.
enum SunnieSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    static var models: [any PersistentModel.Type] {
        SunnieSchemaV5.models + [
            SDGameSession.self,
            SDGameResult.self
        ]
    }
}

/// A saved game in progress.
///
/// The moves are the save file. Nothing about the board's *layout* is stored —
/// which columns a grid had, which order the options were drawn in — so a build
/// that changes a board still resumes an old session correctly by replaying the
/// same moves through the same engine.
///
/// The seed is a string rather than an integer because it is a `UInt64` and
/// SwiftData's integer storage is signed. Round-tripping through a bit pattern
/// would work and would also be the kind of cleverness that silently breaks a
/// migration; the decimal text is unambiguous.
@Model
final class SDGameSession {
    var id: UUID = UUID()
    var gameID: String = ""
    var puzzleID: String = ""
    var difficultyRaw: String = GameDifficulty.steady.rawValue
    var seedRaw: String = "0"
    /// `yyyy-MM-dd` when this session is a day's puzzle, empty otherwise.
    /// Stored as an empty string rather than nil so the predicate that finds
    /// today's session does not have to reason about optionals.
    var dailyKey: String = ""
    var encodedMoves: Data = Data()
    var statusRaw: String = GameSessionStatus.inProgress.rawValue
    var startedAt: Date = Date()
    var lastPlayedAt: Date = Date()
    var elapsedSeconds: Int = 0

    init(
        id: UUID = UUID(),
        gameID: String = "",
        puzzleID: String = "",
        difficultyRaw: String = GameDifficulty.steady.rawValue,
        seedRaw: String = "0",
        dailyKey: String = "",
        encodedMoves: Data = Data(),
        statusRaw: String = GameSessionStatus.inProgress.rawValue,
        startedAt: Date = Date(),
        lastPlayedAt: Date = Date(),
        elapsedSeconds: Int = 0
    ) {
        self.id = id
        self.gameID = gameID
        self.puzzleID = puzzleID
        self.difficultyRaw = difficultyRaw
        self.seedRaw = seedRaw
        self.dailyKey = dailyKey
        self.encodedMoves = encodedMoves
        self.statusRaw = statusRaw
        self.startedAt = startedAt
        self.lastPlayedAt = lastPlayedAt
        self.elapsedSeconds = elapsedSeconds
    }
}

/// A finished game.
///
/// Kept forever and never overwritten by a replay: the record is what happened
/// on a particular afternoon, and a later attempt is a second record, not a
/// correction of the first.
@Model
final class SDGameResult {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var gameID: String = ""
    var puzzleID: String = ""
    var difficultyRaw: String = GameDifficulty.steady.rawValue
    var completionRaw: String = GameCompletion.setAside.rawValue
    var score: Int = 0
    var stepsCorrect: Int = 0
    var stepsTotal: Int = 0
    var hintsUsed: Int = 0
    var elapsedSeconds: Int = 0
    /// The per-step explanations, stored whole. They are read and written with
    /// the result and never queried individually — the same reasoning as the
    /// encoded blobs on recipes and preferences.
    var encodedSteps: Data = Data()
    var dailyKey: String = ""
    var finishedAt: Date = Date()

    init(
        id: UUID = UUID(),
        sessionID: UUID = UUID(),
        gameID: String = "",
        puzzleID: String = "",
        difficultyRaw: String = GameDifficulty.steady.rawValue,
        completionRaw: String = GameCompletion.setAside.rawValue,
        score: Int = 0,
        stepsCorrect: Int = 0,
        stepsTotal: Int = 0,
        hintsUsed: Int = 0,
        elapsedSeconds: Int = 0,
        encodedSteps: Data = Data(),
        dailyKey: String = "",
        finishedAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.gameID = gameID
        self.puzzleID = puzzleID
        self.difficultyRaw = difficultyRaw
        self.completionRaw = completionRaw
        self.score = score
        self.stepsCorrect = stepsCorrect
        self.stepsTotal = stepsTotal
        self.hintsUsed = hintsUsed
        self.elapsedSeconds = elapsedSeconds
        self.encodedSteps = encodedSteps
        self.dailyKey = dailyKey
        self.finishedAt = finishedAt
    }
}
