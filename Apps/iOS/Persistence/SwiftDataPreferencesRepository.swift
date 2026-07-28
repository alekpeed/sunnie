import Foundation
import SwiftData
import SunnieShared

/// Profile and preferences storage.
///
/// Preferences round-trip through JSON. If a stored blob cannot be decoded — an
/// older build reading a newer shape, or a corrupted record — the defaults are
/// returned rather than throwing. Settings failing to load should never keep the
/// app from opening.
@ModelActor
actor SwiftDataPreferencesRepository: PreferencesRepository {

    private var log: SunnieLog { SunnieLog(category: .persistence) }

    func profile() async throws -> UserProfile {
        if let existing = try fetchProfile() {
            return ModelMapping.domain(existing)
        }
        let model = SDUserProfile(
            displayName: DefaultProfile.displayName,
            preferredNickname: DefaultProfile.nickname
        )
        modelContext.insert(model)
        try? modelContext.save()
        return ModelMapping.domain(model)
    }

    func save(_ profile: UserProfile) async throws {
        do {
            if let existing = try fetchProfile() {
                ModelMapping.apply(profile, to: existing)
            } else {
                let model = SDUserProfile()
                ModelMapping.apply(profile, to: model)
                modelContext.insert(model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveUserProfile")
        }
    }

    func preferences() async throws -> UserPreferences {
        guard let stored = try fetchPreferences() else { return .default }
        do {
            return try JSONDecoder().decode(UserPreferences.self, from: stored.encoded)
        } catch {
            log.error("Stored preferences could not be decoded; using defaults.")
            return .default
        }
    }

    func save(_ preferences: UserPreferences) async throws {
        do {
            let encoded = try JSONEncoder().encode(preferences)
            if let existing = try fetchPreferences() {
                existing.encoded = encoded
                existing.modifiedAt = Date()
            } else {
                modelContext.insert(SDUserPreferences(encoded: encoded))
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "saveUserPreferences")
        }
    }

    private func fetchProfile() throws -> SDUserProfile? {
        var descriptor = FetchDescriptor<SDUserProfile>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchPreferences() throws -> SDUserPreferences? {
        var descriptor = FetchDescriptor<SDUserPreferences>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

/// Durable queue for Watch actions that have not been applied yet.
@ModelActor
actor SwiftDataPendingWatchActionRepository: PendingWatchActionRepository {

    func enqueue(_ action: PendingWatchAction) async throws -> SaveOutcome<PendingWatchAction> {
        let key = action.actionKey.rawValue
        var descriptor = FetchDescriptor<SDPendingWatchAction>(
            predicate: #Predicate { $0.actionKey == key }
        )
        descriptor.fetchLimit = 1

        // A redelivered transfer must not queue the same action twice.
        if let existing = try modelContext.fetch(descriptor).first {
            return .alreadyExisted(ModelMapping.domain(existing))
        }

        do {
            let model = ModelMapping.model(action)
            modelContext.insert(model)
            try modelContext.save()
            return .created(action)
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "enqueueWatchAction")
        }
    }

    func unprocessedActions() async throws -> [PendingWatchAction] {
        let pending = PendingWatchActionState.pending.rawValue
        let descriptor = FetchDescriptor<SDPendingWatchAction>(
            predicate: #Predicate { $0.stateRaw == pending },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor).map(ModelMapping.domain)
        } catch {
            throw DomainError.persistenceFailed(operation: "unprocessedWatchActions")
        }
    }

    func markProcessed(actionID: UUID, at date: Date) async throws {
        var descriptor = FetchDescriptor<SDPendingWatchAction>(
            predicate: #Predicate { $0.id == actionID }
        )
        descriptor.fetchLimit = 1
        do {
            guard let model = try modelContext.fetch(descriptor).first else { return }
            model.state = .processed
            model.processedAt = date
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw DomainError.persistenceFailed(operation: "markWatchActionProcessed")
        }
    }
}

extension SDPendingWatchAction {
    var state: PendingWatchActionState {
        get { PendingWatchActionState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }
}

/// Seed values for a fresh install.
///
/// The app is built for one person, so the profile starts populated rather than
/// forcing a name-entry step. Both values are editable in Settings.
enum DefaultProfile {
    static let displayName = "Vanessa"
    static let nickname = "Noonies"
}
