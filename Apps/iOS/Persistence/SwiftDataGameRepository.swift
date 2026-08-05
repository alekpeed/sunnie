import Foundation
import SwiftData
import SunnieShared

/// Saved sessions and finished results.
///
/// Same `@ModelActor` discipline as every other repository: check-then-insert
/// inside the actor's serialized context rather than a uniqueness attribute,
/// because `@Attribute(.unique)` and CloudKit do not coexist (ADR-011).
@ModelActor
actor SwiftDataGameRepository: GameRepository {

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    // MARK: - Sessions

    func resumableSessions() async throws -> [GameSessionState] {
        let completed = GameSessionStatus.completed.rawValue
        var descriptor = FetchDescriptor<SDGameSession>(
            predicate: #Predicate<SDGameSession> { $0.statusRaw != completed },
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.resumableLimit
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            log.error("Fetching resumable game sessions failed.")
            throw DomainError.persistenceFailed(operation: "resumableSessions")
        }
    }

    /// How many unfinished games the home screen offers to continue.
    ///
    /// Bounded because a long list of half-played puzzles reads as a pile of
    /// unfinished business, which is exactly the feeling this app is not for.
    /// The older ones are still stored and still resumable from the game's own
    /// page.
    static let resumableLimit = 10

    func session(id: UUID) async throws -> GameSessionState? {
        var descriptor = FetchDescriptor<SDGameSession>(
            predicate: #Predicate<SDGameSession> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { ModelMapping.domain($0) }
    }

    func session(dailyKey: String) async throws -> GameSessionState? {
        var descriptor = FetchDescriptor<SDGameSession>(
            predicate: #Predicate<SDGameSession> { $0.dailyKey == dailyKey },
            sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map { ModelMapping.domain($0) }
    }

    func save(_ session: GameSessionState) async throws {
        let id = session.id
        var descriptor = FetchDescriptor<SDGameSession>(
            predicate: #Predicate<SDGameSession> { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                ModelMapping.apply(session, to: existing)
            } else {
                let model = SDGameSession()
                ModelMapping.apply(session, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveGameSession")
        }
    }

    func deleteSession(id: UUID) async throws {
        do {
            var descriptor = FetchDescriptor<SDGameSession>(
                predicate: #Predicate<SDGameSession> { $0.id == id }
            )
            descriptor.fetchLimit = 1
            if let model = try modelContext.fetch(descriptor).first {
                modelContext.delete(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "deleteGameSession")
        }
    }

    // MARK: - Results

    func results(limit: Int) async throws -> [GameResult] {
        var descriptor = FetchDescriptor<SDGameResult>(
            sortBy: [SortDescriptor(\.finishedAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(1, limit)
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "gameResults")
        }
    }

    func results(gameID: ContentID, limit: Int) async throws -> [GameResult] {
        let raw = gameID.rawValue
        var descriptor = FetchDescriptor<SDGameResult>(
            predicate: #Predicate<SDGameResult> { $0.gameID == raw },
            sortBy: [SortDescriptor(\.finishedAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(1, limit)
        do {
            return try modelContext.fetch(descriptor).map { ModelMapping.domain($0) }
        } catch {
            throw DomainError.persistenceFailed(operation: "gameResultsForGame")
        }
    }

    /// Stores a result unless the session already has one.
    ///
    /// Keyed on the session rather than the result's own id, so finishing the
    /// same session twice — a double tap, a resumed screen re-submitting — is one
    /// record. The progression award is separately idempotent on the puzzle, so
    /// neither path can double-count.
    func save(_ result: GameResult) async throws -> SaveOutcome<GameResult> {
        let sessionID = result.sessionID
        var descriptor = FetchDescriptor<SDGameResult>(
            predicate: #Predicate<SDGameResult> { $0.sessionID == sessionID }
        )
        descriptor.fetchLimit = 1

        do {
            if let existing = try modelContext.fetch(descriptor).first {
                return .alreadyExisted(ModelMapping.domain(existing))
            }
            let model = SDGameResult()
            ModelMapping.apply(result, to: model)
            modelContext.insert(model)
            try modelContext.save()
            return .created(ModelMapping.domain(model))
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveGameResult")
        }
    }

    func hasFinished(puzzleID: ContentID) async throws -> Bool {
        let raw = puzzleID.rawValue
        let setAside = GameCompletion.setAside.rawValue
        var descriptor = FetchDescriptor<SDGameResult>(
            predicate: #Predicate<SDGameResult> {
                $0.puzzleID == raw && $0.completionRaw != setAside
            }
        )
        descriptor.fetchLimit = 1
        return try !modelContext.fetch(descriptor).isEmpty
    }
}
