import Foundation
import SunnieShared

/// In-process publisher for typed domain events.
///
/// This is how one feature learns that another did something without importing
/// it (TECHNICAL_ARCHITECTURE.md §6). Logging a watering publishes
/// `plantCareLogged`; Today's summary provider observes it and invalidates. The
/// Jungle feature has no idea Today exists.
///
/// Delivery is best-effort and unordered by design. Subscribers react to events
/// but never rely on them for correctness — the durable record is always the
/// repository, so a missed event costs a stale summary, not lost data.
actor DomainEventBus: DomainEventPublishing {

    private var subscribers: [UUID: @Sendable (DomainEvent) async -> Void] = [:]

    func publish(_ event: DomainEvent) async {
        let handlers = subscribers.values
        for handler in handlers {
            await handler(event)
        }
    }

    /// Returns a token used to unsubscribe. Callers must unsubscribe when they
    /// go away, or the bus keeps their closure — and whatever it captures —
    /// alive for the app's lifetime.
    @discardableResult
    func subscribe(_ handler: @escaping @Sendable (DomainEvent) async -> Void) -> UUID {
        let token = UUID()
        subscribers[token] = handler
        return token
    }

    func unsubscribe(_ token: UUID) {
        subscribers[token] = nil
    }
}

/// A publisher that does nothing, for previews and for tests that do not care
/// about cross-feature effects.
struct NoOpEventPublisher: DomainEventPublishing {
    func publish(_ event: DomainEvent) async {}
}
