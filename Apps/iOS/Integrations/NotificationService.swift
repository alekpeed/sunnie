import Foundation
import SunnieShared
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Local notification scheduling.
///
/// A shell for Phase 1: authorization and scheduling work, but no feature
/// schedules reminders yet — reminder rules land in Phase 3. It exists now so
/// the boundary is established and no view ever reaches UserNotifications
/// directly.
///
/// Permission is never requested at launch. The app is fully usable with
/// notifications denied, and asking before the user has seen why would be the
/// kind of pressure the tone rules forbid.
final class NotificationService: NotificationScheduling, @unchecked Sendable {

    private let log = SunnieLog(category: .notifications)

    func authorizationStatus() async -> NotificationAuthorization {
        #if canImport(UserNotifications)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.map(settings.authorizationStatus)
        #else
        return .notDetermined
        #endif
    }

    func requestAuthorization() async -> NotificationAuthorization {
        #if canImport(UserNotifications)
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            return granted ? .authorized : .denied
        } catch {
            log.debug("Notification authorization could not be requested.")
            return .denied
        }
        #else
        return .denied
        #endif
    }

    func schedule(_ reminder: ScheduledReminderRequest) async throws {
        #if canImport(UserNotifications)
        guard await authorizationStatus() == .authorized else {
            throw DomainError.permissionDenied(capability: "notifications")
        }

        let interval = reminder.fireDate.timeIntervalSinceNow
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        // Copy is resolved from content at delivery-planning time by the caller;
        // this service does not compose user-facing text.
        content.userInfo = [
            "messageID": reminder.messageID.rawValue,
            "route": reminder.route
        ]
        content.sound = reminder.respectsQuietHours ? nil : .default

        let request = UNNotificationRequest(
            identifier: reminder.id.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: interval, repeats: false
            )
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            throw DomainError.persistenceFailed(operation: "scheduleReminder")
        }
        #else
        throw DomainError.permissionDenied(capability: "notifications")
        #endif
    }

    func cancel(reminderID: UUID) async {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminderID.uuidString])
        #endif
    }

    #if canImport(UserNotifications)
    private static func map(
        _ status: UNAuthorizationStatus
    ) -> NotificationAuthorization {
        switch status {
        case .authorized, .ephemeral: .authorized
        case .provisional: .provisional
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
    #endif
}
