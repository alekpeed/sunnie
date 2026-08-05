import Foundation
import SunnieShared

/// Mapping for the models added in schema V6.
extension ModelMapping {

    /// Moves and step results are the two encoded blobs in this schema. Both
    /// decode to an empty collection on failure rather than throwing: an
    /// unreadable move list costs the player their progress on one puzzle, while
    /// a throw here would take out the whole games list.
    private static var gameDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var gameEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    // MARK: - Sessions

    static func domain(_ model: SDGameSession) -> GameSessionState {
        let moves = (try? gameDecoder.decode([GameMove].self, from: model.encodedMoves)) ?? []

        return GameSessionState(
            id: model.id,
            gameID: ContentID(rawValue: model.gameID),
            puzzleID: ContentID(rawValue: model.puzzleID),
            difficulty: GameDifficulty(rawValue: model.difficultyRaw) ?? .steady,
            seed: UInt64(model.seedRaw) ?? 0,
            dailyKey: model.dailyKey.isEmpty ? nil : model.dailyKey,
            moves: moves,
            // An unreadable status reads as in-progress, which is the outcome
            // that loses nothing: the session stays resumable rather than being
            // presented as finished when it may not be.
            status: GameSessionStatus(rawValue: model.statusRaw) ?? .inProgress,
            startedAt: model.startedAt,
            lastPlayedAt: model.lastPlayedAt,
            elapsedSeconds: model.elapsedSeconds
        )
    }

    static func apply(_ session: GameSessionState, to model: SDGameSession) {
        model.id = session.id
        model.gameID = session.gameID.rawValue
        model.puzzleID = session.puzzleID.rawValue
        model.difficultyRaw = session.difficulty.rawValue
        model.seedRaw = String(session.seed)
        model.dailyKey = session.dailyKey ?? ""
        model.encodedMoves = (try? gameEncoder.encode(session.moves)) ?? Data()
        model.statusRaw = session.status.rawValue
        model.startedAt = session.startedAt
        model.lastPlayedAt = session.lastPlayedAt
        model.elapsedSeconds = session.elapsedSeconds
    }

    // MARK: - Results

    static func domain(_ model: SDGameResult) -> GameResult {
        let steps = (try? gameDecoder.decode(
            [GameStepResult].self, from: model.encodedSteps
        )) ?? []

        return GameResult(
            id: model.id,
            sessionID: model.sessionID,
            gameID: ContentID(rawValue: model.gameID),
            puzzleID: ContentID(rawValue: model.puzzleID),
            difficulty: GameDifficulty(rawValue: model.difficultyRaw) ?? .steady,
            completion: GameCompletion(rawValue: model.completionRaw) ?? .setAside,
            score: model.score,
            stepsCorrect: model.stepsCorrect,
            stepsTotal: model.stepsTotal,
            hintsUsed: model.hintsUsed,
            elapsedSeconds: model.elapsedSeconds,
            steps: steps,
            dailyKey: model.dailyKey.isEmpty ? nil : model.dailyKey,
            finishedAt: model.finishedAt
        )
    }

    static func apply(_ result: GameResult, to model: SDGameResult) {
        model.id = result.id
        model.sessionID = result.sessionID
        model.gameID = result.gameID.rawValue
        model.puzzleID = result.puzzleID.rawValue
        model.difficultyRaw = result.difficulty.rawValue
        model.completionRaw = result.completion.rawValue
        model.score = result.score
        model.stepsCorrect = result.stepsCorrect
        model.stepsTotal = result.stepsTotal
        model.hintsUsed = result.hintsUsed
        model.elapsedSeconds = result.elapsedSeconds
        model.encodedSteps = (try? gameEncoder.encode(result.steps)) ?? Data()
        model.dailyKey = result.dailyKey ?? ""
        model.finishedAt = result.finishedAt
    }
}
